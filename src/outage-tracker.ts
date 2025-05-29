import { NetworkMetric, OutageEvent } from './types';

export class OutageTracker {
  private currentOutage: OutageEvent | null = null;
  private outages: OutageEvent[] = [];
  private outageThreshold = {
    packetLoss: 50,
    consecutiveFailures: 2
  };
  private consecutiveFailures = 0;

  processMetric(metric: NetworkMetric): OutageEvent | null {
    const isOutage = this.isOutageCondition(metric);
    metric.isOutage = isOutage;

    if (isOutage) {
      this.consecutiveFailures++;
      
      if (!this.currentOutage && this.consecutiveFailures >= this.outageThreshold.consecutiveFailures) {
        this.currentOutage = this.startOutage(metric);
        return this.currentOutage;
      }
    } else {
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

  private startOutage(metric: NetworkMetric): OutageEvent {
    const outage: OutageEvent = {
      id: `outage-${Date.now()}`,
      startTime: metric.timestamp,
      type: metric.ping.packetLoss === 100 ? 'connectivity' : 'partial',
      metrics: {
        packetLoss: metric.ping.packetLoss,
        dnsFailure: !metric.dns.success
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
  }

  loadOutages(outages: OutageEvent[]): void {
    this.outages = outages.map(o => ({
      ...o,
      startTime: new Date(o.startTime),
      endTime: o.endTime ? new Date(o.endTime) : undefined
    }));

    const ongoingOutage = this.outages.find(o => !o.endTime);
    if (ongoingOutage) {
      this.currentOutage = ongoingOutage;
    }
  }
}