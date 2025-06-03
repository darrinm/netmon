import chalk from 'chalk';
import { NetworkMetric } from './types';

export class Graph {
  static drawLatencyGraph(metrics: NetworkMetric[], width: number = 60, height: number = 10): string[] {
    if (metrics.length < 2) return [];

    const output: string[] = [];
    // Filter out outage data (0 values) for calculating scale, but keep them for display
    const validLatencies = metrics
      .map(m => m.ping.avg)
      .filter(l => l > 0);
    
    // If all data points are outages, show a message
    if (validLatencies.length === 0) {
      output.push(chalk.cyan('Latency History (ms)'));
      output.push(chalk.red('No data available - Network outage'));
      return output;
    }
    
    const latencies = metrics.map(m => m.ping.avg);
    const maxLatency = Math.max(...validLatencies, 10); // Minimum scale of 10ms
    const minLatency = 0; // Always start from 0
    
    // Create graph title
    output.push(chalk.cyan('Latency History (ms)'));
    
    // Draw Y-axis labels and graph
    for (let row = 0; row < height; row++) {
      const yValue = maxLatency - (row * (maxLatency - minLatency) / (height - 1));
      const label = isNaN(yValue) ? '   0' : yValue.toFixed(0).padStart(4);
      let line = chalk.gray(`${label} │`);
      
      // Sample the data to fit the width
      const step = Math.max(1, Math.floor(metrics.length / width));
      for (let col = 0; col < width; col++) {
        const index = Math.min(col * step, metrics.length - 1);
        const latency = latencies[index];
        
        // Handle outage (0 latency) specially
        if (latency === 0) {
          if (row === height - 1) {
            line += chalk.red('✗'); // Show outage marker at bottom
          } else {
            line += ' ';
          }
          continue;
        }
        
        const normalizedLatency = (latency - minLatency) / (maxLatency - minLatency);
        const graphRow = height - 1 - Math.round(normalizedLatency * (height - 1));
        
        if (row === graphRow) {
          if (latency < 50) {
            line += chalk.green('●');
          } else if (latency < 100) {
            line += chalk.yellow('●');
          } else {
            line += chalk.red('●');
          }
        } else if (row > graphRow) {
          line += chalk.gray('│');
        } else {
          line += ' ';
        }
      }
      
      output.push(line);
    }
    
    // Draw X-axis
    output.push(chalk.gray('     └' + '─'.repeat(width)));
    
    // Time labels
    const oldestTime = metrics[0].timestamp;
    const newestTime = metrics[metrics.length - 1].timestamp;
    const duration = newestTime.getTime() - oldestTime.getTime();
    const durationMin = Math.round(duration / 60000);
    
    const timeLabel = `${durationMin} min ago ← Time → now`;
    const padding = Math.max(0, width - timeLabel.length + 6);
    output.push(chalk.gray(' '.repeat(6) + timeLabel));
    
    return output;
  }
}