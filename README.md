# netmon - Network Quality Monitor

A command-line utility that monitors your network connection quality and provides insights into performance over time.

![screenshot 2025-05-28 at 18 40 59@2x](https://github.com/user-attachments/assets/b503cab5-af51-4657-b8a8-35ad9cf7fbdc)

## Features

- 🔍 Real-time network monitoring
- 📊 Historical statistics for different time periods
- 🚨 Automatic outage detection and duration tracking
- 📈 Detailed downtime analytics
- 🎨 Color-coded status indicators
- 💾 Persistent data storage
- ⚡ Lightweight and efficient

## Installation

```bash
npm install
npm run build
npm link  # Optional: to use 'netmon' command globally
```

## Quick Start

Two convenient shell scripts are provided:

### 1. Command-line Interface (`./netmon`)
```bash
./netmon              # Start monitoring
./netmon stats        # Show statistics
./netmon history      # Show history
./netmon outages      # Show outage history
./netmon help         # Show help
```

### 2. Interactive Menu (`./netmon-menu`)
```bash
./netmon-menu         # Launch interactive menu
```

The interactive menu provides:
- Easy navigation through all features
- Quick network status checks
- Configuration management
- Visual feedback

## Usage

### Start Monitoring
```bash
npm run dev monitor
# or after building:
npm start monitor

# With options:
npm start monitor -- --host google.com --interval 60
```

### View Statistics
```bash
npm start stats
npm start stats -- --period 1  # Last hour
npm start stats -- --period 0  # All time
```

### View History
```bash
npm start history
npm start history -- --number 50  # Show last 50 entries
```

### View Outages
```bash
npm start outages
npm start outages -- --period 168  # Show outages from last week
npm start outages -- --period 0    # Show all outages
```

### Clear Data
```bash
npm start clear
```

## Metrics Tracked

- **Ping Latency**: Min, average, and max response times
- **Packet Loss**: Percentage of lost packets
- **DNS Response Time**: Time to resolve DNS queries
- **Network Uptime**: Percentage of successful connections
- **Outages**: Automatic detection with duration tracking
  - Full connectivity loss (100% packet loss)
  - Partial outages (high packet loss + DNS failures)
  - Outage duration and frequency statistics

## Data Storage

Metrics are stored in `~/.netmon/metrics.json` by default. You can specify a custom location using the `--data-file` option.
