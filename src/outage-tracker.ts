import { NetworkMetric, OutageEvent } from './types';

export class OutageTracker {
  // How stale an ongoing outage can be on load before we close it instead of resuming.
  // We can't claim downtime that occurred while the monitor wasn't running.
  private static readonly STALE_OUTAGE_MS = 5 * 60 * 1000;

  private currentOutage: OutageEvent | null = null;
  private outages: OutageEvent[] = [];
  private outageThreshold = {
    packetLoss: 50,
    consecutiveFailures: 2
  };
  private consecutiveFailures = 0;
  private firstFailureMetric: NetworkMetric | null = null;

  processMetric(metric: NetworkMetric): OutageEvent | null {
    const isOutage = this.isOutageCondition(metric);
    metric.isOutage = isOutage;

    if (isOutage) {
      this.consecutiveFailures++;
      if (!this.firstFailureMetric) {
        this.firstFailureMetric = metric;
      }

      if (this.currentOutage) {
        this.currentOutage.lastUpdateTime = metric.timestamp;
      } else if (this.consecutiveFailures >= this.outageThreshold.consecutiveFailures) {
        this.currentOutage = this.startOutage(this.firstFailureMetric, metric);
        return this.currentOutage;
      }
    } else {
      this.firstFailureMetric = null;
      if (this.currentOutage) {
        const endedOutage = this.endOutage(metric);
        this.consecutiveFailures = 0;
        return endedOutage;
      }
      this.consecutiveFailures = 0;
    }

    return null;
  }

  private isOutageCondition(metric: NetworkMetric): boolean {
    const hasHighPacketLoss = metric.ping.packetLoss >= this.outageThreshold.packetLoss;
    const hasDnsFailure = !metric.dns.success;
    const hasNoConnectivity = metric.ping.packetLoss === 100;

    return hasNoConnectivity || (hasHighPacketLoss && hasDnsFailure);
  }

  private startOutage(firstFailure: NetworkMetric, latestFailure: NetworkMetric): OutageEvent {
    const outage: OutageEvent = {
      id: `outage-${firstFailure.timestamp.getTime()}`,
      startTime: firstFailure.timestamp,
      lastUpdateTime: latestFailure.timestamp,
      type: firstFailure.ping.packetLoss === 100 ? 'connectivity' : 'partial',
      metrics: {
        packetLoss: firstFailure.ping.packetLoss,
        dnsFailure: !firstFailure.dns.success
      }
    };

    this.outages.push(outage);
    return outage;
  }

  private endOutage(metric: NetworkMetric): OutageEvent {
    if (!this.currentOutage) {
      throw new Error('No current outage to end');
    }

    this.currentOutage.endTime = metric.timestamp;
    this.currentOutage.duration = 
      metric.timestamp.getTime() - this.currentOutage.startTime.getTime();

    const endedOutage = this.currentOutage;
    this.currentOutage = null;
    return endedOutage;
  }

  getOutages(since?: Date): OutageEvent[] {
    if (!since) return [...this.outages];
    
    return this.outages.filter(o => o.startTime >= since);
  }

  getCurrentOutage(): OutageEvent | null {
    return this.currentOutage;
  }

  clearOutages(): void {
    this.outages = [];
    this.currentOutage = null;
    this.consecutiveFailures = 0;
    this.firstFailureMetric = null;
  }

  loadOutages(outages: OutageEvent[]): void {
    this.outages = outages.map(o => ({
      ...o,
      startTime: new Date(o.startTime),
      endTime: o.endTime ? new Date(o.endTime) : undefined,
      lastUpdateTime: o.lastUpdateTime ? new Date(o.lastUpdateTime) : undefined
    }));

    const ongoingOutage = this.outages.find(o => !o.endTime);
    if (!ongoingOutage) return;

    const lastActivity = ongoingOutage.lastUpdateTime ?? ongoingOutage.startTime;
    const staleness = Date.now() - lastActivity.getTime();

    if (staleness > OutageTracker.STALE_OUTAGE_MS) {
      // Monitor wasn't running for too long to credibly extend this outage; close it
      // at the last observed activity so stats don't double-count the offline gap.
      ongoingOutage.endTime = lastActivity;
      ongoingOutage.duration = lastActivity.getTime() - ongoingOutage.startTime.getTime();
    } else {
      this.currentOutage = ongoingOutage;
    }
  }
}