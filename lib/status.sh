#!/bin/bash

# MOTU M4 Dynamic Optimizer - Status Module
# Contains status display and monitoring functions

# ============================================================================
# MAIN STATUS DISPLAY
# ============================================================================

# Show standard status display
show_status() {
    echo "=== $OPTIMIZER_NAME v$OPTIMIZER_VERSION Status ==="
    echo ""

    local motu_connected
    motu_connected=$(check_motu_m4)
    local current_state
    current_state=$(get_current_state)

    echo "🎛️  MOTU M4 detected: $motu_connected"
    echo "🔄 Current state: $current_state"

    # Show current JACK settings
    _show_jack_status

    echo ""

    # Detailed MOTU M4 information
    _show_motu_details

    # CPU isolation check
    local isolation_info
    isolation_info=$(check_cpu_isolation)
    echo "🔒 CPU-Isolation: $isolation_info"
    echo ""

    # CPU Governor status
    _show_cpu_governor_status "$current_state"

    # USB controller IRQ assignments
    echo ""
    _show_usb_irq_status

    # Audio IRQs
    echo ""
    _show_audio_irq_status

    # Active audio processes
    echo ""
    echo "🎵 Active audio processes:"
    list_audio_processes

    # Script performance info
    echo ""
    echo "🔧 Script-Performance:"
    get_script_performance_info

    # USB Power Management
    echo ""
    echo "🔋 MOTU M4 USB Power Management:"
    get_motu_usb_power_status

    # Kernel parameter status
    echo ""
    show_kernel_status

    # Optimization summary
    echo ""
    _show_optimization_summary

    echo ""
    echo "🎯 v4 Hybrid: Stability through optimized CPU assignment, performance where needed!"
}

# ============================================================================
# DETAILED STATUS DISPLAY
# ============================================================================

# Show detailed monitoring information
show_detailed_status() {
    echo "=== MOTU M4 Detailed Monitoring ==="
    echo ""

    # All MOTU M4 relevant information
    _show_motu_hardware_details

    echo ""
    _show_usb_connection_details

    echo ""
    _show_complete_irq_analysis

    echo ""
    _show_audio_process_details

    echo ""
    _show_cpu_details

    echo ""
    echo "⚙️  Advanced kernel parameters:"
    show_advanced_kernel_status

    echo ""
    _show_optimization_success_summary

    echo ""
    _show_recommended_next_steps

    echo ""
    _show_detailed_xrun_statistics
}

# ============================================================================
# JACK STATUS HELPERS
# ============================================================================

# Show JACK status information
_show_jack_status() {
    local jack_info
    jack_info=$(get_jack_settings)
    local jack_status bufsize samplerate nperiods
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "🎵 JACK Status: $jack_status"
    if [ "$jack_status" = "✅ Active" ]; then
        echo "   Settings: ${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            echo "   Periods: $nperiods"
        fi
    fi
}

# ============================================================================
# MOTU DETAILS HELPERS
# ============================================================================

# Show MOTU M4 details
_show_motu_details() {
    echo "🎵 MOTU M4 Details:"
    local motu_card
    motu_card=$(get_motu_card_info)

    if [ -n "$motu_card" ]; then
        echo "   Card: $(cat "/proc/asound/$motu_card/id" 2>/dev/null)"
        if [ -e "/proc/asound/$motu_card/stream0" ]; then
            echo "   Connection: $(cat "/proc/asound/$motu_card/stream0" 2>/dev/null | head -1)"
        fi
        if [ -e "/proc/asound/$motu_card/usbmixer" ]; then
            echo "   USB-Details: $(head -1 "/proc/asound/$motu_card/usbmixer" 2>/dev/null)"
        fi
    else
        echo "   MOTU M4 card not found in ALSA"
    fi

    # USB device status
    local motu_usb
    motu_usb=$(lsusb 2>/dev/null | grep "Mark of the Unicorn")
    if [ -n "$motu_usb" ]; then
        echo "   USB-Device: $motu_usb"
        local usb_bus
        usb_bus=$(echo "$motu_usb" | awk '{print $2}')
        echo "   USB Bus: $usb_bus"
    else
        echo "   MOTU M4 not found in USB devices"
    fi
}

