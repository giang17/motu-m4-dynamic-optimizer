#!/bin/bash

# MOTU M4 Dynamic Optimizer - Optimization Module
# Contains main activation and deactivation functions for audio optimizations

# ============================================================================
# MAIN ACTIVATION
# ============================================================================

# Activate audio optimizations - Hybrid Strategy (Stability-optimized)
# P-Cores on Performance, Background E-Cores on Powersave, IRQ E-Cores on Performance
activate_audio_optimizations() {
    log_message "🎵 MOTU M4 detected - Activating hybrid audio optimizations..."
    log_message "🏗️  Strategy: P-Cores(0-7) Performance, Background E-Cores(8-13) Powersave, IRQ E-Cores(14-19) Performance"

    # Optimize P-Cores for audio processing (0-7)
    _optimize_p_cores

    # Keep background E-Cores on Powersave (8-13) - Reduces interference
    _configure_background_e_cores

    # IRQ E-Cores to Performance (14-19)
    _optimize_irq_e_cores

    # Set USB controller IRQs to E-Cores
    _optimize_usb_irqs

    # Set audio IRQs to E-Cores
    _optimize_audio_irqs

    # Set audio process affinity to optimal P-Cores
    optimize_audio_process_affinity

    # MOTU M4 USB optimizations
    optimize_motu_usb_settings

    # Kernel parameter optimizations
    optimize_kernel_parameters

    # Advanced audio optimizations
    optimize_advanced_audio_settings

    # Save state
    set_state "optimized"
    log_message "✅ Hybrid audio optimizations activated - Stability and performance optimal!"
}

# ============================================================================
# MAIN DEACTIVATION
# ============================================================================

# Deactivate audio optimizations - Back to standard
deactivate_audio_optimizations() {
    log_message "🔧 MOTU M4 not detected - Reset to standard configuration..."

    # Reset audio-relevant CPUs (P-Cores + IRQ E-Cores)
    _reset_cpu_governors

    # Reset process affinity
    reset_audio_process_affinity

    # Reset USB controller IRQs to all CPUs
    _reset_usb_irqs

    # Reset Audio IRQs to all CPUs
    _reset_audio_irqs

    # Reset kernel parameters
    reset_kernel_parameters

    # Save state
    set_state "standard"
    log_message "✅ Hybrid optimizations deactivated, system reset to standard"
}

# ============================================================================
# CPU GOVERNOR OPTIMIZATION
# ============================================================================

# Optimize P-Cores (0-7) for audio processing
_optimize_p_cores() {
    log_message "🚀 Optimize P-Cores (0-7) for audio processing..."

    for cpu in {0..7}; do
        # Set governor to performance
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
            result=$?
            if [ $result -eq 0 ]; then
                log_message "  P-Core CPU $cpu: Governor set to 'performance'"
            fi
        fi

        # P-Core specific optimizations: Set min frequency to max
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
            local max_freq
            max_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" 2>/dev/null)
            if [ -n "$max_freq" ]; then
                echo "$max_freq" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null
                result=$?
                if [ $result -eq 0 ]; then
                    log_message "  P-Core CPU $cpu: Min-Frequency set to maximum"
                fi
            fi
        fi
    done
}

# Keep background E-Cores (8-13) on Powersave for stability
_configure_background_e_cores() {
    log_message "🔋 Keep Background E-Cores (8-13) on Powersave for stability..."

    for cpu in {8..13}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            local current_governor
            current_governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            if [ "$current_governor" != "$DEFAULT_GOVERNOR" ]; then
                echo "$DEFAULT_GOVERNOR" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
                result=$?
                if [ $result -eq 0 ]; then
                    log_message "  Background E-Core CPU $cpu: Governor set to '$DEFAULT_GOVERNOR'"
                fi
            fi
        fi
    done
}

