import notifier from 'node-notifier';
import { OutageEvent } from './types';

export interface NotifierConfig {
  enabled: boolean;
  onOutageStart: boolean;
  onOutageEnd: boolean;
  minOutageDuration?: number; // minimum seconds before notifying end
}

const DEFAULT_CONFIG: NotifierConfig = {
  enabled: true,
  onOutageStart: true,
  onOutageEnd: true,
  minOutageDuration: 0
};

export class Notifier {
  private config: NotifierConfig;

  constructor(config: Partial<NotifierConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  outageStarted(outage: OutageEvent, host: string): void {
    if (!this.config.enabled || !this.config.onOutageStart) return;

    const typeLabel = outage.type === 'connectivity' ? 'Complete' : 'Partial';

    notifier.notify({
      title: 'Network Outage Detected',
      message: `${typeLabel} outage - ${host} unreachable`,
      sound: true
    });
  }

  outageEnded(outage: OutageEvent, host: string): void {
    if (!this.config.enabled || !this.config.onOutageEnd) return;

    const durationSec = outage.duration ? Math.round(outage.duration / 1000) : 0;

    if (this.config.minOutageDuration && durationSec < this.config.minOutageDuration) {
      return;
    }

    const duration = this.formatDuration(durationSec);

    notifier.notify({
      title: 'Network Restored',
      message: `Connection to ${host} restored after ${duration}`,
      sound: true
    });
  }

  private formatDuration(seconds: number): string {
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return `${hours}h ${minutes}m`;
  }
}
