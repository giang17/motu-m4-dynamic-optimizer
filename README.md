# MOTU M4 Dynamic Audio Optimizer

A hybrid udev/systemd solution for optimizing Linux audio performance with the MOTU M4 audio interface.

## Features

- ⚡ **Instant response** when plugging/unplugging the MOTU M4
- 🔋 **Zero resource usage** when the interface is disconnected
- 🎵 **Real-time xrun monitoring** with live detection
- 🎛️ **Dynamic JACK settings detection** with contextual recommendations
- 🔄 **Plug-and-play** without manual intervention

## Requirements

- Linux (Ubuntu 24.04 or compatible distribution)
- MOTU M4 Audio Interface
- Root privileges for installation

## Quick Installation

```bash
# Copy files to system locations
sudo cp motu-m4-dynamic-optimizer.sh /usr/local/bin/
sudo cp motu-m4-dynamic-optimizer.service /etc/systemd/system/
sudo cp 99-motu-m4-audio-optimizer.rules /etc/udev/rules.d/

# Make script executable
sudo chmod +x /usr/local/bin/motu-m4-dynamic-optimizer.sh

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb

# The service will auto-start when MOTU M4 is connected
```

## Usage

```bash
# Check status
sudo /usr/local/bin/motu-m4-dynamic-optimizer.sh status

# Detailed analysis
sudo /usr/local/bin/motu-m4-dynamic-optimizer.sh detailed

# Live xrun monitoring
sudo /usr/local/bin/motu-m4-dynamic-optimizer.sh live-xruns

# Continuous monitoring
sudo /usr/local/bin/motu-m4-dynamic-optimizer.sh monitor
```

## How It Works

1. **MOTU M4 connected** → udev detects USB device → service starts → optimizations activated
2. **MOTU M4 removed** → udev detects removal → service stops → optimizations deactivated

## Optimizations Applied

- CPU governor set to `performance` for audio-relevant cores
- IRQ affinity optimized for USB audio
- USB autosuspend disabled
- Kernel parameters tuned for low latency

## Documentation

See [README-HYBRID.md](README-HYBRID.md) for comprehensive documentation including:
- Detailed configuration options
- Troubleshooting guides
- Performance monitoring
- GRUB parameters for best performance

## License

MIT License