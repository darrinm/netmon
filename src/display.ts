import chalk from 'chalk';
import Table from 'cli-table3';
import { NetworkMetric, NetworkStats } from './types';

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

  static showCurrentStatus(metric: NetworkMetric): void {
    console.clear();
    console.log(chalk.bold.cyan('\n🌐 Network Monitor - Live Status\n'));
    console.log(chalk.gray(`Last Update: ${metric.timestamp.toLocaleString()}\n`));

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

    console.log(statusTable.toString());
  }

  static showStats(stats: Map<string, NetworkStats>): void {
    console.log(chalk.bold.cyan('\n📊 Network Statistics\n'));

    const statsTable = new Table({
      head: ['Period', 'Uptime', 'Avg Latency', 'Packet Loss', 'DNS Success', 'Samples'],
      colWidths: [15, 12, 15, 15, 15, 10]
    });

    stats.forEach((stat, period) => {
      statsTable.push([
        period,
        this.formatUptime(stat.pingStats.uptime),
        this.formatLatency(stat.pingStats.avgLatency),
        this.formatPacketLoss(stat.pingStats.avgPacketLoss),
        this.formatUptime(stat.dnsStats.successRate),
        stat.samples.toString()
      ]);
    });

    console.log(statsTable.toString());
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
      ['Success Rate', this.formatUptime(stats.dnsStats.successRate)]
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
}