#!/bin/bash

# MOTU M4 Dynamic Optimizer - System Checks Module
# Provides functions for detecting hardware and system state
#
# ============================================================================
# MODULE API REFERENCE
# ============================================================================
#
# PUBLIC FUNCTIONS:
#
#   check_cpu_isolation()
#     Checks CPU isolation status from kernel and runtime.
#     @return : string - "sys_isolated|kernel_param" (pipe-separated)
#     @stdout : Isolation status string
#
#   check_motu_m4()
#     Detects if MOTU M4 audio interface is connected.
#     @return : string - "true" or "false"
#     @stdout : Detection result as string
#
#   get_motu_card_info()
#     Gets ALSA card directory name for MOTU M4.
#     @return : string - Card name (e.g., "card1") or empty
#     @stdout : ALSA card identifier
#
#   get_motu_usb_path()
#     Finds sysfs path for MOTU M4 USB device.
#     @return : string - Full sysfs path or empty
#     @exit   : 0 if found, 1 if not found
#     @stdout : USB device path
#
#   is_jack_running()
#     Checks if JACK audio server is running.
#     @exit   : 0 if running, 1 if not
#
#   is_pipewire_running()
#     Checks if PipeWire is running.
#     @exit   : 0 if running, 1 if not
#
#   is_qjackctl_running()
#     Checks if QJackCtl GUI is running.
#     @exit   : 0 if running, 1 if not
#
#   get_original_user()
#     Gets username when running via sudo.
#     @return : string - Username or empty
#     @stdout : Original username
#
#   get_usb_irqs()
#     Gets IRQ numbers for USB (xHCI) controllers.
#     @return : string - Space-separated IRQ numbers
#     @stdout : IRQ list
#
#   get_audio_irqs()
#     Gets IRQ numbers for audio devices.
#     @return : string - Space-separated IRQ numbers
#     @stdout : IRQ list
#
#   get_irq_affinity(irq)
#     Gets CPU affinity for an IRQ.
#     @param  irq : int - IRQ number
#     @return     : string - CPU list (e.g., "14-19") or "N/A"
#     @stdout     : Affinity string
#
#   count_audio_processes()
#     Counts running audio processes.
#     @return : int - Process count
#     @stdout : Count as string
#
#   count_rt_audio_processes()
#     Counts audio processes with RT scheduling.
#     @return : int - RT process count
#     @stdout : Count as string
#
#   get_current_state()
#     Gets current optimization state.
#     @return : string - "optimized", "standard", or "unknown"
#     @stdout : State string
#
#   set_state(state)
#     Sets optimization state.
#     @param  state : string - "optimized" or "standard"
#     @return       : void
#     @file         : Writes to STATE_FILE
#
# DEPENDENCIES:
#   - config.sh (MOTU_CARD_ID, MOTU_VENDOR_ID, MOTU_PRODUCT_ID,
#                AUDIO_PROCESSES, AUDIO_GREP_PATTERN, STATE_FILE)
#   - logging.sh (log_debug)
#
# ============================================================================
# CPU ISOLATION CHECK
# ============================================================================
#
# CPU isolation removes CPUs from the kernel scheduler, reserving them
# exclusively for specific tasks. This can improve latency but requires
# explicit process pinning to use isolated CPUs.

# Check if CPUs are isolated (via kernel parameters)
# Checks both runtime state and boot parameters for isolation settings.
#
# Returns: "sys_isolated|kernel_param" (pipe-separated string)
#   - sys_isolated: CPUs currently isolated (from /sys/devices/system/cpu/isolated)
#   - kernel_param: isolcpus= boot parameter value (if set)
#
# Example output: "2-3|2-3" or "|" if no isolation
check_cpu_isolation() {
    local isolated_cpus=""
    if [ -e "/sys/devices/system/cpu/isolated" ]; then
        isolated_cpus=$(cat /sys/devices/system/cpu/isolated)
    fi

    # Also check kernel boot parameters
    local kernel_isolation=""
    if grep -q "isolcpus=" /proc/cmdline; then
        kernel_isolation=$(grep -o "isolcpus=[0-9,-]*" /proc/cmdline | cut -d= -f2)
    fi

    log_debug "📊 CPU-Isolation Status:"
    log_debug "  Sys-Isolation: '$isolated_cpus'"
    log_debug "  Kernel-Param: '$kernel_isolation'"

    echo "$isolated_cpus|$kernel_isolation"
}

# ============================================================================
# MOTU M4 DETECTION
# ============================================================================
#
# Detection methods for MOTU M4 audio interface:
#   1. ALSA card check: Looks for card ID "M4" in /proc/asound/
#   2. USB fallback: Checks lsusb for "Mark of the Unicorn" vendor string
#
# The MOTU M4 uses USB Audio Class 2 and appears as a standard USB audio device.

# Check if MOTU M4 is connected
# Uses multiple detection methods for reliability.
#
# Returns: "true" or "false" (as string, not exit code)
check_motu_m4() {
    local motu_found=false

    # Check ALSA cards - primary detection method
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            local card_id
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "$MOTU_CARD_ID" ]; then
                motu_found=true
                break
            fi
        fi
    done

    # Additional USB check if not found via ALSA
    # Catches cases where device is connected but not yet initialized
    if ! $motu_found; then
        if lsusb 2>/dev/null | grep -q "Mark of the Unicorn"; then
            motu_found=true
        fi
    fi

    echo $motu_found
}

