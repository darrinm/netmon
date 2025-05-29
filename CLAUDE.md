# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a TypeScript-based command-line network monitoring utility that tracks network connection quality over time. It monitors ping latency, packet loss, and DNS response times, storing historical data for analysis.

## Commands

- `npm run build` - Compile TypeScript to JavaScript
- `npm run dev` - Run the CLI in development mode using tsx
- `npm start` - Run the compiled CLI
- `npm run watch` - Watch mode for TypeScript compilation

### CLI Usage
- `netmon monitor` - Start monitoring network connection
- `netmon stats` - Show network statistics
- `netmon history` - Show recent monitoring history
- `netmon clear` - Clear all monitoring data

## Architecture

### Core Components

1. **NetworkMonitor** (`src/monitor.ts`) - Core monitoring engine that collects ping and DNS metrics
2. **MetricsStorage** (`src/storage.ts`) - Persists metrics to JSON file with automatic cleanup
3. **StatsAnalyzer** (`src/stats.ts`) - Analyzes metrics to generate statistics for different time periods
4. **Display** (`src/display.ts`) - Formats and displays metrics in terminal with color-coded status indicators
5. **CLI** (`src/cli.ts`) - Commander-based CLI interface with multiple commands

### Data Flow
1. NetworkMonitor collects metrics at specified intervals
2. Metrics are saved to `~/.netmon/metrics.json` by default
3. Display shows real-time status and aggregated statistics
4. Historical data is retained up to 10,000 samples

### Key Features
- Real-time network monitoring with color-coded status
- Historical data analysis for multiple time periods
- Persistent storage of metrics
- Configurable monitoring intervals and hosts