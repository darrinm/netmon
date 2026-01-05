import * as fs from 'fs/promises';
import * as path from 'path';
import { NetworkMetric, OutageEvent } from './types';

export class MetricsStorage {
  private dataFile: string;
  private outageFile: string;
  private lockFile: string;
  private metrics: NetworkMetric[] = [];
  private outages: OutageEvent[] = [];
  private maxMetrics: number = 100000; // ~28 hours at 1s intervals, ~35 days at 30s intervals
  private writeQueue: Promise<void> = Promise.resolve();
  private outageWriteQueue: Promise<void> = Promise.resolve();

  constructor(dataFile: string) {
    this.dataFile = dataFile;
    this.outageFile = dataFile.replace('.json', '-outages.json');
    this.lockFile = dataFile.replace('.json', '.lock');
  }

  private isValidMetric(m: any): boolean {
    return m &&
      typeof m === 'object' &&
      m.timestamp !== undefined &&
      m.ping && typeof m.ping === 'object' &&
      m.dns && typeof m.dns === 'object';
  }

  private isValidOutage(o: any): boolean {
    return o &&
      typeof o === 'object' &&
      typeof o.id === 'string' &&
      o.startTime !== undefined &&
      o.metrics && typeof o.metrics === 'object';
  }

  async init(): Promise<void> {
    try {
      await fs.mkdir(path.dirname(this.dataFile), { recursive: true });
      const data = await fs.readFile(this.dataFile, 'utf-8');
      const parsed = JSON.parse(data);

      if (!Array.isArray(parsed)) {
        console.warn('Metrics file is not an array, starting fresh');
        this.metrics = [];
      } else {
        this.metrics = parsed
          .filter((m: any) => this.isValidMetric(m))
          .map((m: any) => ({
            ...m,
            timestamp: new Date(m.timestamp)
          }));

        if (this.metrics.length < parsed.length) {
          console.warn(`Filtered out ${parsed.length - this.metrics.length} invalid metrics`);
        }
      }
    } catch (error) {
      this.metrics = [];
    }

    try {
      const outageData = await fs.readFile(this.outageFile, 'utf-8');
      const parsedOutages = JSON.parse(outageData);

      if (!Array.isArray(parsedOutages)) {
        console.warn('Outages file is not an array, starting fresh');
        this.outages = [];
      } else {
        this.outages = parsedOutages
          .filter((o: any) => this.isValidOutage(o))
          .map((o: any) => ({
            ...o,
            startTime: new Date(o.startTime),
            endTime: o.endTime ? new Date(o.endTime) : undefined
          }));

        if (this.outages.length < parsedOutages.length) {
          console.warn(`Filtered out ${parsedOutages.length - this.outages.length} invalid outages`);
        }
      }
    } catch (error) {
      this.outages = [];
    }
  }

  async acquireLock(): Promise<boolean> {
    try {
      await fs.writeFile(this.lockFile, process.pid.toString(), { flag: 'wx' });
      return true;
    } catch (error: any) {
      if (error.code === 'EEXIST') {
        try {
          const lockPid = await fs.readFile(this.lockFile, 'utf-8');
          const pid = parseInt(lockPid, 10);
          try {
            process.kill(pid, 0);
            return false;
          } catch {
            await fs.unlink(this.lockFile);
            return this.acquireLock();
          }
        } catch {
          return false;
        }
      }
      return false;
    }
  }

  async releaseLock(): Promise<void> {
    try {
      await fs.unlink(this.lockFile);
    } catch {
      // Ignore errors when releasing lock
    }
  }

  async save(metric: NetworkMetric): Promise<void> {
    this.metrics.push(metric);

    if (this.metrics.length > this.maxMetrics) {
      this.metrics = this.metrics.slice(-this.maxMetrics);
    }

    this.writeQueue = this.writeQueue.then(() => this.persist());
    await this.writeQueue;
  }

  private async persist(): Promise<void> {
    try {
      await fs.writeFile(this.dataFile, JSON.stringify(this.metrics, null, 2));
    } catch (error: any) {
      console.error(`Failed to save metrics: ${error.message}`);
    }
  }

  async saveOutage(outage: OutageEvent): Promise<void> {
    const existingIndex = this.outages.findIndex(o => o.id === outage.id);
    if (existingIndex >= 0) {
      this.outages[existingIndex] = outage;
    } else {
      this.outages.push(outage);
    }
    this.outageWriteQueue = this.outageWriteQueue.then(() => this.persistOutages());
    await this.outageWriteQueue;
  }

  private async persistOutages(): Promise<void> {
    try {
      await fs.writeFile(this.outageFile, JSON.stringify(this.outages, null, 2));
    } catch (error: any) {
      console.error(`Failed to save outages: ${error.message}`);
    }
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