# Show detailed MOTU hardware info
_show_motu_hardware_details() {
    echo "🎛️  MOTU M4 hardware status:"
    local motu_card
    motu_card=$(get_motu_card_info)

    if [ -n "$motu_card" ]; then
        echo "   Card: $(cat "/proc/asound/$motu_card/id" 2>/dev/null)"
        echo "   Stream-Status: $(cat "/proc/asound/$motu_card/stream0" 2>/dev/null | head -3)"
        if [ -e "/proc/asound/$motu_card/usbmixer" ]; then
            echo "   USB-Mixer: $(head -1 "/proc/asound/$motu_card/usbmixer" 2>/dev/null)"
        fi
    else
        echo "   MOTU M4 card not found in ALSA"
    fi
}

# Show USB connection details
_show_usb_connection_details() {
    echo "🔌 USB-Connection details:"
    get_motu_usb_details
    echo ""
    get_motu_usb_power_status
}

# ============================================================================
# CPU STATUS HELPERS
# ============================================================================

# Show CPU governor status
_show_cpu_governor_status() {
    local current_state="$1"

    echo "🖥️  CPU Governor Status (Hybrid Strategy):"
    if [ "$current_state" = "optimized" ]; then
        echo "   🚀 P-Cores: Performance | 🔋 Background E-Cores: Powersave | ⚡ IRQ E-Cores: Performance"
    else
        echo "   🔋 STANDARD: All CPUs on $DEFAULT_GOVERNOR governor"
    fi
    echo ""

    echo "   P-Cores (DAW/Plugins: 0-5, JACK/PipeWire: 6-7):"
    for cpu in 0 1 2 3 4 5 6 7; do
        _show_cpu_info "$cpu"
    done

    echo "   E-Cores (Background: 8-13, IRQ-Handling: 14-19):"
    for cpu in 8 9 10 11 12 13 14 15 16 17 18 19; do
        _show_cpu_info "$cpu" "with_role"
    done
}

# Show single CPU info
_show_cpu_info() {
    local cpu="$1"
    local show_role="${2:-}"

    if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
        local governor freq=""
        governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")

        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
            local freq_khz
            freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
            freq=" @ $(($freq_khz / 1000))MHz"
        fi

        local usage=""
        if [ "$show_role" = "with_role" ]; then
            if [ "$cpu" -ge 14 ] && [ "$cpu" -le 19 ]; then
                usage=" [IRQ]"
            elif [ "$cpu" -ge 8 ] && [ "$cpu" -le 13 ]; then
                usage=" [BG]"
            fi
        fi

        echo "     CPU $cpu: $governor$freq$usage"
    fi
}

