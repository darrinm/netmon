# netmon - Network Quality Monitor

A full-screen terminal application that monitors your network connection quality with real-time statistics, outage tracking, and visual latency graphs.

![Network Monitor Screenshot](https://github.com/user-attachments/assets/b503cab5-af51-4657-b8a8-35ad9cf7fbdc)

## Features

- 🖥️ **Full-screen terminal UI** - Professional dashboard layout with live updates
- 📊 **Real-time statistics** - Monitor latency, packet loss, and DNS performance
- 📈 **ASCII latency graph** - Visual representation of network performance trends
- 🚨 **Outage detection & tracking** - Automatic detection with duration monitoring
- ⏱️ **Multiple time periods** - View stats for last 5 minutes, hour, 24 hours, or all time
- 🎨 **Color-coded indicators** - Instant visual feedback on connection quality
- 💾 **Persistent storage** - Historical data survives restarts
- 🔄 **Smooth updates** - Flicker-free display with intelligent rendering
- 📏 **Responsive design** - Adapts to terminal size with resize support

## Installation

```bash
npm install
npm run build
npm link  # Optional: to use 'netmon' command globally
```

## Quick Start

```bash
# Clone and setup
git clone https://github.com/darrinm/netmon.git
cd netmon
npm install

# Start monitoring
./netmon              # or npm run dev monitor
```

## Shell Scripts

Two convenient shell scripts are provided:

### 1. Command-line Interface (`./netmon`)
```bash
./netmon                    # Start monitoring (default)
./netmon monitor -i 5       # Monitor with 5-second interval
./netmon monitor -h 1.1.1.1 # Monitor specific host
./netmon stats              # Show statistics
./netmon history            # Show recent history
./netmon outages            # Show outage history
./netmon help               # Show help
```

### 2. Interactive Menu (`./netmon-menu`)
```bash
./netmon-menu         # Launch interactive menu
```

Features:
- Navigate through all commands with a menu
- Configure monitoring settings
- Quick network status check
- View different time periods easily

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

## Display Features

### Main Dashboard
- **Header**: Shows title, last update time, and session collection count
- **Status Table**: Current connection metrics with color-coded status
- **Statistics Table**: Performance metrics for multiple time periods
- **Latency Graph**: ASCII visualization of recent latency trends (5-minute window)
- **Footer**: Help text and monitoring interval

### Color Coding
- 🟢 **Green**: Excellent (latency < 50ms, packet loss = 0%)
- 🟡 **Yellow**: Fair (latency < 100ms, packet loss < 5%)
- 🔴 **Red**: Poor (latency ≥ 100ms, packet loss ≥ 5%)

## Metrics Tracked

- **Ping Latency**: Min, average, and max response times
- **Packet Loss**: Percentage of lost packets
- **DNS Response Time**: Time to resolve DNS queries
- **Network Uptime**: Percentage of successful connections
- **Outages**: Automatic detection with duration tracking
  - Full connectivity loss (100% packet loss)
  - Partial outages (high packet loss + DNS failures)
  - Outage start/end times and total duration
  - Downtime percentage per time period

## Data Storage

- **Metrics**: `~/.netmon/metrics.json` (up to 100,000 samples)
- **Outages**: `~/.netmon/metrics-outages.json`
- **Custom location**: Use `--data-file` option to specify alternative path

## Requirements

- Node.js 14.0 or higher
- Terminal with ANSI color support
- Unix-like OS (macOS, Linux) or Windows with proper terminal

## Technical Details

### Architecture
- **TypeScript** - Type-safe development with modern JavaScript features
- **Modular design** - Separate modules for monitoring, storage, statistics, and display
- **Event-driven** - Async monitoring with configurable intervals
- **Full-screen TUI** - Uses alternate screen buffer for clean terminal experience

### Key Technologies
- **ping** - ICMP echo requests for latency measurement
- **dns** - Native Node.js DNS module for DNS checks
- **commander** - CLI argument parsing
- **chalk** - Terminal color output
- **cli-table3** - Formatted table display

### Performance
- Efficient data storage with automatic cleanup
- Smart rendering to prevent flicker
- Minimal CPU usage during monitoring
- Handles terminal resize events gracefully

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Author

Created by Darrin Massena with assistance from Claude
