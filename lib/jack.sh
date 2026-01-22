#!/bin/bash

# MOTU M4 Dynamic Optimizer - JACK Module
# Contains JACK-related functions for settings retrieval and recommendations

# ============================================================================
# JACK SETTINGS RETRIEVAL
# ============================================================================

# Get current JACK settings
# Returns: "status|bufsize|samplerate|nperiods"
get_jack_settings() {
    local bufsize="unknown"
    local samplerate="unknown"
    local nperiods="unknown"
    local jack_status="❌ Not active"

    # Determine the original user if script runs as root via sudo
    local original_user=""
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        original_user="$SUDO_USER"
    elif [ "$EUID" -ne 0 ]; then
        original_user="$(whoami)"
    fi

    # Check if JACK is running AND M4 is available
    if pgrep -x "jackd" > /dev/null 2>&1 || pgrep -x "jackdbus" > /dev/null 2>&1; then
        # JACK process running, but also check M4 availability
        local motu_available="false"
        if ls /proc/asound/*/id 2>/dev/null | xargs cat 2>/dev/null | grep -q M4; then
            motu_available="true"
        fi

        if [ "$motu_available" = "true" ]; then
            jack_status="✅ Active"
        else
            jack_status="⚠️ Running (M4 not available)"
        fi

        # Function to execute JACK commands in user context
        run_jack_command() {
            local cmd="$1"
            if [ -n "$original_user" ] && [ "$EUID" -eq 0 ]; then
                # As root: Use sudo -u to run in user context
                sudo -u "$original_user" "$cmd" 2>/dev/null || echo "unknown"
            else
                # As normal user: Execute directly
                "$cmd" 2>/dev/null || echo "unknown"
            fi
        }

        # Try to determine JACK parameters
        if command -v jack_bufsize &> /dev/null; then
            bufsize=$(run_jack_command "jack_bufsize")
        fi

        if command -v jack_samplerate &> /dev/null; then
            samplerate=$(run_jack_command "jack_samplerate")
        fi

        if command -v jack_control &> /dev/null; then
            # Extract nperiods value from format "uint:set:2:3" - take the last value
            if [ -n "$original_user" ] && [ "$EUID" -eq 0 ]; then
                nperiods=$(sudo -u "$original_user" jack_control dp 2>/dev/null | grep nperiods | awk -F':' '{print $NF}' | tr -d ')' || echo "unknown")
            else
                nperiods=$(jack_control dp 2>/dev/null | grep nperiods | awk -F':' '{print $NF}' | tr -d ')' || echo "unknown")
            fi
        fi

        # Fallback: If all JACK commands fail, but process runs
        if [ "$bufsize" = "unknown" ] && [ "$samplerate" = "unknown" ] && [ -n "$original_user" ]; then
            if [ "$jack_status" = "✅ Active" ]; then
                jack_status="⚠️ Active (user session)"
            fi
        fi
    fi

    echo "$jack_status|$bufsize|$samplerate|$nperiods"
}

# ============================================================================
# JACK LATENCY CALCULATIONS
# ============================================================================

# Calculate latency in milliseconds from buffer size and sample rate
# Args: $1 = buffer size, $2 = sample rate
# Returns: latency in ms (with bc) or approximate value
calculate_latency_ms() {
    local bufsize="$1"
    local samplerate="$2"

    if [ "$bufsize" = "unknown" ] || [ "$samplerate" = "unknown" ]; then
        echo "unknown"
        return
    fi

    if command -v bc &> /dev/null; then
        echo "scale=1; $bufsize * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / $samplerate))"
    else
        echo "~$(($bufsize * 1000 / $samplerate))"
    fi
}

# ============================================================================
# DYNAMIC XRUN RECOMMENDATIONS
# ============================================================================

# Generate dynamic xrun recommendations based on current JACK settings
# Args: $1 = current xrun count, $2 = severity ("perfect", "mild", "severe")
get_dynamic_xrun_recommendations() {
    local current_xruns=$1
    local severity=$2

    # Get current JACK settings
    local jack_info
    jack_info=$(get_jack_settings)
    local jack_status
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    local bufsize
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    local samplerate
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    local nperiods
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    # Format current settings for display
    local settings_info=""
    if [ "$jack_status" = "✅ Active" ]; then
        settings_info="Current: ${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            settings_info="$settings_info, $nperiods periods"
        fi
    else
        settings_info="JACK not active"
    fi

    case "$severity" in
        "perfect")
            echo "   🎉 Perfect audio performance - No xruns!"
            echo "   💡 $settings_info running optimally stable"
            ;;
        "mild")
            echo "   🟡 Occasional audio problems - Still within acceptable range"
            if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ]; then
                # Dynamic recommendation based on current buffer
                if [ "$bufsize" -le 128 ]; then
                    echo "   💡 For frequent problems: Increase buffer from $bufsize to 256 samples"
                elif [ "$bufsize" -le 256 ]; then
                    echo "   💡 For frequent problems: Increase buffer from $bufsize to 512 samples"
                else
                    echo "   💡 Buffer already high ($bufsize) - check CPU load or sample rate"
                fi

                # Periods recommendation
                if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ]; then
                    echo "   💡 Consider using 3 periods instead of $nperiods for more stability"
                fi
            else
                echo "   💡 $settings_info - Start JACK for specific recommendations"
            fi
            ;;
        "severe")
            echo "   🔴 Frequent audio problems detected ($current_xruns Xruns)"
            if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ]; then
                # More aggressive recommendations for severe problems
                if [ "$bufsize" -le 64 ]; then
                    echo "   💡 Immediate action: Increase buffer from $bufsize to 256+ samples"
                elif [ "$bufsize" -le 128 ]; then
                    echo "   💡 Recommendation: Increase buffer from $bufsize to 512 samples"
                elif [ "$bufsize" -le 256 ]; then
                    echo "   💡 Increase buffer from $bufsize to 1024 samples or higher"
                else
                    echo "   💡 Buffer already very high ($bufsize) - system optimization needed"
                fi

                # Sample rate recommendation
                if [ "$samplerate" != "unknown" ] && [ "$samplerate" -gt 48000 ]; then
                    echo "   💡 Or reduce sample rate from ${samplerate}Hz to 48kHz for more stability"
                fi

                # Periods recommendation
                if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ]; then
                    echo "   💡 Important: Use 3 periods instead of $nperiods for better latency tolerance"
                fi
            else
                echo "   💡 $settings_info - Start JACK for detailed recommendations"
                echo "   💡 Generally: Higher buffer sizes (256+ samples) or lower sample rate"
            fi
            ;;
    esac
}

# ============================================================================
# BUFFER RECOMMENDATIONS
# ============================================================================

# Get recommended buffer size based on xrun count
# Args: $1 = current buffer size, $2 = xrun count
get_recommended_buffer() {
    local current_buffer="$1"
    local xrun_count="$2"

    if [ "$current_buffer" = "unknown" ]; then
        echo "256"  # Safe default
        return
    fi

    if [ "$xrun_count" -gt 20 ]; then
        # Severe problems - recommend 4x buffer or 1024 minimum
        local recommended=$((current_buffer * 4))
        [ "$recommended" -lt 1024 ] && recommended=1024
        echo "$recommended"
    elif [ "$xrun_count" -gt 5 ]; then
        # Moderate problems - recommend 2x buffer or 512 minimum
        local recommended=$((current_buffer * 2))
        [ "$recommended" -lt 512 ] && recommended=512
        echo "$recommended"
    elif [ "$xrun_count" -gt 0 ]; then
        # Minor problems - recommend 1.5x buffer or 256 minimum
        local recommended=$((current_buffer * 3 / 2))
        [ "$recommended" -lt 256 ] && recommended=256
        echo "$recommended"
    else
        # No problems - current buffer is fine
        echo "$current_buffer"
    fi
}

# ============================================================================
# JACK STATUS HELPERS
# ============================================================================

# Check if JACK is running
is_jack_running() {
    pgrep -x "jackd" > /dev/null 2>&1 || pgrep -x "jackdbus" > /dev/null 2>&1
}

# Get compact JACK info string for display
get_jack_compact_info() {
    local jack_info
    jack_info=$(get_jack_settings)
    local jack_status
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    local bufsize
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    local samplerate
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)

    if [ "$jack_status" = "✅ Active" ]; then
        echo "🎵 ${bufsize}@${samplerate}Hz"
    else
        echo "🎵 Inactive"
    fi
}
