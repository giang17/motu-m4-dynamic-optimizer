# MOTU M4 Dynamic Audio Optimizer

A hybrid udev/systemd solution for optimizing Linux audio performance with the MOTU M4 audio interface.

## Features

- ⚡ **Instant response** when plugging/unplugging the MOTU M4
- 🔋 **Zero resource usage** when the interface is disconnected
- 🎵 **Real-time xrun monitoring** with live detection
- 🎛️ **Dynamic JACK settings detection** with contextual recommendations
- 🔄 **Plug-and-play** without manual intervention
- 🏗️ **Modular architecture** for easy maintenance and customization
- 🖥️ **Optional system tray icon** for visual status display (PyQt5 or yad)

## Requirements

- Linux (Ubuntu 24.04 or compatible distribution)
- MOTU M4 Audio Interface
- Root privileges for installation
- Optional: `python3-pyqt5` for system tray icon (`sudo apt install python3-pyqt5`)
  - Alternative: `yad` package (`sudo apt install yad`)

## Quick Installation

Use the included installer script:

```bash
# Install
sudo ./install.sh install

# Check installation status
sudo ./install.sh status

# Update existing installation
sudo ./install.sh update

# Uninstall
sudo ./install.sh uninstall
```

### Manual Installation

If you prefer manual installation:

```bash
# Create library directory and copy modules
sudo mkdir -p /usr/local/lib/motu-m4-dynamic-optimizer
sudo cp lib/*.sh /usr/local/lib/motu-m4-dynamic-optimizer/

# Copy main script
sudo cp motu-m4-dynamic-optimizer.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/motu-m4-dynamic-optimizer.sh

# Install systemd service and udev rules
sudo cp motu-m4-dynamic-optimizer.service /etc/systemd/system/
sudo cp 99-motu-m4-audio-optimizer.rules /etc/udev/rules.d/

# Reload daemons
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb

# Enable service
sudo systemctl enable motu-m4-dynamic-optimizer.service
```

## Usage

```bash
# Check status
motu-m4-dynamic-optimizer status

# Detailed analysis
motu-m4-dynamic-optimizer detailed

# Live xrun monitoring
motu-m4-dynamic-optimizer live-xruns

# Continuous monitoring (daemon mode)
motu-m4-dynamic-optimizer monitor

# One-time optimization
sudo motu-m4-dynamic-optimizer once

# Deactivate optimizations
sudo motu-m4-dynamic-optimizer stop

# Start system tray icon (optional, requires yad)
motu-m4-tray
```

## Project Structure

The optimizer uses a modular architecture for better maintainability:

```
motu-m4-dynamic-optimizer/
├── motu-m4-dynamic-optimizer.sh    # Main entry point script
├── install.sh                       # Installer script
├── lib/                             # Module library
│   ├── config.sh                    # Configuration variables
│   ├── logging.sh                   # Logging functions
│   ├── checks.sh                    # System detection functions
│   ├── jack.sh                      # JACK-related functions
│   ├── xrun.sh                      # Xrun monitoring
│   ├── process.sh                   # Process affinity management
│   ├── usb.sh                       # USB optimization
│   ├── kernel.sh                    # Kernel parameter tuning
│   ├── optimization.sh              # Main optimization logic
│   ├── status.sh                    # Status display functions
│   ├── monitor.sh                   # Monitoring loops
│   └── tray.sh                      # System tray integration (optional)
├── tray/                            # System tray application
│   ├── motu-m4-tray.py              # Tray icon (PyQt5, preferred)
│   ├── motu-m4-tray.sh              # Tray icon (yad fallback)
│   ├── motu-m4-tray.desktop         # Desktop entry
│   └── icons/                       # Status icons (SVG)
├── motu-m4-dynamic-optimizer.service
├── motu-m4-dynamic-optimizer-delayed.service
├── 99-motu-m4-audio-optimizer.rules
└── README.md
```

## How It Works

1. **MOTU M4 connected** → udev detects USB device → service starts → optimizations activated
2. **MOTU M4 removed** → udev detects removal → service stops → optimizations deactivated

## CPU Strategy (Hybrid v4)

The optimizer uses a hybrid CPU strategy optimized for Intel 12th/13th Gen processors:

| CPU Type | Cores | Governor | Purpose |
|----------|-------|----------|---------|
| P-Cores | 0-5 | Performance | DAW/Plugins (max single-thread) |
| P-Cores | 6-7 | Performance | JACK/PipeWire (dedicated audio) |
| E-Cores | 8-13 | Powersave | Background tasks (less interference) |
| E-Cores | 14-19 | Performance | IRQ handling (stable latency) |

## Optimizations Applied

- **CPU Governor**: Performance mode for audio-relevant cores
- **IRQ Affinity**: USB and audio IRQs pinned to dedicated E-cores
- **Process Affinity**: Audio processes pinned to P-cores with RT priority
- **USB Settings**: Autosuspend disabled, power management optimized
- **Kernel Parameters**: RT scheduling, swappiness, scheduler latency tuned

## System Tray Icon (Optional)

The optimizer includes an optional system tray icon for visual status display.

### Requirements

```bash
# Recommended (better KDE/Qt integration)
sudo apt install python3-pyqt5

# Alternative (fallback)
sudo apt install yad
```

The installer automatically selects PyQt5 if available, otherwise falls back to yad.

### Usage

```bash
# Start the tray icon manually
motu-m4-tray

# For development/testing with local icons
TRAY_ICON_DIR=./tray/icons python3 ./tray/motu-m4-tray.py
```

### Features

- **Status Icons**:
  - 🟢 Green: MOTU M4 connected and optimized
  - 🔵 Blue: MOTU M4 connected but not optimized
  - 🟠 Orange: Warning (xruns detected)
  - ⚫ Gray: MOTU M4 not connected

- **Tooltip**: Shows current status, JACK state, and xrun count

- **Right-click Menu**:
  - Status anzeigen (View status in terminal)
  - Live Xrun-Monitor (Open live monitoring)
  - Daemon-Monitor (Open daemon monitoring)
  - Optimierung starten/stoppen (Start/stop optimization)

### Configuration

To enable automatic tray state updates, add to `/etc/motu-m4-optimizer.conf`:

```bash
TRAY_ENABLED="true"
```

See `motu-m4-optimizer.conf.example` for all available tray options.

## Troubleshooting

### Check if MOTU M4 is detected
```bash
lsusb | grep "Mark of the Unicorn"
```

### Check service status
```bash
systemctl status motu-m4-dynamic-optimizer.service
```

### View logs
```bash
tail -f /var/log/motu-m4-optimizer.log
```

### Manual optimization trigger
```bash
sudo motu-m4-dynamic-optimizer once
```

## Documentation

See [README-HYBRID.md](README-HYBRID.md) for comprehensive documentation including:
- Detailed configuration options
- Troubleshooting guides
- Performance monitoring
- GRUB parameters for best performance

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
