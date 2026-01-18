#!/bin/bash

# MOTU M4 Dynamic Optimizer - USB Module
# Contains MOTU M4 USB-specific optimization functions

# ============================================================================
# MOTU M4 USB OPTIMIZATION
# ============================================================================

# Optimize MOTU M4 USB settings for audio performance
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

# Optimize USB power management for audio device
# Args: $1 = USB device path
_optimize_usb_power() {
    local usb_device="$1"

    # Disable USB autosuspend - keep device always on
    if [ -e "$usb_device/power/control" ]; then
        echo "on" > "$usb_device/power/control" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    Power-Management: always on"
        fi
    fi

    # Disable autosuspend delay
    if [ -e "$usb_device/power/autosuspend" ]; then
        echo -1 > "$usb_device/power/autosuspend" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    Autosuspend: disabled"
        fi
    fi

    # Disable autosuspend delay (ms version)
    if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
        echo -1 > "$usb_device/power/autosuspend_delay_ms" 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "    Autosuspend-Delay: disabled"
        fi
    fi

    # Set runtime PM to always on
    if [ -e "$usb_device/power/runtime_status" ]; then
        local runtime_status
        runtime_status=$(cat "$usb_device/power/runtime_status" 2>/dev/null)
        log_message "    Runtime status: $runtime_status"
    fi
}

# ============================================================================
# USB TRANSFER OPTIMIZATION
# ============================================================================

# Optimize USB transfer settings
# Args: $1 = USB device path
_optimize_usb_transfer() {
    local usb_device="$1"

    # Increase URB count for better buffer handling
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

# Optimize USB subsystem memory settings
optimize_usb_memory() {
    # Increase USB filesystem memory buffer
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
get_usb_memory_setting() {
    if [ -e /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
        cat /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null
    else
        echo "N/A"
    fi
}
