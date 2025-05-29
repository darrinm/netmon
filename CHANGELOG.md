# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-05-29

### Added
- Initial release with basic network monitoring functionality
- Real-time ping and DNS monitoring
- Historical data storage in JSON format
- Multiple time period statistics (hour, 24 hours, all time)
- Color-coded status indicators
- Shell script wrappers for easy usage
- Interactive menu interface

### Enhanced
- Outage detection and duration tracking
  - Automatic detection of connectivity loss
  - Tracks start/end times and durations
  - Separate storage for outage history
  - Downtime percentage calculations

- Full-screen terminal application
  - Professional dashboard layout
  - Alternate screen buffer support
  - Terminal resize handling
  - Centered header with divider lines
  - Footer with help information

- Visual improvements
  - ASCII latency graph (5-minute window)
  - Smooth, flicker-free updates
  - Better use of terminal real estate
  - Dynamic layout based on terminal size

- Performance improvements
  - Fixed time period filtering
  - Session collection counter
  - Increased storage capacity to 100k samples
  - Smart rendering without buffering

### Fixed
- Sample count display for different time periods
- Display cutoff issues in smaller terminals
- Screen flashing during updates
- Focus-related flicker when switching windows

### Technical Stack
- TypeScript for type safety
- Commander.js for CLI parsing
- Chalk for terminal colors
- cli-table3 for formatted tables
- Custom graph rendering for latency visualization