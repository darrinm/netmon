import chalk from 'chalk';
import Table from 'cli-table3';
import { NetworkMetric, NetworkStats, OutageEvent } from './types';
import { Graph } from './graph';

export class Display {
  static formatLatency(ms: number): string {
    if (ms === 0) return chalk.gray('N/A');
    if (ms < 50) return chalk.green(`${ms}ms`);
    if (ms < 100) return chalk.yellow(`${ms}ms`);
    return chalk.red(`${ms}ms`);
  }

  static formatPacketLoss(loss: number): string {
    if (loss === 0) return chalk.green('0%');
    if (loss < 5) return chalk.yellow(`${loss}%`);
    return chalk.red(`${loss}%`);
  }

  static formatUptime(uptime: number): string {
    if (uptime >= 99) return chalk.green(`${uptime}%`);
    if (uptime >= 95) return chalk.yellow(`${uptime}%`);
    return chalk.red(`${uptime}%`);
  }

  static formatDuration(seconds: number): string {
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
  }

  private static isFirstRun = true;

  static showMonitoringDisplay(
    metric: NetworkMetric,
    stats: Map<string, NetworkStats>,
    sessionCollections: number,
    currentOutage: OutageEvent | null,
    recentMetrics: NetworkMetric[] = []
  ): void {
    // Always move to home position and clear screen in alternate buffer
    process.stdout.write('\x1B[H\x1B[2J');

    // Get terminal dimensions
    const termWidth = process.stdout.columns || 80;
    const termHeight = process.stdout.rows || 24;

    // Build entire display in memory first
    const output: string[] = [];
    
    // Compact header
    const title = '🌐 Network Monitor';
    const updateInfo = `Updated: ${metric.timestamp.toLocaleTimeString()} | Session: ${sessionCollections}`;
    const padding = Math.max(0, termWidth - title.length - updateInfo.length - 2);
    output.push(chalk.bold.cyan(title) + ' '.repeat(padding) + chalk.gray(updateInfo));
    output.push(chalk.gray('─'.repeat(termWidth)));

    // Status table
    const statusTable = new Table({
      head: ['Metric', 'Value', 'Status'],
      colWidths: [20, 20, 15]
    });

    const pingStatus = metric.ping.packetLoss === 100 ? chalk.red('✗ Down') : chalk.green('✓ Up');
    const dnsStatus = metric.dns.success ? chalk.green('✓ OK') : chalk.red('✗ Failed');

    statusTable.push(
      ['Ping Host', metric.ping.host, pingStatus],
      ['Latency (avg)', this.formatLatency(metric.ping.avg), ''],
      ['Packet Loss', this.formatPacketLoss(metric.ping.packetLoss), ''],
      ['DNS Response', `${metric.dns.responseTime}ms`, dnsStatus]
    );

    output.push(statusTable.toString());

    // Outage warning if active
    if (currentOutage) {
      const duration = Date.now() - currentOutage.startTime.getTime();
      output.push('');
      output.push(chalk.bold.red(`⚠️  ONGOING OUTAGE: ${this.formatDuration(Math.round(duration / 1000))}`));
    }

    // Statistics
    output.push(this.showStats(stats));

    // Calculate available space for graph
    const currentLines = output.length + 2; // +2 for footer
    const availableLines = termHeight - currentLines - 1;
    
    // Latency graph if we have enough data and space
    if (recentMetrics.length > 10 && availableLines > 5) {
      output.push('');
      const graphWidth = Math.min(termWidth - 10, 80);
      const graphHeight = Math.min(8, availableLines - 2);
      const graphLines = Graph.drawLatencyGraph(recentMetrics, graphWidth, graphHeight);
      output.push(...graphLines);
    }

    // Footer
    const footerSpace = termHeight - output.length - 2;
    if (footerSpace > 0) {
      output.push('\n'.repeat(footerSpace));
    }
    
    output.push(chalk.gray('─'.repeat(termWidth)));
    const interval = sessionCollections > 1 ? Math.round((metric.timestamp.getTime() - this.lastUpdateTime) / 1000) : 1;
    output.push(chalk.gray('Press Ctrl+C to exit  |  ' + 
      `Monitoring ${metric.ping.host} every ${interval}s`));
    
    this.lastUpdateTime = metric.timestamp.getTime();

    // Ensure we don't exceed terminal height
    const totalLines = output.length;
    if (totalLines > termHeight) {
      // Trim from the middle (keep header and footer)
      const toRemove = totalLines - termHeight + 1;
      output.splice(termHeight - 10, toRemove);
    }

    // Write everything at once
    console.log(output.join('\n'));
  }

  private static lastUpdateTime: number = Date.now();

  static showCurrentStatus(metric: NetworkMetric): void {
    // This method is now deprecated in favor of showMonitoringDisplay
    console.log('Use showMonitoringDisplay instead');
  }

