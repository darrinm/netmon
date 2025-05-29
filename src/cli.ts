#!/usr/bin/env node

import { program } from 'commander';
import * as path from 'path';
import * as os from 'os';
import chalk from 'chalk';
import { NetworkMonitor } from './monitor';
import { MetricsStorage } from './storage';
import { StatsAnalyzer } from './stats';
import { Display } from './display';
import { MonitorConfig } from './types';

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
    
    await storage.init();
    
    console.log(chalk.bold.green('🚀 Starting network monitor...'));
    console.log(chalk.gray(`Monitoring ${config.pingHost} every ${options.interval}s`));
    console.log(chalk.gray(`Data stored in: ${config.dataFile}`));
    console.log(chalk.gray('Press Ctrl+C to stop\n'));

    monitor.start(async (metric) => {
      await storage.save(metric);
      Display.showCurrentStatus(metric);
      
      const last24h = StatsAnalyzer.getMetricsForPeriod(storage.getMetrics(), 24);
      const stats = new Map([
        ['Last Hour', StatsAnalyzer.analyze(StatsAnalyzer.getMetricsForPeriod(storage.getMetrics(), 1), 'Last Hour')],
        ['Last 24 Hours', StatsAnalyzer.analyze(last24h, 'Last 24 Hours')],
        ['All Time', StatsAnalyzer.analyze(storage.getMetrics(), 'All Time')]
      ]);
      
      Display.showStats(stats);
    });

    process.on('SIGINT', () => {
      console.log(chalk.yellow('\n\n👋 Stopping monitor...'));
      monitor.stop();
      process.exit(0);
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
    const stats = StatsAnalyzer.analyze(metrics, period);
    
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
  .command('clear')
  .description('Clear all monitoring data')
  .option('-d, --data-file <path>', 'Data file path', DEFAULT_CONFIG.dataFile)
  .action(async (options) => {
    const storage = new MetricsStorage(options.dataFile);
    await storage.init();
    storage.clear();
    console.log(chalk.green('✓ Monitoring data cleared.'));
  });

program.parse();