# Get MOTU M4 ALSA card information
# Finds the ALSA card directory name (e.g., "card1") for the MOTU M4.
#
# Returns: ALSA card name (e.g., "card1") or empty string if not found
#
# Example usage:
#   card=$(get_motu_card_info)
#   cat "/proc/asound/$card/stream0"  # Get stream info
get_motu_card_info() {
    local motu_card=""

    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            local card_id
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "$MOTU_CARD_ID" ]; then
                motu_card=$(basename "$card")
                break
            fi
        fi
    done

    echo "$motu_card"
}

# Get MOTU M4 USB device path
# Searches /sys/bus/usb/devices/ for the MOTU M4 by vendor/product ID.
#
# Returns: Full sysfs path (e.g., "/sys/bus/usb/devices/1-2") or empty string
# Exit code: 0 if found, 1 if not found
#
# The returned path can be used to access USB device attributes like:
#   - power/control - USB power management
#   - speed - USB connection speed
#   - bMaxPower - Maximum power draw
get_motu_usb_path() {
    for usb_device in /sys/bus/usb/devices/*; do
        if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
            local vendor product
            vendor=$(cat "$usb_device/idVendor" 2>/dev/null)
            product=$(cat "$usb_device/idProduct" 2>/dev/null)

            if [ "$vendor" = "$MOTU_VENDOR_ID" ] && [ "$product" = "$MOTU_PRODUCT_ID" ]; then
                echo "$usb_device"
                return 0
            fi
        fi
    done

    echo ""
    return 1
}

# ============================================================================
# AUDIO SERVICE DETECTION
# ============================================================================
#
# Functions to detect running audio services. These are used to determine
# which optimizations to apply and to query audio server settings.

# Check if JACK is running
# Checks for both standalone jackd and DBus-activated jackdbus.
#
# Exit code: 0 if running, 1 if not
is_jack_running() {
    pgrep -x "jackd" > /dev/null 2>&1 || pgrep -x "jackdbus" > /dev/null 2>&1
}

# Check if PipeWire is running
# PipeWire can provide JACK compatibility via its JACK tunnel.
#
# Exit code: 0 if running, 1 if not
is_pipewire_running() {
    pgrep -x "pipewire" > /dev/null 2>&1
}

# Check if QJackCtl is running
# QJackCtl is a common GUI for JACK control and monitoring.
#
# Exit code: 0 if running, 1 if not
is_qjackctl_running() {
    pgrep -x "qjackctl" > /dev/null 2>&1
}

# Get the original user when running as root via sudo
# Used to run user-context commands (like jack_control) correctly.
#
# Returns: Username of the original user, or empty if can't determine
#
# Example:
#   user=$(get_original_user)
#   sudo -u "$user" jack_bufsize
get_original_user() {
    local original_user=""

    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        original_user="$SUDO_USER"
    elif [ "$EUID" -ne 0 ]; then
        original_user="$(whoami)"
    fi

    echo "$original_user"
}

# ============================================================================
# IRQ DETECTION
# ============================================================================
#
# IRQs (Interrupt Requests) are hardware signals that interrupt the CPU.
# For low-latency audio, IRQ handling should be pinned to specific CPUs
# to avoid interfering with audio processing on other cores.

# Get USB controller IRQs
# Returns a list of IRQ numbers for xHCI (USB 3.0) controllers.
# These are important for USB audio devices like the MOTU M4.
#
# Returns: Space-separated list of IRQ numbers
get_usb_irqs() {
    cat /proc/interrupts 2>/dev/null | grep "xhci_hcd" | awk '{print $1}' | tr -d ':'
}

# Get audio-related IRQs
# Returns IRQ numbers for sound devices (snd_* drivers).
#
# Returns: Space-separated list of IRQ numbers
get_audio_irqs() {
    cat /proc/interrupts 2>/dev/null | grep -i "snd\|audio" | awk '{print $1}' | tr -d ':'
}

# Get IRQ affinity (which CPUs can handle this IRQ)
#
# Args:
#   $1 - IRQ number
#
# Returns: CPU list (e.g., "14-19") or "N/A" if unavailable
get_irq_affinity() {
    local irq=$1

    if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
        cat "/proc/irq/$irq/smp_affinity_list"
    else
        echo "N/A"
    fi
}

# ============================================================================
# PROCESS DETECTION
# ============================================================================
#
# Functions to count and identify audio-related processes.
# Used for status display and to determine optimization scope.

# Count running audio processes
# Counts processes matching names in the AUDIO_PROCESSES array.
#
# Returns: Number of matching processes
count_audio_processes() {
    local count=0

    for process in "${AUDIO_PROCESSES[@]}"; do
        local pids
        pids=$(pgrep -x "$process" 2>/dev/null | wc -l)
        count=$((count + pids))
    done

    echo "$count"
}

# Get RT audio process count
# Counts audio processes running with real-time scheduling (SCHED_FIFO/SCHED_RR).
# FF = SCHED_FIFO, RR = SCHED_RR in ps output.
#
# Returns: Number of RT audio processes
count_rt_audio_processes() {
    ps -eo pid,class,rtprio,comm,cmd 2>/dev/null | \
        grep -E "FF|RR" | \
        grep -iE "$AUDIO_GREP_PATTERN" | \
        grep -v "\[.*\]" | \
        wc -l
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================
#
# The optimizer maintains state in a file to track whether optimizations
# are currently active. This prevents redundant optimization attempts
# and enables proper cleanup on deactivation.

# Get current optimization state
# Reads state from STATE_FILE (/var/run/motu-m4-state).
#
# Returns: "optimized", "standard", or "unknown"
get_current_state() {
    if [ -e "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "unknown"
    fi
}

# Set optimization state
# Writes state to STATE_FILE for persistence across script invocations.
#
# Args:
#   $1 - State to set ("optimized" or "standard")
set_state() {
    local state=$1
    echo "$state" > "$STATE_FILE" 2>/dev/null
}
