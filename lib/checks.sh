#!/bin/bash

# MOTU M4 Dynamic Optimizer - System Checks Module
# Provides functions for detecting hardware and system state

# ============================================================================
# CPU ISOLATION CHECK
# ============================================================================

# Check if CPUs are isolated (via kernel parameters)
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

    log_message "📊 CPU-Isolation Status:"
    log_message "  Sys-Isolation: '$isolated_cpus'"
    log_message "  Kernel-Param: '$kernel_isolation'"

    echo "$isolated_cpus|$kernel_isolation"
}

# ============================================================================
# MOTU M4 DETECTION
# ============================================================================

# Check if MOTU M4 is connected
check_motu_m4() {
    local motu_found=false

    # Check ALSA cards
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
    if ! $motu_found; then
        if lsusb 2>/dev/null | grep -q "Mark of the Unicorn"; then
            motu_found=true
        fi
    fi

    echo $motu_found
}

# Get MOTU M4 ALSA card information
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

# Check if JACK is running
is_jack_running() {
    pgrep -x "jackd" > /dev/null 2>&1 || pgrep -x "jackdbus" > /dev/null 2>&1
}

# Check if PipeWire is running
is_pipewire_running() {
    pgrep -x "pipewire" > /dev/null 2>&1
}

# Check if QJackCtl is running
is_qjackctl_running() {
    pgrep -x "qjackctl" > /dev/null 2>&1
}

# Get the original user when running as root via sudo
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

# Get USB controller IRQs
get_usb_irqs() {
    cat /proc/interrupts 2>/dev/null | grep "xhci_hcd" | awk '{print $1}' | tr -d ':'
}

# Get audio-related IRQs
get_audio_irqs() {
    cat /proc/interrupts 2>/dev/null | grep -i "snd\|audio" | awk '{print $1}' | tr -d ':'
}

# Get IRQ affinity
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

# Count running audio processes
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

# Get current optimization state
get_current_state() {
    if [ -e "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "unknown"
    fi
}

# Set optimization state
set_state() {
    local state=$1
    echo "$state" > "$STATE_FILE" 2>/dev/null
}