# Show detailed CPU information
_show_cpu_details() {
    echo "🖥️  CPU-Details per core:"
    for cpu in {0..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            local governor freq_cur="" freq_min="" freq_max=""
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")

            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                local freq_khz
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq_cur=" @ $(($freq_khz / 1000))MHz"
            fi
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
                local freq_khz
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq")
                freq_min=" (min: $(($freq_khz / 1000))MHz"
            fi
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" ]; then
                local freq_khz
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq")
                freq_max=", max: $(($freq_khz / 1000))MHz)"
            fi

            local cpu_type="E-Core"
            local role="Background"
            if [ "$cpu" -le 7 ]; then
                cpu_type="P-Core"
                if [ "$cpu" -le 5 ]; then
                    role="DAW/Plugins"
                else
                    role="JACK/PipeWire"
                fi
            elif [ "$cpu" -ge 14 ] && [ "$cpu" -le 19 ]; then
                role="IRQ-Handling"
            fi

            echo "     CPU $cpu ($cpu_type - $role): $governor$freq_cur$freq_min$freq_max"
        fi
    done
}

# ============================================================================
# IRQ STATUS HELPERS
# ============================================================================

# Show USB IRQ status
_show_usb_irq_status() {
    echo "⚡ USB controller IRQ assignments:"
    cat /proc/interrupts 2>/dev/null | grep "xhci_hcd" | while read -r line; do
        local irq
        irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            local affinity threading balance balance_text
            affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            threading=$(cat "/proc/irq/$irq/threading" 2>/dev/null || echo "standard")
            balance=$(cat "/proc/irq/$irq/balance_disabled" 2>/dev/null || echo "0")
            balance_text="enabled"
            [ "$balance" = "1" ] && balance_text="disabled"

            local status_icon="✅"
            [ "$affinity" != "$IRQ_CPUS" ] && status_icon="⚠️"

            echo "   $status_icon IRQ $irq: CPUs $affinity, Threading: $threading, Balance: $balance_text"
        fi
    done
}

# Show audio IRQ status
_show_audio_irq_status() {
    echo "🔊 Audio-IRQs:"
    cat /proc/interrupts 2>/dev/null | grep -i "snd" | while read -r line; do
        local irq
        irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            local affinity balance balance_text
            affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            balance=$(cat "/proc/irq/$irq/balance_disabled" 2>/dev/null || echo "0")
            balance_text="enabled"
            [ "$balance" = "1" ] && balance_text="disabled"

            local status_icon="✅"
            [ "$affinity" != "$IRQ_CPUS" ] && status_icon="⚠️"

            echo "   $status_icon Audio IRQ $irq: CPUs $affinity, Balance: $balance_text"
        fi
    done
}

# Show complete IRQ analysis for detailed view
_show_complete_irq_analysis() {
    echo "⚡ Complete IRQ analysis:"
    echo "   USB controller IRQs:"
    cat /proc/interrupts 2>/dev/null | grep "xhci_hcd" | while read -r line; do
        local irq
        irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            local affinity threading balance balance_text spurious
            affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            threading=$(cat "/proc/irq/$irq/threading" 2>/dev/null || echo "standard")
            balance=$(cat "/proc/irq/$irq/balance_disabled" 2>/dev/null || echo "0")
            balance_text="enabled"
            [ "$balance" = "1" ] && balance_text="disabled"
            spurious=$(cat "/proc/irq/$irq/spurious" 2>/dev/null || echo "N/A")
            echo "     IRQ $irq: CPUs=$affinity, Threading=$threading, Balance=$balance_text"
            echo "       $line"
            echo "       Spurious: $spurious"
        fi
    done

    echo ""
    echo "   Audio-specific IRQs:"
    cat /proc/interrupts 2>/dev/null | grep -i "snd\|audio" | while read -r line; do
        local irq
        irq=$(echo "$line" | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            local affinity
            affinity=$(cat "/proc/irq/$irq/smp_affinity_list")
            echo "     Audio IRQ $irq: CPUs=$affinity"
            echo "       $line"
        fi
    done
}

# ============================================================================
# AUDIO PROCESS STATUS HELPERS
# ============================================================================

# Show audio process details with RT priorities
_show_audio_process_details() {
    echo "🎵 Audio process details with RT priorities:"
    local audio_rt_procs
    audio_rt_procs=$(ps -eo pid,class,rtprio,ni,comm,cmd 2>/dev/null | \
        grep -E "FF|RR" | \
        grep -iE "$AUDIO_GREP_PATTERN" | \
        grep -v "\[.*\]")

    if [ -n "$audio_rt_procs" ]; then
        echo "   RT audio processes found:"
        echo "$audio_rt_procs" | while read -r line; do
            echo "     $line"
        done
    else
        echo "   No audio processes with RT priority found"
        echo ""
        echo "   Standard audio processes (without RT):"
        ps -eo pid,class,rtprio,ni,comm,cmd 2>/dev/null | \
            grep -iE "$AUDIO_GREP_PATTERN" | \
            grep -v "\[.*\]" | \
            grep -v "grep" | \
            head -5 | while read -r line; do
                echo "     $line"
            done
    fi
}

# ============================================================================
# OPTIMIZATION SUMMARY HELPERS
# ============================================================================

# Show optimization summary
_show_optimization_summary() {
    echo "📊 Optimization Summary:"

    # USB IRQ optimization status
    local usb_irq_status
    usb_irq_status=$(count_optimized_usb_irqs)
    echo "   USB controller IRQs optimized: $usb_irq_status"

    # Audio IRQ optimization status
    local audio_irq_status
    audio_irq_status=$(count_optimized_audio_irqs)
    echo "   Audio IRQs optimized: $audio_irq_status"

    # RT audio process count
    local rt_audio_procs
    rt_audio_procs=$(count_rt_audio_processes)
    echo "   Audio processes with RT priority: $rt_audio_procs"

    # Xrun and performance status
    _show_xrun_performance_summary
}

# Show xrun performance summary
_show_xrun_performance_summary() {
    # Get all xrun data
    local xrun_stats system_xruns live_jack_xruns
    xrun_stats=$(get_xrun_stats)
    system_xruns=$(get_system_xruns)
    live_jack_xruns=$(get_live_jack_xruns)

    # Parse xrun data
    local jack_xruns pipewire_xruns recent_xruns severe_xruns
    jack_xruns=$(echo "$xrun_stats" | cut -d'|' -f1 | cut -d':' -f2)
    pipewire_xruns=$(echo "$xrun_stats" | cut -d'|' -f2 | cut -d':' -f2)
    recent_xruns=$(echo "$system_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    severe_xruns=$(echo "$system_xruns" | cut -d'|' -f2 | cut -d':' -f2)

    # Calculate total current xruns
    local total_current_xruns
    total_current_xruns=$((jack_xruns + pipewire_xruns + live_jack_xruns))

    # JACK settings in compact status display
    local jack_info jack_status bufsize samplerate nperiods
    jack_info=$(get_jack_settings)
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "   🎵 JACK: $jack_status"
    if [ "$jack_status" = "✅ Active" ]; then
        local settings_text="${bufsize}@${samplerate}Hz"
        [ "$nperiods" != "unknown" ] && settings_text="$settings_text, $nperiods periods"
        echo "       $settings_text"
    fi

    # Audio performance with consistent assessment
    if [ "$total_current_xruns" -eq 0 ] && [ "$recent_xruns" -eq 0 ]; then
        echo "   ✅ Audio performance: No problems"
        if [ "$jack_status" = "✅ Active" ]; then
            echo "       ${bufsize}@${samplerate}Hz running optimally stable"
        fi
    elif [ "$total_current_xruns" -lt 5 ] && [ "$severe_xruns" -eq 0 ]; then
        echo "   🟡 Audio-Performance: Occasional problems ($total_current_xruns Xruns)"
        _show_buffer_recommendation "$jack_status" "$bufsize"
    else
        echo "   🔴 Audio-Performance: Frequent problems ($total_current_xruns Xruns)"
        _show_severe_buffer_recommendation "$jack_status" "$bufsize" "$samplerate"
    fi

    [ "$severe_xruns" -gt 0 ] && echo "   ❌ Additional: Hardware errors ($severe_xruns in 5min)"

    echo ""
    _show_dynamic_buffer_recommendations "$jack_status" "$bufsize" "$samplerate" "$nperiods" "$total_current_xruns"
}

# Show buffer recommendation for mild issues
_show_buffer_recommendation() {
    local jack_status="$1"
    local bufsize="$2"

    if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ]; then
        if [ "$bufsize" -le 128 ]; then
            echo "       💡 For frequent problems: Increase buffer from $bufsize to 256 samples"
        elif [ "$bufsize" -le 256 ]; then
            echo "       💡 For frequent problems: Increase buffer from $bufsize to 512 samples"
        fi
    fi
}

# Show buffer recommendation for severe issues
_show_severe_buffer_recommendation() {
    local jack_status="$1"
    local bufsize="$2"
    local samplerate="$3"

    if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ]; then
        if [ "$bufsize" -le 64 ]; then
            echo "       💡 Immediate action: Increase buffer from $bufsize to 256+ samples"
        elif [ "$bufsize" -le 128 ]; then
            echo "       💡 Recommendation: Increase buffer from $bufsize to 512 samples"
        elif [ "$bufsize" -le 256 ]; then
            echo "       💡 Increase buffer from $bufsize to 1024 Samples or higher"
        else
            echo "       💡 Buffer already very high ($bufsize) - system optimization needed"
        fi
        if [ "$samplerate" != "unknown" ] && [ "$samplerate" -gt 48000 ]; then
            echo "       💡 Or reduce sample rate from ${samplerate}Hz to 48kHz"
        fi
    fi
}

# Show dynamic buffer recommendations
_show_dynamic_buffer_recommendations() {
    local jack_status="$1"
    local bufsize="$2"
    local samplerate="$3"
    local nperiods="$4"
    local total_current_xruns="$5"

    echo "💡 Dynamic buffer recommendations based on current settings:"

    if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ] && [ "$samplerate" != "unknown" ]; then
        # Calculate current latency
        local latency_ms
        latency_ms=$(calculate_latency_ms "$bufsize" "$samplerate")

        echo "   🎯 Current: $bufsize Samples @ ${samplerate}Hz = ${latency_ms}ms"

        # Dynamic recommendations based on xrun situation
        if [ "$total_current_xruns" -gt 20 ]; then
            # Aggressive recommendations for many xruns
            if [ "$bufsize" -le 256 ]; then
                local safe_buffer=1024
                local safe_latency
                safe_latency=$(calculate_latency_ms "$safe_buffer" "$samplerate")
                echo "   🔴 Problems detected: $safe_buffer Samples = ${safe_latency}ms recommended"
            else
                echo "   🔴 Buffer already high - check system performance"
            fi
        elif [ "$total_current_xruns" -gt 5 ]; then
            # Moderate recommendations for some xruns
            if [ "$bufsize" -le 128 ]; then
                local safe_buffer=512
                local safe_latency
                safe_latency=$(calculate_latency_ms "$safe_buffer" "$samplerate")
                echo "   🟡 Stability: $safe_buffer Samples = ${safe_latency}ms recommended"
            fi
        else
            # Standard recommendations for few/no xruns
            if [ "$bufsize" -le 64 ]; then
                local next_buffer=128
                local next_latency
                next_latency=$(calculate_latency_ms "$next_buffer" "$samplerate")
                echo "   🟡 More stable: $next_buffer Samples = ${next_latency}ms"
            elif [ "$bufsize" -le 128 ]; then
                local safe_buffer=256
                local safe_latency
                safe_latency=$(calculate_latency_ms "$safe_buffer" "$samplerate")
                echo "   🟢 More stable: $safe_buffer Samples = ${safe_latency}ms"
            else
                echo "   ✅ Buffer already in stable range"
            fi
        fi

        # Sample rate alternatives if needed
        if [ "$samplerate" -gt 48000 ] && [ "$total_current_xruns" -gt 10 ]; then
            local alt_latency
            alt_latency=$(calculate_latency_ms "$bufsize" "48000")
            echo "   🔄 Alternative: $bufsize@48kHz = ${alt_latency}ms (more stable)"
        fi

        # Periods recommendation for problems
        if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ] && [ "$total_current_xruns" -gt 5 ]; then
            echo "   🔧 Important: Use 3 periods instead of $nperiods for better latency tolerance"
        fi
    else
        echo "   🟢 Stable (256): Very stable, low latency (~5.3ms @ 48kHz)"
        echo "   🟡 Optimal (128): Good latency, moderate CPU load (~2.7ms @ 48kHz)"
        echo "   🟠 Aggressive (64): Low latency, high CPU load (~1.3ms @ 48kHz)"
        echo "   🔴 Extreme (32): Only for tests (~0.7ms @ 48kHz)"
    fi
}

