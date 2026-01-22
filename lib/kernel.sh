#!/bin/bash

# MOTU M4 Dynamic Optimizer - Kernel Module
# Handles kernel parameter optimization for audio performance

# ============================================================================
# KERNEL PARAMETER OPTIMIZATION
# ============================================================================

# Optimize kernel parameters for audio processing
optimize_kernel_parameters() {
    log_message "⚙️  Optimize kernel parameters for audio..."

    # Real-Time Scheduling - Allow unlimited RT scheduling
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        echo -1 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  RT-Runtime: Unlimited"
        fi
    fi

    # Memory Management - Reduce swapping for audio stability
    if [ -e /proc/sys/vm/swappiness ]; then
        echo 10 > /proc/sys/vm/swappiness 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Swappiness: 10"
        fi
    fi

    # Scheduler Latency - Reduce for better audio response
    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        echo 1000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Scheduler latency: 1ms"
        fi
    fi

    # Minimum Granularity - Reduce for finer scheduling
    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo 100000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Min granularity: 0.1ms"
        fi
    fi

    # Wakeup Granularity - Reduce for faster process wakeup
    if [ -e /proc/sys/kernel/sched_wakeup_granularity_ns ]; then
        echo 100000 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Wakeup granularity: 0.1ms"
        fi
    fi
}

# ============================================================================
# KERNEL PARAMETER RESET
# ============================================================================

# Reset kernel parameters to standard values
reset_kernel_parameters() {
    log_message "⚙️  Reset kernel parameters..."

    # RT-Scheduling-Limit: Standard (95% of period for RT tasks)
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        echo 950000 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  RT-Runtime: Standard (950ms)"
        fi
    fi

    # Swappiness: Standard
    if [ -e /proc/sys/vm/swappiness ]; then
        echo 60 > /proc/sys/vm/swappiness 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Swappiness: Standard (60)"
        fi
    fi

    # Scheduler latency: Standard
    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        echo 6000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Scheduler latency: Standard (6ms)"
        fi
    fi

    # Min granularity: Standard
    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo 750000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Min granularity: Standard (0.75ms)"
        fi
    fi

    # Wakeup granularity: Standard
    if [ -e /proc/sys/kernel/sched_wakeup_granularity_ns ]; then
        echo 1000000 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  Wakeup granularity: Standard (1ms)"
        fi
    fi
}

# ============================================================================
# ADVANCED AUDIO OPTIMIZATIONS
# ============================================================================

# Activate advanced audio optimizations
optimize_advanced_audio_settings() {
    log_message "🎼 Activating advanced audio optimizations..."

    # USB-Bulk-Transfer-Optimizations - Increase USB buffer
    if [ -e /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
        echo 256 > /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  USB-Memory-Buffer: 256MB"
        fi
    fi

    # HPET frequency - Increase for better timing precision
    if [ -e /proc/sys/dev/hpet/max-user-freq ]; then
        echo 2048 > /proc/sys/dev/hpet/max-user-freq 2>/dev/null
        result=$?
        if [ $result -eq 0 ]; then
            log_message "  HPET-Frequency: 2048Hz"
        fi
    fi

    # Redirect network interface interrupts away from audio CPUs
    _optimize_network_rps
}

# Optimize network RPS (Receive Packet Steering) to avoid audio CPU interference
_optimize_network_rps() {
    for netif in /sys/class/net/*/queues/rx-*/rps_cpus; do
        if [ -e "$netif" ]; then
            # Restrict network RPS to E-Cores 8-13 (binary: 0011 1111 0000 0000 = 0x3f00)
            echo "00003f00" > "$netif" 2>/dev/null
        fi
    done
    log_message "  Network-Interrupts redirected to Background-E-Cores"
}

# ============================================================================
# KERNEL PARAMETER QUERIES
# ============================================================================

# Get current RT runtime setting
get_rt_runtime() {
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        cat /proc/sys/kernel/sched_rt_runtime_us
    else
        echo "N/A"
    fi
}

# Get current swappiness setting
get_swappiness() {
    if [ -e /proc/sys/vm/swappiness ]; then
        cat /proc/sys/vm/swappiness
    else
        echo "N/A"
    fi
}

# Get current scheduler latency setting
get_sched_latency() {
    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        cat /proc/sys/kernel/sched_latency_ns
    else
        echo "N/A"
    fi
}

# Get current min granularity setting
get_min_granularity() {
    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        cat /proc/sys/kernel/sched_min_granularity_ns
    else
        echo "N/A"
    fi
}

# Get current dirty ratio setting
get_dirty_ratio() {
    if [ -e /proc/sys/vm/dirty_ratio ]; then
        cat /proc/sys/vm/dirty_ratio
    else
        echo "N/A"
    fi
}

# Get current RT period setting
get_rt_period() {
    if [ -e /proc/sys/kernel/sched_rt_period_us ]; then
        cat /proc/sys/kernel/sched_rt_period_us
    else
        echo "N/A"
    fi
}

# ============================================================================
# STATUS DISPLAY HELPERS
# ============================================================================

# Display kernel parameter status
show_kernel_status() {
    local rt_runtime
    rt_runtime=$(get_rt_runtime)

    echo "⚙️  Kernel parameter status:"

    # RT Runtime
    if [ "$rt_runtime" = "-1" ]; then
        echo "   RT-Scheduling-Limit: Unlimited ✓"
    elif [ "$rt_runtime" != "N/A" ]; then
        echo "   RT-Scheduling-Limit: $rt_runtime µs"
    fi

    # RT Period
    local rt_period
    rt_period=$(get_rt_period)
    if [ "$rt_period" != "N/A" ]; then
        echo "   RT-Period: $rt_period µs"
    fi

    # Swappiness
    local swappiness
    swappiness=$(get_swappiness)
    if [ "$swappiness" != "N/A" ]; then
        echo "   Swappiness: $swappiness"
    fi

    # Dirty ratio
    local dirty_ratio
    dirty_ratio=$(get_dirty_ratio)
    if [ "$dirty_ratio" != "N/A" ]; then
        echo "   Dirty Ratio: $dirty_ratio%"
    fi
}

# Display advanced kernel parameter status (for detailed view)
show_advanced_kernel_status() {
    echo "   RT-Scheduling:"

    local rt_runtime
    rt_runtime=$(get_rt_runtime)
    if [ "$rt_runtime" = "-1" ]; then
        echo "     RT-Runtime: Unlimited ✓"
    elif [ "$rt_runtime" != "N/A" ]; then
        echo "     RT-Runtime: $rt_runtime µs"
    fi

    local rt_period
    rt_period=$(get_rt_period)
    if [ "$rt_period" != "N/A" ]; then
        echo "     RT-Period: $rt_period µs"
    fi

    echo "   Memory Management:"

    local swappiness
    swappiness=$(get_swappiness)
    if [ "$swappiness" != "N/A" ]; then
        echo "     Swappiness: $swappiness"
    fi

    local dirty_ratio
    dirty_ratio=$(get_dirty_ratio)
    if [ "$dirty_ratio" != "N/A" ]; then
        echo "     Dirty Ratio: $dirty_ratio%"
    fi
}
