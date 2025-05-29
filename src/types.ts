export interface NetworkMetric {
  timestamp: Date;
  ping: {
    host: string;
    min: number;
    avg: number;
    max: number;
    packetLoss: number;
  };
  bandwidth?: {
    download: number;
    upload: number;
  };
  dns: {
    responseTime: number;
    success: boolean;
  };
  isOutage?: boolean;
}

export interface OutageEvent {
  id: string;
  startTime: Date;
  endTime?: Date;
  duration?: number;
  type: 'connectivity' | 'partial';
  metrics: {
    packetLoss: number;
    dnsFailure: boolean;
  };
}

export interface NetworkStats {
  period: string;
  startTime: Date;
  endTime: Date;
  pingStats: {
    avgLatency: number;
    minLatency: number;
    maxLatency: number;
    avgPacketLoss: number;
    uptime: number;
  };
  dnsStats: {
    avgResponseTime: number;
    successRate: number;
  };
  outageStats: {
    totalOutages: number;
    totalDuration: number;
    avgDuration: number;
    longestOutage: number;
    outagePercentage: number;
  };
  samples: number;
}

export interface MonitorConfig {
  pingHost: string;
  dnsServer: string;
  interval: number;
  dataFile: string;
}