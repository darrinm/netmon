#!/usr/bin/env node

import { program } from 'commander';
import * as path from 'path';
import * as os from 'os';
import chalk from 'chalk';
import { NetworkMonitor } from './monitor';
import { MetricsStorage } from './storage';
import { StatsAnalyzer } from './stats';
import { Display } from './display';
import { OutageTracker } from './outage-tracker';
import { MonitorConfig, NetworkMetric, NetworkStats, OutageEvent } from './types';
import { TerminalUtils } from './terminal-utils';

const DEFAULT_CONFIG: MonitorConfig = {
  pingHost: '8.8.8.8',
  dnsServer: '8.8.8.8',
  interval: 30000,
  dataFile: path.join(os.homedir(), '.netmon', 'metrics.json')
};

program
  .name('netmon')
  .description('Monitor network connection quality')
  .version('1.0.0');

program
  .command('monitor')
  .description('Start monitoring network connection')
  .option('-h, --host <host>', 'Host to ping', DEFAULT_CONFIG.pingHost)
  .option('-i, --interval <seconds>', 'Monitoring interval in seconds', '30')
  .option('-d, --data-file <path>', 'Data file path', DEFAULT_CONFIG.dataFile)
  .action(async (options) => {
    const config: MonitorConfig = {
      pingHost: options.host,
      dnsServer: DEFAULT_CONFIG.dnsServer,
      interval: parseInt(options.interval) * 1000,
      dataFile: options.dataFile
    };

    const monitor = new NetworkMonitor(config);
    const storage = new MetricsStorage(config.dataFile);
    const outageTracker = new OutageTracker();
    
    await storage.init();
    outageTracker.loadOutages(storage.getOutages());
    
    console.log(chalk.bold.green('🚀 Starting network monitor...'));
    console.log(chalk.gray(`Monitoring ${config.pingHost} every ${options.interval}s`));
    console.log(chalk.gray(`Data stored in: ${config.dataFile}`));
    console.log(chalk.gray('Press Ctrl+C to stop\n'));

    // Enter alternate screen buffer and hide cursor
    TerminalUtils.enterAlternateScreen();
    TerminalUtils.hideCursor();
    
    let sessionCollections = 0;
    let lastMetric: NetworkMetric | null = null;
    let lastStats: Map<string, NetworkStats> | null = null;
    let lastOutage: OutageEvent | null = null;
    let recentMetrics: NetworkMetric[] = [];
    
    // Pre-populate with recent historical data if available
    const existingMetrics = storage.getMetrics();
    const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
    recentMetrics = existingMetrics.filter(m => {
      const timestamp = m.timestamp instanceof Date ? m.timestamp : new Date(m.timestamp);
      return timestamp >= fiveMinAgo;
    });
    
    // Handle terminal resize
    const handleResize = () => {
      if (lastMetric && lastStats) {
        Display.showMonitoringDisplay(lastMetric, lastStats, sessionCollections, lastOutage, recentMetrics);
      }
    };
    process.stdout.on('resize', handleResize);
    
    monitor.start(async (metric) => {
      sessionCollections++;
      const outageEvent = outageTracker.processMetric(metric);
      await storage.save(metric);
      
      if (outageEvent) {
        await storage.saveOutage(outageEvent);
        // Outage alerts will be shown in the unified display
      }
      
      const currentOutage = outageTracker.getCurrentOutage();
      const allMetrics = storage.getMetrics();
      const last5min = StatsAnalyzer.getMetricsForPeriod(allMetrics, 0.0833); // 5 min = 0.0833 hours
      const lastHour = StatsAnalyzer.getMetricsForPeriod(allMetrics, 1);
      const last24h = StatsAnalyzer.getMetricsForPeriod(allMetrics, 24);
      const allOutages = storage.getOutages();
      
      const stats = new Map([
        ['Last 5 Min', StatsAnalyzer.analyze(last5min, 'Last 5 Min', allOutages)],
        ['Last Hour', StatsAnalyzer.analyze(lastHour, 'Last Hour', allOutages)],
        ['Last 24 Hours', StatsAnalyzer.analyze(last24h, 'Last 24 Hours', allOutages)],
        ['All Time', StatsAnalyzer.analyze(allMetrics, 'All Time', allOutages)]
      ]);
      
      // Store for resize handler and graph
      lastMetric = metric;
      lastStats = stats;
      lastOutage = currentOutage;
      
      // Keep recent metrics for graph (last 5 minutes)
      recentMetrics.push(metric);
      const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
      recentMetrics = recentMetrics.filter(m => {
        // Ensure timestamp is a Date object for comparison
        const timestamp = m.timestamp instanceof Date ? m.timestamp : new Date(m.timestamp);
        return timestamp >= fiveMinAgo;
      });
      
      // Single unified display update
      Display.showMonitoringDisplay(metric, stats, sessionCollections, currentOutage, recentMetrics);
    });

    process.on('SIGINT', () => {
      TerminalUtils.exitAlternateScreen();
      TerminalUtils.showCursor();
      console.log(chalk.yellow('\n👋 Stopping monitor...'));
      monitor.stop();
      process.exit(0);
    });

    // Ensure cleanup on other exit scenarios
    process.on('exit', () => {
      TerminalUtils.exitAlternateScreen();
      TerminalUtils.showCursor();
    });
  });

