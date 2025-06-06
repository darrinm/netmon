import * as ping from 'ping';
import * as dns from 'dns/promises';
import { NetworkMetric, MonitorConfig } from './types';

export class NetworkMonitor {
  private config: MonitorConfig;
  private isRunning: boolean = false;
  private intervalId?: NodeJS.Timeout;

  constructor(config: MonitorConfig) {
    this.config = config;
  }

  async measurePing(): Promise<NetworkMetric['ping']> {
    try {
      const res = await ping.promise.probe(this.config.pingHost, {
        timeout: 10,
        extra: ['-c', '5']
      });

      // Helper to safely parse float values
      const safeParseFloat = (value: any, defaultValue: number = 0): number => {
        if (value === undefined || value === null || value === '') return defaultValue;
        const parsed = parseFloat(value);
        return isNaN(parsed) ? defaultValue : parsed;
      };

      return {
        host: this.config.pingHost,
        min: safeParseFloat(res.min, 0),
        avg: safeParseFloat(res.avg, 0),
        max: safeParseFloat(res.max, 0),
        packetLoss: res.packetLoss !== undefined ? safeParseFloat(res.packetLoss, 100) : 100
      };
    } catch (error) {
      return {
        host: this.config.pingHost,
        min: 0,
        avg: 0,
        max: 0,
        packetLoss: 100
      };
    }
  }

  async measureDNS(): Promise<NetworkMetric['dns']> {
    const start = Date.now();
    try {
      await dns.resolve4('google.com');
      return {
        responseTime: Date.now() - start,
        success: true
      };
    } catch (error) {
      return {
        responseTime: Date.now() - start,
        success: false
      };
    }
  }

  async collectMetric(): Promise<NetworkMetric> {
    const [pingResult, dnsResult] = await Promise.all([
      this.measurePing(),
      this.measureDNS()
    ]);

    return {
      timestamp: new Date(),
      ping: pingResult,
      dns: dnsResult
    };
  }

  start(callback: (metric: NetworkMetric) => void): void {
    if (this.isRunning) return;
    
    this.isRunning = true;
    
    const collect = async () => {
      try {
        const metric = await this.collectMetric();
        callback(metric);
      } catch (error) {
        console.error('Error collecting metrics:', error);
      }
    };

    collect();
    this.intervalId = setInterval(collect, this.config.interval);
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
    }
    this.isRunning = false;
  }
}