# Optimize IRQ E-Cores (14-19) for stable latency
_optimize_irq_e_cores() {
    log_message "⚡ Optimize IRQ E-Cores (14-19) for stable latency..."

    for cpu in {14..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
            result=$?
            if [ $result -eq 0 ]; then
                log_message "  IRQ E-Core CPU $cpu: Governor set to 'performance'"
            fi
        fi
    done
}

# Reset CPU governors to default
_reset_cpu_governors() {
    log_message "🔋 Reset audio-relevant CPUs to standard governor..."

    # Reset P-Cores and IRQ E-Cores
    for cpu in {0..7} {14..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            local current_governor
            current_governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            if [ "$current_governor" = "performance" ]; then
                echo "$DEFAULT_GOVERNOR" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
                result=$?
                if [ $result -eq 0 ]; then
                    log_message "  CPU $cpu: Governor reset to '$DEFAULT_GOVERNOR'"
                fi
            fi
        fi

        # Reset min frequency
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
            local min_freq
            min_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_min_freq" 2>/dev/null)
            if [ -n "$min_freq" ]; then
                echo "$min_freq" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null
            fi
        fi
    done
}

# ============================================================================
# IRQ OPTIMIZATION
# ============================================================================

# Optimize USB controller IRQs
_optimize_usb_irqs() {
    log_message "🎯 USB controller IRQs to E-Cores (14-19) for stable latency..."

    local usb_irqs
    usb_irqs=$(get_usb_irqs)

    for irq in $usb_irqs; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            echo "$IRQ_CPUS" > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
            result=$?
            if [ $result -eq 0 ]; then
                log_message "  USB controller IRQ $irq set to E-Cores $IRQ_CPUS"
            fi

            # IRQ optimizations: Force threading
            if [ -e "/proc/irq/$irq/threading" ]; then
                echo "forced" > "/proc/irq/$irq/threading" 2>/dev/null
            fi

            # Disable IRQ balancing for this IRQ
            if [ -e "/proc/irq/$irq/balance_disabled" ]; then
                echo 1 > "/proc/irq/$irq/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Fallback for known IRQs (common USB controller IRQs)
    for irq in 156 176; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            echo "$IRQ_CPUS" > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
            result=$?
            if [ $result -eq 0 ]; then
                log_message "  Fallback: IRQ $irq set to E-Cores $IRQ_CPUS"
            fi
        fi
    done
}

# Optimize audio-related IRQs
_optimize_audio_irqs() {
    log_message "🔊 Audio IRQs to E-Cores (14-19) for optimal latency..."

    local audio_irqs
    audio_irqs=$(get_audio_irqs)

    for irq in $audio_irqs; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            local current_affinity
            current_affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            if [ "$current_affinity" != "$IRQ_CPUS" ]; then
                echo "$IRQ_CPUS" > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
                result=$?
                if [ $result -eq 0 ]; then
                    log_message "  Audio IRQ $irq set to E-Cores $IRQ_CPUS (was: $current_affinity)"
                fi
            fi

            # Disable IRQ balance for audio IRQs
            if [ -e "/proc/irq/$irq/balance_disabled" ]; then
                echo 1 > "/proc/irq/$irq/balance_disabled" 2>/dev/null
            fi
        fi
    done
}

# Reset USB controller IRQs to all CPUs
_reset_usb_irqs() {
    local usb_irqs
    usb_irqs=$(get_usb_irqs)

    for irq in $usb_irqs; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            echo "$ALL_CPUS" > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
            result=$?
            if [ $result -eq 0 ]; then
                log_message "  USB controller IRQ $irq reset to all CPUs ($ALL_CPUS)"
            fi

            # Re-enable IRQ balancing
            if [ -e "/proc/irq/$irq/balance_disabled" ]; then
                echo 0 > "/proc/irq/$irq/balance_disabled" 2>/dev/null
            fi
        fi
    done
}

# Reset audio IRQs to all CPUs
_reset_audio_irqs() {
    local audio_irqs
    audio_irqs=$(get_audio_irqs)

    for irq in $audio_irqs; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            echo "$ALL_CPUS" > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null
            result=$?
            if [ $result -eq 0 ]; then
                log_message "  Audio IRQ $irq reset to all CPUs ($ALL_CPUS)"
            fi

            # Re-enable IRQ balancing
            if [ -e "/proc/irq/$irq/balance_disabled" ]; then
                echo 0 > "/proc/irq/$irq/balance_disabled" 2>/dev/null
            fi
        fi
    done
}

# ============================================================================
# OPTIMIZATION STATUS HELPERS
# ============================================================================

# Count optimized USB IRQs
count_optimized_usb_irqs() {
    local optimized=0
    local total=0
    local usb_irqs

    usb_irqs=$(get_usb_irqs)

    for irq in $usb_irqs; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            total=$((total + 1))
            local affinity
            affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            if [ "$affinity" = "$IRQ_CPUS" ]; then
                optimized=$((optimized + 1))
            fi
        fi
    done

    echo "$optimized/$total"
}

# Count optimized audio IRQs
count_optimized_audio_irqs() {
    local optimized=0
    local total=0
    local audio_irqs

    audio_irqs=$(get_audio_irqs)

    for irq in $audio_irqs; do
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            total=$((total + 1))
            local affinity
            affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            if [ "$affinity" = "$IRQ_CPUS" ]; then
                optimized=$((optimized + 1))
            fi
        fi
    done

    echo "$optimized/$total"
}

# Check if system is currently optimized
is_system_optimized() {
    local current_state
    current_state=$(get_current_state)

    if [ "$current_state" = "optimized" ]; then
        return 0
    else
        return 1
    fi
}
