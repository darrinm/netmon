import { NetworkMetric, NetworkStats } from './types';

export class StatsAnalyzer {
  static analyze(metrics: NetworkMetric[], period: string): NetworkStats {
    if (metrics.length === 0) {
      const now = new Date();
      return {
        period,
        startTime: now,
        endTime: now,
        pingStats: {
          avgLatency: 0,
          minLatency: 0,
          maxLatency: 0,
          avgPacketLoss: 0,
          uptime: 0
        },
        dnsStats: {
          avgResponseTime: 0,
          successRate: 0
        },
        samples: 0
      };
    }

    const startTime = metrics[0].timestamp;
    const endTime = metrics[metrics.length - 1].timestamp;

    const pingLatencies = metrics.map(m => m.ping.avg).filter(l => l > 0);
    const packetLosses = metrics.map(m => m.ping.packetLoss);
    const dnsResponseTimes = metrics
      .filter(m => m.dns.success)
      .map(m => m.dns.responseTime);
    const dnsSuccesses = metrics.filter(m => m.dns.success).length;

    const avgLatency = pingLatencies.length > 0
      ? pingLatencies.reduce((a, b) => a + b, 0) / pingLatencies.length
      : 0;

    const avgPacketLoss = packetLosses.length > 0
      ? packetLosses.reduce((a, b) => a + b, 0) / packetLosses.length
      : 100;

    const uptime = metrics.length > 0
      ? (metrics.filter(m => m.ping.packetLoss < 100).length / metrics.length) * 100
      : 0;

    const avgDnsResponseTime = dnsResponseTimes.length > 0
      ? dnsResponseTimes.reduce((a, b) => a + b, 0) / dnsResponseTimes.length
      : 0;

    const dnsSuccessRate = metrics.length > 0
      ? (dnsSuccesses / metrics.length) * 100
      : 0;

    return {
      period,
      startTime,
      endTime,
      pingStats: {
        avgLatency: Math.round(avgLatency * 100) / 100,
        minLatency: pingLatencies.length > 0 ? Math.min(...pingLatencies) : 0,
        maxLatency: pingLatencies.length > 0 ? Math.max(...pingLatencies) : 0,
        avgPacketLoss: Math.round(avgPacketLoss * 100) / 100,
        uptime: Math.round(uptime * 100) / 100
      },
      dnsStats: {
        avgResponseTime: Math.round(avgDnsResponseTime * 100) / 100,
        successRate: Math.round(dnsSuccessRate * 100) / 100
      },
      samples: metrics.length
    };
  }

  static getMetricsForPeriod(
    metrics: NetworkMetric[],
    hours: number
  ): NetworkMetric[] {
    const since = new Date();
    since.setHours(since.getHours() - hours);
    return metrics.filter(m => m.timestamp >= since);
  }
}