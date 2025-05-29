# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a full-screen terminal application for monitoring network connection quality, built with TypeScript. It provides real-time statistics, outage tracking, visual latency graphs, and persistent historical data storage.

## Commands

- `npm run build` - Compile TypeScript to JavaScript
- `npm run dev` - Run the CLI in development mode using tsx
- `npm start` - Run the compiled CLI
- `npm run watch` - Watch mode for TypeScript compilation

### CLI Usage
- `netmon monitor` - Start monitoring network connection (full-screen mode)
- `netmon stats` - Show network statistics
- `netmon history` - Show recent monitoring history
- `netmon outages` - Show outage history
- `netmon clear` - Clear all monitoring data

## Architecture

### Core Components

1. **NetworkMonitor** (`src/monitor.ts`) - Core monitoring engine that collects ping and DNS metrics
2. **MetricsStorage** (`src/storage.ts`) - Persists metrics and outages to JSON files with automatic cleanup
3. **OutageTracker** (`src/outage-tracker.ts`) - Detects and tracks network outages with duration calculation
4. **StatsAnalyzer** (`src/stats.ts`) - Analyzes metrics to generate statistics for different time periods
5. **Display** (`src/display.ts`) - Full-screen terminal UI with live updates and no flicker
6. **Graph** (`src/graph.ts`) - ASCII graph generator for latency visualization
7. **TerminalUtils** (`src/terminal-utils.ts`) - Terminal control utilities for cursor and screen management
8. **CLI** (`src/cli.ts`) - Commander-based CLI interface with alternate screen buffer support

### Data Flow
1. NetworkMonitor collects metrics at specified intervals
2. OutageTracker processes each metric to detect outages
3. Metrics saved to `~/.netmon/metrics.json`, outages to `~/.netmon/metrics-outages.json`
4. Display renders full-screen dashboard with all information
5. Historical data retained up to 100,000 samples (~28 hours at 1s intervals)

### Key Features
- Full-screen terminal UI with alternate screen buffer
- Real-time monitoring with smooth, flicker-free updates
- Automatic outage detection and duration tracking
- ASCII latency graph for visual trend analysis
- Multiple time period views (5 min, 1 hour, 24 hours, all time)
- Color-coded status indicators (green < 50ms, yellow < 100ms, red ≥ 100ms)
- Terminal resize handling
- Session collection counter

### Display Layout
1. Header: Title + update time + session count
2. Status table: Current metrics
3. Statistics table: Multi-period performance data
4. Latency graph: 5-minute trend visualization
5. Footer: Help text and monitoring info