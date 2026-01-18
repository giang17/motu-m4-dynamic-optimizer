# MOTU M4 Dynamic Optimizer v1.0.0

🎉 **First stable release with modular architecture**

## Highlights

- Complete refactor from monolithic 1800+ line script to clean modular architecture
- Professional installer with install/update/uninstall/status commands
- Hybrid CPU strategy optimized for Intel 12th/13th/14th gen (P-Core + E-Core)
- Real-time audio optimization for low-latency production

## Features

### 🎛️ Audio Optimization
- Automatic MOTU M4 detection via USB and ALSA
- JACK/PipeWire real-time priority management (SCHED_FIFO)
- Dynamic buffer size recommendations based on xrun analysis
- USB IRQ affinity optimization for minimal latency

### 🖥️ CPU Management (Hybrid Strategy)
- **P-Cores 0-5**: DAW and plugin processing (performance governor)
- **P-Cores 6-7**: JACK/PipeWire audio engine (performance governor)
- **E-Cores 8-13**: Background tasks (powersave governor)
- **E-Cores 14-19**: IRQ handling, isolated via kernel (performance governor)

### 📦 Modular Architecture
New clean structure with 11 specialized modules:
- `config.sh` - Configuration and audio process definitions
- `logging.sh` - Logging with permission-aware fallback
- `checks.sh` - Hardware and system state detection
- `jack.sh` - JACK settings and buffer management
- `xrun.sh` - Xrun monitoring and analysis
- `process.sh` - Process affinity and RT priority
- `usb.sh` - USB power and URB optimization
- `kernel.sh` - Kernel parameter tuning
- `optimization.sh` - Core optimization logic
- `status.sh` - Status display and reporting
- `monitor.sh` - Continuous monitoring loop

### 🔧 Installer
```bash
sudo ./install.sh install   # Full installation
sudo ./install.sh update    # Update existing installation
sudo ./install.sh uninstall # Clean removal
./install.sh status         # Check installation status
```

### 🚀 Usage
```bash
motu-m4-dynamic-optimizer status      # Show current status
motu-m4-dynamic-optimizer once        # One-time optimization
motu-m4-dynamic-optimizer monitor     # Continuous monitoring (daemon)
motu-m4-dynamic-optimizer live-xruns  # Real-time xrun display
```

## Installation

### Prerequisites
- Linux with systemd
- MOTU M4 audio interface
- Intel hybrid CPU (12th gen or newer recommended)
- JACK or PipeWire audio system

### Quick Start
```bash
git clone https://github.com/gnugat/motu-m4-dynamic-optimizer.git
cd motu-m4-dynamic-optimizer
sudo ./install.sh install
```

### Kernel Parameters (recommended)
Add to GRUB for optimal performance:
```
isolcpus=14-19 nohz_full=14-19 rcu_nocbs=14-19
```

## System Requirements
- Linux kernel 5.x or newer
- systemd 245 or newer
- bash 4.0 or newer

## Files Installed
- `/usr/local/bin/motu-m4-dynamic-optimizer` - Main command
- `/usr/local/lib/motu-m4-dynamic-optimizer/` - Module library
- `/etc/systemd/system/motu-m4-dynamic-optimizer.service` - Systemd service
- `/etc/udev/rules.d/99-motu-m4-audio-optimizer.rules` - Udev rules
- `/var/log/motu-m4-optimizer.log` - Log file

---

**Full Changelog**: Initial release