# ============================================================================
# DETAILED STATUS HELPERS
# ============================================================================

# Show optimization success summary for detailed view
_show_optimization_success_summary() {
    echo "📊 Optimization success summary:"

    # USB IRQ optimization
    local usb_irq_status
    usb_irq_status=$(count_optimized_usb_irqs)
    echo "   ✅ USB controller IRQs on CPUs 14-19: $usb_irq_status"

    # RT audio process count
    local rt_audio_procs
    rt_audio_procs=$(count_rt_audio_processes)
    echo "   ✅ Audio processes with RT priority: $rt_audio_procs"

    # MOTU M4 hardware status
    local motu_card
    motu_card=$(get_motu_card_info)
    if [ -n "$motu_card" ]; then
        echo "   ✅ MOTU M4 hardware: Detected as $motu_card"
    else
        echo "   ❌ MOTU M4 hardware: Not detected"
    fi
}

# Show recommended next steps
_show_recommended_next_steps() {
    echo "🏁 Recommended next steps:"

    local usb_irq_status
    usb_irq_status=$(count_optimized_usb_irqs)
    local optimized
    optimized=$(echo "$usb_irq_status" | cut -d'/' -f1)

    if [ "$optimized" -eq 0 ]; then
        echo "   🔧 Run 'sudo motu-m4-dynamic-optimizer.sh once' to activate IRQ optimizations"
    fi

    local rt_audio_procs
    rt_audio_procs=$(count_rt_audio_processes)
    if [ "$rt_audio_procs" -eq 0 ]; then
        echo "   🎵 Start audio software for automatic RT priority assignment"
    fi

    local motu_card
    motu_card=$(get_motu_card_info)
    if [ -z "$motu_card" ]; then
        echo "   🔌 Check the MOTU M4 USB connection"
    fi
}

