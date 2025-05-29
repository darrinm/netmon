import * as fs from 'fs/promises';
import * as path from 'path';
import { NetworkMetric, OutageEvent } from './types';

export class MetricsStorage {
  private dataFile: string;
  private outageFile: string;
  private metrics: NetworkMetric[] = [];
  private outages: OutageEvent[] = [];
  private maxMetrics: number = 100000; // ~28 hours at 1s intervals, ~35 days at 30s intervals

  constructor(dataFile: string) {
    this.dataFile = dataFile;
    this.outageFile = dataFile.replace('.json', '-outages.json');
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

    try {
      const outageData = await fs.readFile(this.outageFile, 'utf-8');
      const parsedOutages = JSON.parse(outageData);
      this.outages = parsedOutages.map((o: any) => ({
        ...o,
        startTime: new Date(o.startTime),
        endTime: o.endTime ? new Date(o.endTime) : undefined
      }));
    } catch (error) {
      this.outages = [];
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

  async saveOutage(outage: OutageEvent): Promise<void> {
    const existingIndex = this.outages.findIndex(o => o.id === outage.id);
    if (existingIndex >= 0) {
      this.outages[existingIndex] = outage;
    } else {
      this.outages.push(outage);
    }
    await this.persistOutages();
  }

  private async persistOutages(): Promise<void> {
    await fs.writeFile(this.outageFile, JSON.stringify(this.outages, null, 2));
  }

  getMetrics(since?: Date): NetworkMetric[] {
    if (!since) return [...this.metrics];
    
    return this.metrics.filter(m => m.timestamp >= since);
  }

  getLatest(count: number = 10): NetworkMetric[] {
    return this.metrics.slice(-count);
  }

  getOutages(since?: Date): OutageEvent[] {
    if (!since) return [...this.outages];
    
    return this.outages.filter(o => o.startTime >= since);
  }

  async clear(): Promise<void> {
    this.metrics = [];
    this.outages = [];
    await this.persist();
    await this.persistOutages();
  }
}