  static showStats(stats: Map<string, NetworkStats>): string {
    const output: string[] = [];
    output.push('');
    output.push(chalk.bold.cyan('📊 Network Statistics'));

    const statsTable = new Table({
      head: ['Period', 'Uptime', 'Avg Latency', 'Packet Loss', 'Outages', 'Downtime', 'Samples'],
      colWidths: [14, 9, 12, 12, 9, 11, 9],
      style: { 'padding-left': 0, 'padding-right': 0 }
    });

    stats.forEach((stat, period) => {
      statsTable.push([
        period,
        this.formatUptime(stat.pingStats.uptime),
        this.formatLatency(stat.pingStats.avgLatency),
        this.formatPacketLoss(stat.pingStats.avgPacketLoss),
        stat.outageStats.totalOutages > 0 
          ? chalk.red(stat.outageStats.totalOutages.toString())
          : chalk.green('0'),
        stat.outageStats.totalDuration > 0
          ? chalk.red(this.formatDuration(stat.outageStats.totalDuration))
          : chalk.green('0s'),
        stat.samples.toString()
      ]);
    });

    output.push(statsTable.toString());
    return output.join('\n');
  }

  static showDetailedStats(stats: NetworkStats): void {
    console.log(chalk.bold.cyan(`\n📈 Detailed Statistics - ${stats.period}\n`));

    const table = new Table();
    
    table.push(
      [chalk.bold('Time Range'), `${stats.startTime.toLocaleString()} - ${stats.endTime.toLocaleString()}`],
      [chalk.bold('Total Samples'), stats.samples],
      ['', ''],
      [chalk.bold.underline('Ping Statistics'), ''],
      ['Average Latency', this.formatLatency(stats.pingStats.avgLatency)],
      ['Min Latency', this.formatLatency(stats.pingStats.minLatency)],
      ['Max Latency', this.formatLatency(stats.pingStats.maxLatency)],
      ['Average Packet Loss', this.formatPacketLoss(stats.pingStats.avgPacketLoss)],
      ['Uptime', this.formatUptime(stats.pingStats.uptime)],
      ['', ''],
      [chalk.bold.underline('DNS Statistics'), ''],
      ['Average Response Time', `${stats.dnsStats.avgResponseTime}ms`],
      ['Success Rate', this.formatUptime(stats.dnsStats.successRate)],
      ['', ''],
      [chalk.bold.underline('Outage Statistics'), ''],
      ['Total Outages', stats.outageStats.totalOutages > 0 
        ? chalk.red(stats.outageStats.totalOutages.toString())
        : chalk.green('0')],
      ['Total Downtime', stats.outageStats.totalDuration > 0
        ? chalk.red(this.formatDuration(stats.outageStats.totalDuration))
        : chalk.green('0s')],
      ['Average Outage Duration', stats.outageStats.avgDuration > 0
        ? this.formatDuration(stats.outageStats.avgDuration)
        : 'N/A'],
      ['Longest Outage', stats.outageStats.longestOutage > 0
        ? chalk.red(this.formatDuration(stats.outageStats.longestOutage))
        : 'N/A'],
      ['Downtime Percentage', stats.outageStats.outagePercentage > 0
        ? chalk.red(`${stats.outageStats.outagePercentage}%`)
        : chalk.green('0%')]
    );

    console.log(table.toString());
  }

  static showHistory(metrics: NetworkMetric[]): void {
    console.log(chalk.bold.cyan('\n📜 Recent History\n'));

    const table = new Table({
      head: ['Time', 'Latency', 'Packet Loss', 'DNS'],
      colWidths: [25, 15, 15, 15]
    });

    metrics.slice(-20).reverse().forEach(metric => {
      table.push([
        metric.timestamp.toLocaleTimeString(),
        this.formatLatency(metric.ping.avg),
        this.formatPacketLoss(metric.ping.packetLoss),
        metric.dns.success ? chalk.green('✓') : chalk.red('✗')
      ]);
    });

    console.log(table.toString());
  }

  static showOutages(outages: OutageEvent[]): void {
    console.log(chalk.bold.cyan('\n🚨 Outage History\n'));

    if (outages.length === 0) {
      console.log(chalk.green('No outages recorded.'));
      return;
    }

    const table = new Table({
      head: ['Start Time', 'End Time', 'Duration', 'Type', 'Packet Loss'],
      colWidths: [25, 25, 15, 15, 15]
    });

    outages.slice(-20).reverse().forEach(outage => {
      const duration = outage.duration 
        ? this.formatDuration(Math.round(outage.duration / 1000))
        : chalk.yellow('Ongoing');
      
      table.push([
        outage.startTime.toLocaleString(),
        outage.endTime ? outage.endTime.toLocaleString() : chalk.yellow('Ongoing'),
        duration,
        outage.type === 'connectivity' ? chalk.red('Full') : chalk.yellow('Partial'),
        chalk.red(`${outage.metrics.packetLoss}%`)
      ]);
    });

    console.log(table.toString());
  }
}