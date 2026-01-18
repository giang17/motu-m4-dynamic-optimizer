#!/bin/bash

# MOTU M4 Dynamic Optimizer v4 - Configuration Module
# Contains all configuration variables and constants

# ============================================================================
# FILE PATHS
# ============================================================================

LOG_FILE="/var/log/motu-m4-optimizer.log"
STATE_FILE="/var/run/motu-m4-state"

# ============================================================================
# CPU ASSIGNMENTS
# ============================================================================

# CPU assignments for process pinning
# Optimized for Intel 12th/13th Gen with P-Cores and E-Cores

IRQ_CPUS="14-19"        # E-Cores for IRQ handling (stable latency)
AUDIO_MAIN_CPUS="6-7"   # P-Cores for JACK/PipeWire main processes
DAW_CPUS="0-5"          # P-Cores for DAW/Plugins (maximum performance)
BACKGROUND_CPUS="8-13"  # E-Cores for audio background tasks

# All CPUs range (for reset operations)
ALL_CPUS="0-19"

# ============================================================================
# DEFAULT SETTINGS
# ============================================================================

DEFAULT_GOVERNOR="powersave"

# ============================================================================
# MOTU M4 USB IDENTIFIERS
# ============================================================================

MOTU_VENDOR_ID="07fd"
MOTU_PRODUCT_ID="000b"
MOTU_CARD_ID="M4"

# ============================================================================
# XRUN MONITORING THRESHOLDS
# ============================================================================

XRUN_WARNING_THRESHOLD=10
XRUN_SEVERE_THRESHOLD=5

# ============================================================================
# TIMING CONSTANTS
# ============================================================================

# Monitoring intervals (in seconds)
MONITOR_INTERVAL=5
PROCESS_CHECK_INTERVAL=30  # Check process affinity every 30 seconds (6 cycles)
XRUN_CHECK_INTERVAL=10     # Check xruns every 10 seconds (2 cycles)

# Delayed service timing
MAX_AUDIO_WAIT=45          # Maximum wait time for user audio services

# ============================================================================
# AUDIO PROCESSES LIST
# ============================================================================

# Unified audio process list for all optimizations
# This central list is used by all audio optimization functions:
# - optimize_audio_process_affinity() for CPU pinning and RT priorities
# - reset_audio_process_affinity() for resetting optimizations
# - Status-Monitoring for process overview

AUDIO_PROCESSES=(
    # Audio engines and services (handled separately on AUDIO_MAIN_CPUS)
    "jackd"
    "jackdbus"
    "pipewire"
    "pipewire-pulse"
    "wireplumber"

    # DAWs and main audio software (DAW_CPUS + RT priority 70)
    "bitwig-studio"
    "reaper"
    "ardour"
    "studio"
    "cubase"
    "qtractor"
    "rosegarden"
    "renoise"
    "FL64.exe"
    "EZmix 3.exe"

    # Synthesizers and sound generators (DAW_CPUS + RT priority 70)
    "yoshimi"
    "pianoteq"
    "organteq"
    "grandorgue"
    "aeolus"
    "zynaddsubfx"
    "qsynth"
    "fluidsynth"
    "bristol"
    "M1.exe"
    "ARP 2600"
    "Polisix.exe"
    "EP-1.exe"
    "VOX Super Conti"
    "legacycell.exe"
    "wavestate nativ"
    "WAVESTATION.exe"
    "opsix_native.ex"
    "modwave native."
    "ARP ODYSSEY"
    "TRITON.exe"
    "TRITON_Extreme."
    "EZkeys 2.exe"
    "EZbass.exe"
    "AAS Player.exe"
    "Lounge Lizard S"

    # Drums and percussion (DAW_CPUS + RT priority 70)
    "hydrogen"
    "drumgizmo"
    "EZdrummer 3.exe"

    # Plugin hosts and audio tools (DAW_CPUS + RT priority 70)
    "carla"
    "jalv"
    "lv2host"
    "lv2rack"
    "jack-rack"
    "calf"
    "guitarix"
    "rakarrack"
    "klangfalter"

    # Audio editors (DAW_CPUS + RT priority 70)
    "musescore"
    "audacity"
)

# ============================================================================
# RT PRIORITY LEVELS
# ============================================================================

# Real-time priorities for different process types
RT_PRIORITY_JACK=99       # Highest for JACK server
RT_PRIORITY_PIPEWIRE=85   # High for PipeWire
RT_PRIORITY_PULSE=80      # PipeWire-Pulse
RT_PRIORITY_AUDIO=70      # DAWs, synths, plugins

# ============================================================================
# GREP PATTERNS FOR AUDIO PROCESSES
# ============================================================================

# Pattern for finding RT audio processes in ps output
AUDIO_GREP_PATTERN="pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack"

# ============================================================================
# VERSION INFO
# ============================================================================

OPTIMIZER_VERSION="4.0"
OPTIMIZER_NAME="MOTU M4 Dynamic Optimizer"
OPTIMIZER_STRATEGY="Hybrid Strategy (Stability-optimized)"