program
  .command('stats')
  .description('Show network statistics')
  .option('-p, --period <hours>', 'Stats period in hours (0 for all time)', '24')
  .option('-d, --data-file <path>', 'Data file path', DEFAULT_CONFIG.dataFile)
  .action(async (options) => {
    const storage = new MetricsStorage(options.dataFile);
    await storage.init();
    
    const hours = parseInt(options.period);
    const metrics = hours === 0 
      ? storage.getMetrics()
      : StatsAnalyzer.getMetricsForPeriod(storage.getMetrics(), hours);
    
    if (metrics.length === 0) {
      console.log(chalk.yellow('No data available for the specified period.'));
      return;
    }

    const period = hours === 0 ? 'All Time' : `Last ${hours} Hours`;
    const outages = storage.getOutages();
    const stats = StatsAnalyzer.analyze(metrics, period, outages);
    
    Display.showDetailedStats(stats);
  });

program
  .command('history')
  .description('Show recent monitoring history')
  .option('-n, --number <count>', 'Number of recent entries to show', '20')
  .option('-d, --data-file <path>', 'Data file path', DEFAULT_CONFIG.dataFile)
  .action(async (options) => {
    const storage = new MetricsStorage(options.dataFile);
    await storage.init();
    
    const count = parseInt(options.number);
    const metrics = storage.getLatest(count);
    
    if (metrics.length === 0) {
      console.log(chalk.yellow('No monitoring data available.'));
      return;
    }

    Display.showHistory(metrics);
  });

program
  .command('outages')
  .description('Show outage history')
  .option('-p, --period <hours>', 'Period in hours (0 for all time)', '24')
  .option('-d, --data-file <path>', 'Data file path', DEFAULT_CONFIG.dataFile)
  .action(async (options) => {
    const storage = new MetricsStorage(options.dataFile);
    await storage.init();
    
    const hours = parseInt(options.period);
    const since = hours === 0 ? undefined : new Date(Date.now() - hours * 60 * 60 * 1000);
    const outages = storage.getOutages(since);
    
    if (outages.length === 0) {
      console.log(chalk.green('No outages recorded for the specified period.'));
      return;
    }

    Display.showOutages(outages);
    
    const totalDuration = outages.reduce((sum, o) => {
      const duration = o.duration || (Date.now() - o.startTime.getTime());
      return sum + duration;
    }, 0);
    
    console.log(chalk.bold(`\nTotal Outages: ${outages.length}`));
    console.log(chalk.bold(`Total Downtime: ${Display.formatDuration(Math.round(totalDuration / 1000))}`));
  });

program
  .command('clear')
  .description('Clear all monitoring data')
  .option('-d, --data-file <path>', 'Data file path', DEFAULT_CONFIG.dataFile)
  .action(async (options) => {
    const storage = new MetricsStorage(options.dataFile);
    await storage.init();
    await storage.clear();
    console.log(chalk.green('✓ Monitoring data cleared.'));
  });

program.parse();