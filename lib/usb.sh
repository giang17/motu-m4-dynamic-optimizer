#!/bin/bash

# MOTU M4 Dynamic Optimizer - USB Module
# Contains MOTU M4 USB-specific optimization functions

# ============================================================================
# MOTU M4 USB OPTIMIZATION
# ============================================================================
#
# USB optimization is critical for audio interfaces to prevent dropouts.
# Key optimizations:
#   - Disable USB autosuspend to keep device always active
#   - Increase USB buffer memory for better throughput
#   - Optimize URB (USB Request Block) count for smoother transfers

# Optimize MOTU M4 USB settings for audio performance
# Main entry point for USB optimizations. Finds the device and applies
# all USB-related optimizations.
#
# Returns: 0 on success, 1 if device not found
optimize_motu_usb_settings() {
    log_message "🔌 Optimizing MOTU M4 USB settings..."

    local motu_device_path
    motu_device_path=$(get_motu_usb_path)

    if [ -z "$motu_device_path" ]; then
        log_message "  MOTU M4 USB device not found"
        return 1
    fi

    log_message "  MOTU M4 USB device found: $motu_device_path"

    # Disable power management for the MOTU M4
    _optimize_usb_power "$motu_device_path"

    # Optimize USB bulk transfer settings
    _optimize_usb_transfer "$motu_device_path"

    return 0
}

# ============================================================================
# USB POWER MANAGEMENT
# ============================================================================
#
# USB power management can cause audio dropouts when the device enters
# suspend mode. These settings ensure the MOTU M4 stays fully powered.

# Optimize USB power management for audio device
# Disables all power saving features that could cause audio interruptions.
#
# Args:
#   $1 - USB device sysfs path (from get_motu_usb_path)
#
# Modifies:
#   - power/control: Set to "on" (disable runtime PM)
#   - power/autosuspend: Set to -1 (disable autosuspend)
#   - power/autosuspend_delay_ms: Set to -1 (disable delay-based suspend)
_optimize_usb_power() {
    local usb_device="$1"

    # Disable USB autosuspend - keep device always on
    # "on" means device is always active, "auto" allows power management
    if [ -e "$usb_device/power/control" ]; then
        echo "on" > "$usb_device/power/control" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    Power-Management: always on"
        fi
    fi

    # Disable autosuspend delay (legacy interface)
    # -1 = never autosuspend
    if [ -e "$usb_device/power/autosuspend" ]; then
        echo -1 > "$usb_device/power/autosuspend" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    Autosuspend: disabled"
        fi
    fi

    # Disable autosuspend delay (ms version - newer kernels)
    # -1 = never autosuspend
    if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
        echo -1 > "$usb_device/power/autosuspend_delay_ms" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    Autosuspend-Delay: disabled"
        fi
    fi

    # Log runtime PM status for debugging
    if [ -e "$usb_device/power/runtime_status" ]; then
        local runtime_status
        runtime_status=$(cat "$usb_device/power/runtime_status" 2>/dev/null)
        log_message "    Runtime status: $runtime_status"
    fi
}

# ============================================================================
# USB TRANSFER OPTIMIZATION
# ============================================================================
#
# URBs (USB Request Blocks) are the data structures used for USB transfers.
# More URBs = more buffering = smoother audio at the cost of slightly higher latency.

# Optimize USB transfer settings
# Increases URB count for better audio streaming stability.
#
# Args:
#   $1 - USB device sysfs path
#
# Note: The urbnum parameter may not be writable on all systems/kernels.
#       This is normal and the optimization will be skipped silently.
_optimize_usb_transfer() {
    local usb_device="$1"

    # Increase URB count for better buffer handling
    # Default is typically 2-4, increasing to 32 provides more buffering
    if [ -e "$usb_device/urbnum" ]; then
        echo 32 > "$usb_device/urbnum" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    URB count increased to 32"
        else
            log_message "    URB optimization: No permission (normal)"
        fi
    fi
}

# ============================================================================
# USB STATUS INFORMATION
# ============================================================================

# Get MOTU M4 USB power status
# Returns formatted status information
get_motu_usb_power_status() {
    local usb_device
    usb_device=$(get_motu_usb_path)

    if [ -z "$usb_device" ]; then
        echo "   MOTU M4 USB device not found"
        return 1
    fi

    echo "   USB-Device: $usb_device"

    if [ -e "$usb_device/power/control" ]; then
        local control
        control=$(cat "$usb_device/power/control" 2>/dev/null)
        echo "   Power Control: $control"
    fi

    if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
        local delay
        delay=$(cat "$usb_device/power/autosuspend_delay_ms" 2>/dev/null)
        echo "   Autosuspend Delay: $delay ms"
    fi

    if [ -e "$usb_device/speed" ]; then
        local speed
        speed=$(cat "$usb_device/speed" 2>/dev/null)
        echo "   USB Speed: $speed"
    fi

    if [ -e "$usb_device/version" ]; then
        local version
        version=$(cat "$usb_device/version" 2>/dev/null | tr -d ' ')
        echo "   USB Version: $version"
    fi

    if [ -e "$usb_device/bMaxPower" ]; then
        local max_power
        max_power=$(cat "$usb_device/bMaxPower" 2>/dev/null)
        echo "   Max Power: $max_power"
    fi
}

# Get detailed MOTU M4 USB connection info
get_motu_usb_details() {
    local motu_usb
    motu_usb=$(lsusb 2>/dev/null | grep "Mark of the Unicorn")

    if [ -n "$motu_usb" ]; then
        echo "   $motu_usb"
        local usb_bus usb_device_num
        usb_bus=$(echo "$motu_usb" | awk '{print $2}')
        usb_device_num=$(echo "$motu_usb" | awk '{print $4}' | tr -d ':')
        echo "   Bus: $usb_bus, Device: $usb_device_num"
    else
        echo "   MOTU M4 not found in USB devices"
    fi
}

# ============================================================================
# USB MEMORY OPTIMIZATION
# ============================================================================
#
# The usbfs memory buffer limits how much data can be in-flight for USB
# transfers. The default (16MB) can be too low for high-bandwidth audio
# interfaces, especially at high sample rates.

# Optimize USB subsystem memory settings
# Increases the global USB filesystem memory buffer to 256MB.
# This affects all USB devices, not just the MOTU M4.
#
# Returns: 0 on success, 1 on failure
#
# Note: Requires root privileges to modify
optimize_usb_memory() {
    # Increase USB filesystem memory buffer
    # Default is typically 16MB, 256MB provides headroom for high-bandwidth audio
    if [ -e /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
        echo 256 > /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "  USB-Memory-Buffer: 256MB"
            return 0
        fi
    fi
    return 1
}

# Get current USB memory setting
# Returns the current usbfs memory buffer size in MB.
#
# Returns: Memory size in MB, or "N/A" if unavailable
get_usb_memory_setting() {
    if [ -e /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
        cat /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null
    else
        echo "N/A"
    fi
}