# Show detailed xrun statistics
_show_detailed_xrun_statistics() {
    echo "🎵 Detailed audio xrun statistics:"

    # Collect xrun statistics
    local xrun_stats system_xruns live_jack_xruns
    xrun_stats=$(get_xrun_stats)
    system_xruns=$(get_system_xruns)
    live_jack_xruns=$(get_live_jack_xruns)

    # Parse xrun data
    local jack_xruns pipewire_xruns total_xruns
    jack_xruns=$(echo "$xrun_stats" | cut -d'|' -f1 | cut -d':' -f2)
    pipewire_xruns=$(echo "$xrun_stats" | cut -d'|' -f2 | cut -d':' -f2)
    total_xruns=$(echo "$xrun_stats" | cut -d'|' -f3 | cut -d':' -f2)

    local recent_xruns severe_xruns jack_messages
    recent_xruns=$(echo "$system_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    severe_xruns=$(echo "$system_xruns" | cut -d'|' -f2 | cut -d':' -f2)
    jack_messages=$(echo "$system_xruns" | cut -d'|' -f3 | cut -d':' -f2)

    # Status icon based on xruns
    local xrun_icon="✅"
    if [ "$total_xruns" -gt 0 ] || [ "$recent_xruns" -gt 0 ] || [ "$live_jack_xruns" -gt 0 ]; then
        xrun_icon="⚠️"
    fi
    [ "$severe_xruns" -gt 0 ] && xrun_icon="❌"

    echo "   $xrun_icon JACK Xruns (1min): $jack_xruns"
    echo "   $xrun_icon PipeWire Xruns (1min): $pipewire_xruns"
    echo "   $xrun_icon Live JACK Status: $live_jack_xruns"
    echo "   $xrun_icon JACK Messages (5min): $jack_messages"
    echo "   $xrun_icon System Audio-Problems (5min): $recent_xruns"
    [ "$severe_xruns" -gt 0 ] && echo "   ❌ Hardware-Errors (5min): $severe_xruns"

    # Dynamic xrun assessment and recommendations
    local total_current_xruns
    total_current_xruns=$((jack_xruns + pipewire_xruns + live_jack_xruns))

    local severity
    severity=$(get_xrun_severity "$total_current_xruns" "$severe_xruns")
    get_dynamic_xrun_recommendations "$total_current_xruns" "$severity"

    # Additional recommendations for persistent problems
    if [ "$recent_xruns" -gt 3 ]; then
        echo ""
        echo "   🎛️ Additional recommendations for persistent audio problems:"
        get_dynamic_xrun_recommendations "$recent_xruns" "severe"
    fi
}
