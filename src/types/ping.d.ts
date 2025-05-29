declare module 'ping' {
  interface PingConfig {
    timeout?: number;
    extra?: string[];
  }

  interface PingResponse {
    host: string;
    alive: boolean;
    output: string;
    time: string;
    min: string;
    max: string;
    avg: string;
    stddev: string;
    packetLoss: string;
  }

  export namespace promise {
    function probe(host: string, config?: PingConfig): Promise<PingResponse>;
  }
}