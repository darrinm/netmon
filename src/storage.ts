import * as fs from 'fs/promises';
import * as path from 'path';
import { NetworkMetric } from './types';

export class MetricsStorage {
  private dataFile: string;
  private metrics: NetworkMetric[] = [];
  private maxMetrics: number = 10000;

  constructor(dataFile: string) {
    this.dataFile = dataFile;
  }

  async init(): Promise<void> {
    try {
      await fs.mkdir(path.dirname(this.dataFile), { recursive: true });
      const data = await fs.readFile(this.dataFile, 'utf-8');
      const parsed = JSON.parse(data);
      this.metrics = parsed.map((m: any) => ({
        ...m,
        timestamp: new Date(m.timestamp)
      }));
    } catch (error) {
      this.metrics = [];
    }
  }

  async save(metric: NetworkMetric): Promise<void> {
    this.metrics.push(metric);
    
    if (this.metrics.length > this.maxMetrics) {
      this.metrics = this.metrics.slice(-this.maxMetrics);
    }

    await this.persist();
  }

  private async persist(): Promise<void> {
    await fs.writeFile(this.dataFile, JSON.stringify(this.metrics, null, 2));
  }

  getMetrics(since?: Date): NetworkMetric[] {
    if (!since) return [...this.metrics];
    
    return this.metrics.filter(m => m.timestamp >= since);
  }

  getLatest(count: number = 10): NetworkMetric[] {
    return this.metrics.slice(-count);
  }

  clear(): void {
    this.metrics = [];
  }
}