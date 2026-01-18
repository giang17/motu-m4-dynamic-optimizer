#!/bin/bash

# MOTU M4 Dynamic Optimizer v4 - Hybrid Strategy (Stability-optimized)
# P-Cores on Performance, Background E-Cores on Powersave, IRQ E-Cores on Performance

LOG_FILE="/var/log/motu-m4-optimizer.log"
STATE_FILE="/var/run/motu-m4-state"

# CPU assignments for process pinning (remains unchanged)
IRQ_CPUS="14-19"        # E-Cores for IRQ handling (stable latency)
AUDIO_MAIN_CPUS="6-7"   # P-Cores for JACK/PipeWire main processes
DAW_CPUS="0-5"          # P-Cores for DAW/Plugins (maximum performance)
BACKGROUND_CPUS="8-13"  # E-Cores for audio background tasks

DEFAULT_GOVERNOR="powersave"

# Unified audio process list for all optimizations
# This central list is used by all audio optimization functions:
# - optimize_audio_process_affinity() for CPU pinning and RT priorities
# - reset_audio_process_affinity() for resetting optimizations
# - Status-Monitoring for process overview
AUDIO_PROCESSES=(
    # Audio engines and services (handled separately on AUDIO_MAIN_CPUS)
    "jackd" "pipewire" "pipewire-pulse"

    # DAWs and main audio software (DAW_CPUS + RT priority 70)
    "bitwig-studio" "reaper" "ardour" "studio" "cubase"
    "qtractor" "rosegarden" "renoise" "FL64.exe" "EZmix 3.exe"

    # Synthesizers and sound generators (DAW_CPUS + RT priority 70)
    "yoshimi" "pianoteq" "organteq" "grandorgue" "aeolus"
    "zynaddsubfx" "qsynth" "fluidsynth" "bristol" "M1.exe" "ARP 2600" "Polisix.exe" "EP-1.exe" "VOX Super Conti"
    "legacycell.exe" "wavestate nativ" "WAVESTATION.exe" "opsix_native.ex" "modwave native." "ARP ODYSSEY"
    "TRITON.exe" "TRITON_Extreme." "EZkeys 2.exe" "EZbass.exe"
    "AAS Player.exe" "Lounge Lizard S"

    # Drums and percussion (DAW_CPUS + RT priority 70)
    "hydrogen" "drumgizmo" "EZdrummer 3.exe"

    # Plugin hosts and audio tools (DAW_CPUS + RT priority 70)
    "carla" "jalv" "lv2host" "lv2rack" "jack-rack"
    "calf" "guitarix" "rakarrack" "klangfalter"

    # Audio editors (DAW_CPUS + RT priority 70)
    "musescore"
)

# Get current JACK settings
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

# Generate dynamic xrun recommendations based on current JACK settings
get_dynamic_xrun_recommendations() {
    local current_xruns=$1
    local severity=$2  # "perfect", "mild", "severe"

    # Get current JACK settings
    local jack_info=$(get_jack_settings)
    local jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    local bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    local samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    local nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    # Format current settings for display
    local settings_info=""
    if [ "$jack_status" = "✅ Active" ]; then
        settings_info="Aktuell: ${bufsize}@${samplerate}Hz"
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
                # Dynamische Empfehlung basierend to aktuellem Buffer
                if [ "$bufsize" -le 128 ]; then
                    echo "   💡 For frequent problems: Increase buffer from $bufsize to 256 samples"
                elif [ "$bufsize" -le 256 ]; then
                    echo "   💡 For frequent problems: Increase buffer from $bufsize to 512 samples"
                else
                    echo "   💡 Buffer already high ($bufsize) - check CPU load or sample rate"
                fi

                # Periods-Empfehlung
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
                # Aggressivere Empfehlungen bei schweren Problemen
                if [ "$bufsize" -le 64 ]; then
                    echo "   💡 Immediate action: Increase buffer from $bufsize to 256+ samples"
                elif [ "$bufsize" -le 128 ]; then
                    echo "   💡 Recommendation: Increase buffer from $bufsize to 512 samples"
                elif [ "$bufsize" -le 256 ]; then
                    echo "   💡 Increase buffer from $bufsize to 1024 Samples or higher"
                else
                    echo "   💡 Buffer already very high ($bufsize) - system optimization needed"
                fi

                # Samplerate-Empfehlung
                if [ "$samplerate" != "unknown" ] && [ "$samplerate" -gt 48000 ]; then
                    echo "   💡 Or reduce sample rate from ${samplerate}Hz to 48kHz reduzieren for more stability"
                fi

                # Periods-Empfehlung
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

# Logging-Funktion mit Fallback for normal users
log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"

    # Try to write to system log
    if echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message"
    else
        # Fallback for normal users
        local user_log="$HOME/.local/share/motu-m4-optimizer.log"
        mkdir -p "$(dirname "$user_log")" 2>/dev/null
        echo "$message" | tee -a "$user_log"

        # One-time warning about log location
        if [ ! -f "$HOME/.local/share/.motu-log-warning-shown" ]; then
            echo "ℹ️  Log is saved to: $user_log"
            touch "$HOME/.local/share/.motu-log-warning-shown" 2>/dev/null
        fi
    fi
}

# Check if CPUs are isolated
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

# Check if MOTU M4 is connected
check_motu_m4() {
    local motu_found=false

    # Check ALSA cards
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "M4" ]; then
                motu_found=true
                break
            fi
        fi
    done

    # Additional USB check
    if ! $motu_found; then
        if lsusb | grep -q "Mark of the Unicorn"; then
            motu_found=true
        fi
    fi

    echo $motu_found
}

# Xrun-Statistiken sammeln
get_xrun_stats() {
    local jack_xruns=0
    local pipewire_xruns=0
    local jack_messages=0
    local total_xruns=0

    # Real JACK xrun detection with jack_test (if JACK is running)
    if pgrep -x "jackd\|jackdbus" > /dev/null 2>&1; then
        # Methode 1: jack_test for real xrun statistics
        if command -v jack_test &> /dev/null; then
            # jack_test -t 5 runs 5 seconds and reports xruns
            jack_test_output=$(timeout 7 jack_test -t 5 2>&1 || echo "timeout")
            jack_xruns=$(echo "$jack_test_output" | grep -i "xrun\|late\|early" | wc -l || echo "0")

            # Fallback: Suche nach "%" Werten die Timing-Probleme anzeigen
            if [ "$jack_xruns" -eq 0 ]; then
                timing_issues=$(echo "$jack_test_output" | grep -E "[1-9][0-9]*\.[0-9]*%" | wc -l || echo "0")
                jack_xruns=$timing_issues
            fi
        fi

        # Methode 2: jack_simple_client for live test (only at 0 xruns)
        if command -v jack_simple_client &> /dev/null && [ "$jack_xruns" -eq 0 ]; then
            # Kurzer Test-Client um Xruns zu provozieren/erkennen
            jack_client_test=$(timeout 3 jack_simple_client 2>&1 | grep -i "xrun\|buffer\|late" | wc -l || echo "0")
            jack_xruns=$((jack_xruns + jack_client_test))
        fi

        # Methode 3: JACK-Logs aus journalctl der letzten 2 Minuten
        if command -v journalctl &> /dev/null; then
            jack_log_xruns=$(journalctl --since "2 minutes ago" --no-pager -q 2>/dev/null | grep -iE "(jack|qjackctl).*(xrun|underrun|delay.*exceeded|timeout|late)" | wc -l || echo "0")
            jack_xruns=$((jack_xruns + jack_log_xruns))
        fi

        # Methode 4: QJackCtl-specific xrun detection
        if pgrep -x "qjackctl" > /dev/null 2>&1; then
            qjackctl_logs=$(journalctl --since "1 minute ago" --no-pager -q 2>/dev/null | grep -i "qjackctl.*xrun.*count\|jack.*xrun.*detected" | wc -l || echo "0")
            jack_xruns=$((jack_xruns + qjackctl_logs))
        fi
    fi

    # PipeWire xrun detection via JACK tunnel logs (extended)
    if pgrep -x "pipewire" > /dev/null 2>&1; then
        # PipeWire-JACK-Tunnel Xruns (specific for your setup)
        if command -v journalctl &> /dev/null; then
            # Suche nach "mod.jack-tunnel: Xrun" Nachrichten der letzten 2 Minuten
            pipewire_xruns=$(journalctl --since "2 minutes ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun\|pipewire.*xrun\|pipewire.*drop\|pipewire.*underrun" | wc -l || echo "0")
        fi
    fi

    # Gesamtzahl berechnen
    total_xruns=$((jack_xruns + pipewire_xruns))

    echo "jack:$jack_xruns|pipewire:$pipewire_xruns|total:$total_xruns"
}

# Live JACK Xrun Counter mit besserer PipeWire-JACK-Tunnel Erkennung
get_live_jack_xruns() {
    local xrun_count=0
    local pipewire_xruns=0

    # Priorität: PipeWire-JACK-Tunnel Xruns (as these work for you)
    if pgrep -x "pipewire" > /dev/null 2>&1; then
        # PipeWire-JACK-Tunnel xruns of last 10 seconds (live detection)
        if command -v journalctl &> /dev/null; then
            pipewire_xruns=$(journalctl --since "10 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")
            xrun_count=$((xrun_count + pipewire_xruns))
        fi
    fi

    # JACK direkte Xruns (if JACK is running)
    if pgrep -x "jackd\|jackdbus" > /dev/null 2>&1; then
        # JACK server messages of last 15 seconds
        if command -v journalctl &> /dev/null; then
            jack_recent=$(journalctl --since "15 seconds ago" --no-pager -q 2>/dev/null | grep -iE "jack.*(xrun|buffer.*late|delay.*exceeded|timeout)" | wc -l || echo "0")
            xrun_count=$((xrun_count + jack_recent))
        fi

        # QJackCtl/Patchance spezifische Logs
        if pgrep -x "qjackctl" > /dev/null 2>&1; then
            qjackctl_live=$(journalctl --since "15 seconds ago" --no-pager -q 2>/dev/null | grep -iE "(qjackctl|patchance).*(xrun|late|timeout)" | wc -l || echo "0")
            xrun_count=$((xrun_count + qjackctl_live))
        fi
    fi

    echo "$xrun_count"
}

# Xrun-Monitoring über Systemlogs und JACK-Messages
get_system_xruns() {
    local recent_xruns=0
    local severe_xruns=0
    local jack_messages=0

    # Suche in den letzten 5 Minuten nach Audio-Xruns
    if command -v journalctl &> /dev/null; then
        # JACK-spezifische Nachrichten
        jack_messages=$(journalctl --since "5 minutes ago" -u "*jack*" 2>/dev/null | grep -i "xrun\|delay\|timeout" | wc -l || echo "0")

        # Allgemeine Audio-Probleme
        recent_xruns=$(journalctl --since "5 minutes ago" 2>/dev/null | grep -iE "(audio|sound).*(xrun|underrun|overrun|drop|timeout|delay)" | wc -l || echo "0")

        # Hardware-Fehler
        severe_xruns=$(journalctl --since "5 minutes ago" 2>/dev/null | grep -iE "(usb|audio).*(error|fail|disconnect|reset)" | wc -l || echo "0")
    fi

    # Dmesg for USB audio problems (with sudo fallback)
    if command -v dmesg &> /dev/null; then
        usb_audio_errors=$(dmesg 2>/dev/null | tail -100 | grep -iE "(usb|audio).*(error|xrun|underrun)" | wc -l 2>/dev/null || echo "0")
        if [ "$usb_audio_errors" = "0" ] && [ "$EUID" -eq 0 ]; then
            usb_audio_errors=$(dmesg | tail -100 | grep -iE "(usb|audio).*(error|xrun|underrun)" | wc -l 2>/dev/null || echo "0")
        fi
        severe_xruns=$((severe_xruns + usb_audio_errors))
    fi

    echo "recent:$recent_xruns|severe:$severe_xruns|jack_msg:$jack_messages"
}

# Set audio process affinity to optimal P-Cores
optimize_audio_process_affinity() {
    log_message "🎯 Set audio process affinity to optimal P-Cores..."

    # JACK-Prozesse to dedizierte P-Cores (6-7)
    for pid in $(ps -eo pid,comm | grep -E "^[[:space:]]*[0-9]+[[:space:]]+jackd" | awk '{print $1}'); do
        if command -v taskset &> /dev/null; then
            taskset -cp $AUDIO_MAIN_CPUS $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  JACK Prozess $pid to P-Cores $AUDIO_MAIN_CPUS gepinnt"
            fi
        fi

        # Highest real-time priority for JACK
        if command -v chrt &> /dev/null; then
            chrt -f -p 99 $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  JACK process $pid set to real-time priority 99"
            fi
        fi
    done

    # PipeWire-Prozesse to P-Cores
    for pid in $(ps -eo pid,comm | grep -E "pipewire$" | awk '{print $1}'); do
        if command -v taskset &> /dev/null; then
            taskset -cp $AUDIO_MAIN_CPUS $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  PipeWire Prozess $pid to P-Cores $AUDIO_MAIN_CPUS gepinnt"
            fi
        fi
        if command -v chrt &> /dev/null; then
            chrt -f -p 85 $pid 2>/dev/null
        fi
    done

    # PipeWire-Pulse to P-Cores
    for pid in $(ps -eo pid,comm | grep -E "pipewire-pulse" | awk '{print $1}'); do
        if command -v taskset &> /dev/null; then
            taskset -cp $AUDIO_MAIN_CPUS $pid 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  PipeWire-Pulse Prozess $pid to P-Cores $AUDIO_MAIN_CPUS gepinnt"
            fi
        fi
        if command -v chrt &> /dev/null; then
            chrt -f -p 80 $pid 2>/dev/null
        fi
    done

    # Vereinheitlichte Audio-Prozess-Optimierung
    # Behandelt alle DAWs, Synthesizer, Plugin-Hosts und Audio-Tools einheitlich
    # JACK/PipeWire werden separat to AUDIO_MAIN_CPUS (6-7) handled
    for audio_app in "${AUDIO_PROCESSES[@]}"; do
        # Skip JACK/PipeWire hier - die werden separat to AUDIO_MAIN_CPUS handled
        if [[ "$audio_app" =~ ^(jackd|pipewire|pipewire-pulse)$ ]]; then
            continue
        fi

        for pid in $(ps -eo pid,comm --no-headers | awk -v pattern="^$audio_app$" 'tolower($2) ~ tolower(pattern) {print $1}'); do
            # Set CPU affinity to DAW P-Cores (0-5) for maximum single-thread performance
            if command -v taskset &> /dev/null; then
                taskset -cp $DAW_CPUS $pid 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Audio-App ($audio_app) Prozess $pid to P-Cores $DAW_CPUS gepinnt"
                fi
            fi

            # RT-Priorität 70 for all audio software (lower priority than JACK)
            if command -v chrt &> /dev/null; then
                chrt -f -p 70 $pid 2>/dev/null
            fi
        done
    done
}

# Reset audio process affinity
# Verwendet die gleiche vereinheitlichte AUDIO_PROCESSES Liste wie optimize_audio_process_affinity()
reset_audio_process_affinity() {
    log_message "🔄 Reset audio process affinity..."

    # Reset all audio processes to all CPUs - Using unified list
    for process in "${AUDIO_PROCESSES[@]}"; do
        for pid in $(ps -eo pid,comm --no-headers | awk -v pattern="^$process$" 'tolower($2) ~ tolower(pattern) {print $1}'); do
            if command -v taskset &> /dev/null; then
                taskset -cp 0-19 $pid 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Process $process ($pid) reset to all CPUs (0-19)"
                fi
            fi

            # Reset priority (normal scheduling)
            if command -v chrt &> /dev/null; then
                chrt -o -p 0 $pid 2>/dev/null
            fi
        done
    done
}

# Activate audio optimizations - Hybrid Strategy (Stability-optimized)
activate_audio_optimizations() {
    log_message "🎵 MOTU M4 detected - Activating hybrid audio optimizations..."
    log_message "🏗️  Strategy: P-Cores(0-7) Performance, Background E-Cores(8-13) Powersave, IRQ E-Cores(14-19) Performance"

    # Optimize P-Cores for audio processing (0-7)
    log_message "🚀 Optimize P-Cores (0-7) for audio processing..."
    for cpu in {0..7}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  P-Core CPU $cpu: Governor set to 'performance'"
            fi
        fi

        # P-Core spezifische Optimierungen
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
            max_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" 2>/dev/null)
            if [ -n "$max_freq" ]; then
                echo $max_freq > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null
                log_message "  P-Core CPU $cpu: Min-Frequenz to Maximum gesetzt"
            fi
        fi
    done

    # Keep background E-Cores on Powersave (8-13) - Reduces interference
    log_message "🔋 Keep Background E-Cores (8-13) on Powersave for stability..."
    for cpu in {8..13}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            current_governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            if [ "$current_governor" != "$DEFAULT_GOVERNOR" ]; then
                echo "$DEFAULT_GOVERNOR" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Background E-Core CPU $cpu: Governor set to '$DEFAULT_GOVERNOR'"
                fi
            fi
        fi
    done

    # IRQ E-Cores to Performance optimieren (14-19)
    log_message "⚡ Optimize IRQ E-Cores (14-19) for stable latency..."
    for cpu in {14..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  IRQ E-Core CPU $cpu: Governor set to 'performance'"
            fi
        fi
    done

    # Set USB controller IRQs to E-Cores (keeping proven strategy)
    log_message "🎯 USB controller IRQs to E-Cores (14-19) for stable latency..."
    USB_IRQS=$(cat /proc/interrupts | grep "xhci_hcd" | awk '{print $1}' | tr -d ':')
    for IRQ in $USB_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "$IRQ_CPUS" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  USB controller IRQ $IRQ set to E-Cores $IRQ_CPUS"
            fi

            # IRQ-Optimierungen
            if [ -e "/proc/irq/$IRQ/threading" ]; then
                echo "forced" > "/proc/irq/$IRQ/threading" 2>/dev/null
            fi
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 1 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Fallback for known IRQs
    for IRQ in 156 176; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "$IRQ_CPUS" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  Fallback: IRQ $IRQ to E-Cores $IRQ_CPUS gesetzt"
            fi
        fi
    done

    # Set audio IRQs to E-Cores (for lower latency)
    log_message "🔊 Audio IRQs to E-Cores (14-19) for optimal latency..."
    AUDIO_IRQS=$(cat /proc/interrupts | grep -i "snd\|audio" | awk '{print $1}' | tr -d ':')
    for IRQ in $AUDIO_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            current_affinity=$(cat "/proc/irq/$IRQ/smp_affinity_list")
            if [ "$current_affinity" != "$IRQ_CPUS" ]; then
                echo "$IRQ_CPUS" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  Audio IRQ $IRQ to E-Cores $IRQ_CPUS gesetzt (war: $current_affinity)"
                fi
            fi

            # Audio-IRQ Balance optimieren
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 1 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Set audio process affinity to optimal P-Cores
    optimize_audio_process_affinity

    # MOTU M4 USB-Optimierungen
    optimize_motu_usb_settings

    # Kernel-Parameter optimieren
    optimize_kernel_parameters

    # Erweiterte Audio-Optimierungen
    optimize_advanced_audio_settings

    echo "optimized" > "$STATE_FILE"
    log_message "✅ Hybrid audio optimizations activated - Stability and performance optimal!"
}

# Deactivate audio optimizations - Back to standard
deactivate_audio_optimizations() {
    log_message "🔧 MOTU M4 not detected - Reset to standard configuration..."

    # Reset audio-relevant CPUs (P-Cores + IRQ E-Cores)
    log_message "🔋 Reset audio-relevant CPUs to standard governor..."
    for cpu in {0..7} {14..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            current_governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            if [ "$current_governor" = "performance" ]; then
                echo "$DEFAULT_GOVERNOR" > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_message "  CPU $cpu: Governor reset to '$DEFAULT_GOVERNOR'"
                fi
            fi
        fi

        # Reset min frequency
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
            min_freq=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_min_freq" 2>/dev/null)
            if [ -n "$min_freq" ]; then
                echo $min_freq > "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" 2>/dev/null
            fi
        fi
    done

    # Reset process affinity
    reset_audio_process_affinity

    # USB-Controller IRQs to alle CPUs verteilen
    USB_IRQS=$(cat /proc/interrupts | grep "xhci_hcd" | awk '{print $1}' | tr -d ':')
    for IRQ in $USB_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "0-19" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  USB controller IRQ $IRQ reset to all CPUs (0-19)"
            fi

            # IRQ-Balance wieder aktivieren
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 0 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Audio-IRQs to alle CPUs verteilen
    AUDIO_IRQS=$(cat /proc/interrupts | grep -i "snd\|audio" | awk '{print $1}' | tr -d ':')
    for IRQ in $AUDIO_IRQS; do
        if [ -e "/proc/irq/$IRQ/smp_affinity_list" ]; then
            echo "0-19" > "/proc/irq/$IRQ/smp_affinity_list" 2>/dev/null
            if [ $? -eq 0 ]; then
                log_message "  Audio IRQ $IRQ reset to all CPUs (0-19)"
            fi

            # IRQ-Balance wieder aktivieren
            if [ -e "/proc/irq/$IRQ/balance_disabled" ]; then
                echo 0 > "/proc/irq/$IRQ/balance_disabled" 2>/dev/null
            fi
        fi
    done

    # Reset kernel parameters
    reset_kernel_parameters

    echo "standard" > "$STATE_FILE"
    log_message "✅ Hybrid optimizations deactivated, system reset to standard"
}

# MOTU M4 USB-Optimierungen
optimize_motu_usb_settings() {
    log_message "🔌 Optimiere MOTU M4 USB-Einstellungen..."

    for usb_device in /sys/bus/usb/devices/*; do
        if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
            VENDOR=$(cat "$usb_device/idVendor" 2>/dev/null)
            PRODUCT=$(cat "$usb_device/idProduct" 2>/dev/null)

            if [ "$VENDOR" = "07fd" ] && [ "$PRODUCT" = "000b" ]; then
                log_message "  MOTU M4 USB-Optimierungen: $usb_device"

                if [ -e "$usb_device/power/control" ]; then
                    echo "on" > "$usb_device/power/control"
                    log_message "    Power-Management: always on"
                fi

                if [ -e "$usb_device/power/autosuspend" ]; then
                    echo -1 > "$usb_device/power/autosuspend"
                    log_message "    Autosuspend: deaktiviert"
                fi

                if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
                    echo -1 > "$usb_device/power/autosuspend_delay_ms"
                    log_message "    Autosuspend-Delay: deaktiviert"
                fi

                # USB-Bulk-Transfer-Optimierungen
                if [ -e "$usb_device/urbnum" ]; then
                    echo 32 > "$usb_device/urbnum" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        log_message "    URB count increased to 32"
                    else
                        log_message "    URB optimization: No permission (normal)"
                    fi
                fi
            fi
        fi
    done
}

# Kernel-Parameter optimieren
optimize_kernel_parameters() {
    log_message "⚙️  Optimize kernel parameters for audio..."

    # Real-Time Scheduling
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        echo -1 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        log_message "  RT-Runtime: Unlimited"
    fi

    # Memory Management
    if [ -e /proc/sys/vm/swappiness ]; then
        echo 10 > /proc/sys/vm/swappiness 2>/dev/null
        log_message "  Swappiness: 10"
    fi

    # Audio-spezifische Optimierungen
    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        echo 1000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
        log_message "  Scheduler latency: 1ms"
    fi

    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo 100000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
        log_message "  Min granularity: 0.1ms"
    fi
}

# Reset kernel parameters
reset_kernel_parameters() {
    log_message "⚙️  Reset kernel parameters..."

    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        echo 950000 > /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null
        log_message "  RT-Runtime: Standard (950ms)"
    fi

    if [ -e /proc/sys/vm/swappiness ]; then
        echo 60 > /proc/sys/vm/swappiness 2>/dev/null
        log_message "  Swappiness: Standard (60)"
    fi

    if [ -e /proc/sys/kernel/sched_latency_ns ]; then
        echo 6000000 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
        log_message "  Scheduler latency: Standard (6ms)"
    fi

    if [ -e /proc/sys/kernel/sched_min_granularity_ns ]; then
        echo 750000 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
        log_message "  Min granularity: Standard (0.75ms)"
    fi
}

# Erweiterte Audio-Optimierungen
optimize_advanced_audio_settings() {
    log_message "🎼 Activating advanced audio optimizations..."

    # USB-Bulk-Transfer-Optimierungen
    if [ -e /sys/module/usbcore/parameters/usbfs_memory_mb ]; then
        echo 256 > /sys/module/usbcore/parameters/usbfs_memory_mb 2>/dev/null
        log_message "  USB-Memory-Buffer: 256MB"
    fi

    # Audio-Subsystem-Optimierungen
    if [ -e /proc/sys/dev/hpet/max-user-freq ]; then
        echo 2048 > /proc/sys/dev/hpet/max-user-freq 2>/dev/null
        log_message "  HPET-Frequenz: 2048Hz"
    fi

    # Network-Interface-Interrupts von Audio-CPUs weglenken
    for netif in /sys/class/net/*/queues/rx-*/rps_cpus; do
        if [ -e "$netif" ]; then
            # Restrict network RPS to E-Cores 8-13
            echo "00003f00" > "$netif" 2>/dev/null
        fi
    done
    log_message "  Netzwerk-Interrupts to Background-E-Cores umgeleitet"
}

# Script-Performance optimieren
optimize_script_performance() {
    local script_pid=$$

    # Script to Background E-Cores pinnen (8-13)
    if command -v taskset &> /dev/null; then
        taskset -cp $BACKGROUND_CPUS $script_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "📌 Script selbst to Background E-Cores $BACKGROUND_CPUS gepinnt"
        fi
    fi

    # Low priority for the script
    if command -v chrt &> /dev/null; then
        chrt -o -p 0 $script_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "⬇️  Script priority set to low"
        fi
    fi

    # Reduce I/O priority
    if command -v ionice &> /dev/null; then
        ionice -c 3 -p $script_pid 2>/dev/null
        if [ $? -eq 0 ]; then
            log_message "💽 Script I/O priority set to idle"
        fi
    fi
}

# Detailed monitoring function (extended information)
show_detailed_status() {
    echo "=== MOTU M4 Detailed Monitoring ==="
    echo ""

    # Alle MOTU M4 relevanten Informationen
    echo "🎛️  MOTU M4 hardware status:"
    MOTU_CARD=""
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "M4" ]; then
                MOTU_CARD=$(basename "$card")
                echo "   Karte: $(cat /proc/asound/$MOTU_CARD/id 2>/dev/null)"
                echo "   Stream-Status: $(cat /proc/asound/$MOTU_CARD/stream0 2>/dev/null)"
                if [ -e "/proc/asound/$MOTU_CARD/usbmixer" ]; then
                    echo "   USB-Mixer: $(head -1 /proc/asound/$MOTU_CARD/usbmixer 2>/dev/null)"
                fi
                break
            fi
        fi
    done

    echo ""
    echo "🔌 USB-Verbindungsdetails:"
    MOTU_USB=$(lsusb | grep "Mark of the Unicorn")
    if [ -n "$MOTU_USB" ]; then
        echo "   $MOTU_USB"
        USB_BUS=$(echo "$MOTU_USB" | awk '{print $2}')
        USB_DEVICE=$(echo "$MOTU_USB" | awk '{print $4}' | tr -d ':')
        echo "   Bus: $USB_BUS, Device: $USB_DEVICE"

        # USB Power Management Details
        for usb_device in /sys/bus/usb/devices/*; do
            if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
                VENDOR=$(cat "$usb_device/idVendor" 2>/dev/null)
                PRODUCT=$(cat "$usb_device/idProduct" 2>/dev/null)
                if [ "$VENDOR" = "07fd" ] && [ "$PRODUCT" = "000b" ]; then
                    echo "   Power Control: $(cat "$usb_device/power/control" 2>/dev/null || echo "N/A")"
                    echo "   Autosuspend Delay: $(cat "$usb_device/power/autosuspend_delay_ms" 2>/dev/null || echo "N/A") ms"
                    echo "   USB Speed: $(cat "$usb_device/speed" 2>/dev/null || echo "N/A")"
                    echo "   USB Version: $(cat "$usb_device/version" 2>/dev/null || echo "N/A")"
                    echo "   Max Power: $(cat "$usb_device/bMaxPower" 2>/dev/null || echo "N/A")"
                    break
                fi
            fi
        done
    else
        echo "   MOTU M4 USB device not found!"
    fi

    echo ""
    echo "⚡ Complete IRQ analysis:"
    echo "   USB controller IRQs:"
    cat /proc/interrupts | grep "xhci_hcd" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            threading=$(cat /proc/irq/$irq/threading 2>/dev/null || echo "standard")
            balance=$(cat /proc/irq/$irq/balance_disabled 2>/dev/null || echo "0")
            balance_text="enabled"; [ "$balance" = "1" ] && balance_text="disabled"
            spurious=$(cat /proc/irq/$irq/spurious 2>/dev/null || echo "N/A")
            echo "     IRQ $irq: CPUs=$affinity, Threading=$threading, Balance=$balance_text"
            echo "       $line"
            echo "       Spurious: $spurious"
        fi
    done

    echo ""
    echo "   Audio-spezifische IRQs:"
    cat /proc/interrupts | grep -i "snd\|audio" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            echo "     Audio IRQ $irq: CPUs=$affinity"
            echo "       $line"
        fi
    done

    echo ""
    echo "🎵 Audio process details with RT priorities:"
    AUDIO_RT_PROCS=$(ps -eo pid,class,rtprio,ni,comm,cmd | grep -E "FF|RR" | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]")
    if [ -n "$AUDIO_RT_PROCS" ]; then
        echo "   RT audio processes found:"
        echo "$AUDIO_RT_PROCS" | while read line; do
            echo "     $line"
        done
    else
        echo "   No audio processes with RT priority found"
        echo ""
        echo "   Standard Audio-Prozesse (ohne RT):"
        ps -eo pid,class,rtprio,ni,comm,cmd | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]" | grep -v "grep" | head -5 | while read line; do
            echo "     $line"
        done
    fi

    echo ""
    echo "🖥️  CPU-Details pro Kern:"
    for cpu in {0..19}; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            freq_cur=""
            freq_min=""
            freq_max=""
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq_cur=" @ $(($freq_khz / 1000))MHz"
            fi
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_min_freq")
                freq_min=" (min: $(($freq_khz / 1000))MHz"
            fi
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_max_freq")
                freq_max=", max: $(($freq_khz / 1000))MHz)"
            fi

            cpu_type="E-Core"
            role="Background"
            if [ $cpu -le 7 ]; then
                cpu_type="P-Core"
                if [ $cpu -le 5 ]; then
                    role="DAW/Plugins"
                else
                    role="JACK/PipeWire"
                fi
            elif [ $cpu -ge 14 ] && [ $cpu -le 19 ]; then
                role="IRQ-Handling"
            fi

            echo "     CPU $cpu ($cpu_type - $role): $governor$freq_cur$freq_min$freq_max"
        fi
    done

    echo ""
    echo "⚙️  Advanced kernel parameters:"
    echo "   RT-Scheduling:"
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us)
        if [ "$rt_runtime" = "-1" ]; then
            echo "     RT-Runtime: Unbegrenzt ✓"
        else
            echo "     RT-Runtime: $rt_runtime µs"
        fi
    fi
    if [ -e /proc/sys/kernel/sched_rt_period_us ]; then
        rt_period=$(cat /proc/sys/kernel/sched_rt_period_us)
        echo "     RT-Period: $rt_period µs"
    fi

    echo "   Memory Management:"
    if [ -e /proc/sys/vm/swappiness ]; then
        swappiness=$(cat /proc/sys/vm/swappiness)
        echo "     Swappiness: $swappiness"
    fi
    if [ -e /proc/sys/vm/dirty_ratio ]; then
        dirty_ratio=$(cat /proc/sys/vm/dirty_ratio)
        echo "     Dirty Ratio: $dirty_ratio%"
    fi

    echo ""
    echo "📊 Optimierungs-Erfolgsbilanz:"
    USB_IRQS_OPTIMIZED=0
    USB_IRQS_TOTAL=0
    while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            USB_IRQS_TOTAL=$((USB_IRQS_TOTAL + 1))
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            if [ "$affinity" = "14-19" ]; then
                USB_IRQS_OPTIMIZED=$((USB_IRQS_OPTIMIZED + 1))
            fi
        fi
    done < <(cat /proc/interrupts | grep "xhci_hcd")

    RT_AUDIO_PROCS_COUNT=$(ps -eo pid,class,rtprio,comm,cmd | grep -E "FF|RR" | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]" | wc -l)

    echo "   ✅ USB controller IRQs on CPUs 14-19: $USB_IRQS_OPTIMIZED/$USB_IRQS_TOTAL"
    echo "   ✅ Audio processes with RT priority: $RT_AUDIO_PROCS_COUNT"
    if [ -n "$MOTU_CARD" ]; then
        echo "   ✅ MOTU M4 hardware: Detected as $MOTU_CARD"
    else
        echo "   ❌ MOTU M4 hardware: Not detected"
    fi

    echo ""
    echo "🏁 Recommended next steps:"
    if [ $USB_IRQS_OPTIMIZED -eq 0 ]; then
        echo "   🔧 Run 'sudo $0 once' to activate IRQ optimizations"
    fi
    if [ $RT_AUDIO_PROCS_COUNT -eq 0 ]; then
        echo "   🎵 Start audio software for automatic RT priority assignment"
    fi
    if [ -z "$MOTU_CARD" ]; then
        echo "   🔌 Check the MOTU M4 USB connection"
    fi

    echo ""
    echo "🎵 Detailed audio xrun statistics:"

    # Xrun-Statistiken sammeln
    xrun_stats=$(get_xrun_stats)
    system_xruns=$(get_system_xruns)
    live_jack_xruns=$(get_live_jack_xruns)

    # Parse Xrun-Daten
    jack_xruns=$(echo "$xrun_stats" | cut -d'|' -f1 | cut -d':' -f2)
    pipewire_xruns=$(echo "$xrun_stats" | cut -d'|' -f2 | cut -d':' -f2)
    total_xruns=$(echo "$xrun_stats" | cut -d'|' -f3 | cut -d':' -f2)

    recent_xruns=$(echo "$system_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    severe_xruns=$(echo "$system_xruns" | cut -d'|' -f2 | cut -d':' -f2)
    jack_messages=$(echo "$system_xruns" | cut -d'|' -f3 | cut -d':' -f2)

    # Status-Icon basierend to Xruns
    xrun_icon="✅"
    if [ "$total_xruns" -gt 0 ] || [ "$recent_xruns" -gt 0 ] || [ "$live_jack_xruns" -gt 0 ]; then
        xrun_icon="⚠️"
    fi
    if [ "$severe_xruns" -gt 0 ]; then
        xrun_icon="❌"
    fi

    echo "   $xrun_icon JACK Xruns (1min): $jack_xruns"
    echo "   $xrun_icon PipeWire Xruns (1min): $pipewire_xruns"
    echo "   $xrun_icon Live JACK Status: $live_jack_xruns"
    echo "   $xrun_icon JACK Messages (5min): $jack_messages"
    echo "   $xrun_icon System Audio-Probleme (5min): $recent_xruns"
    if [ "$severe_xruns" -gt 0 ]; then
        echo "   ❌ Hardware-Fehler (5min): $severe_xruns"
    fi

    # Dynamische Xrun-Bewertung und Empfehlungen
    total_current_xruns=$((jack_xruns + pipewire_xruns + live_jack_xruns))
    if [ "$total_current_xruns" -eq 0 ] && [ "$recent_xruns" -eq 0 ]; then
        get_dynamic_xrun_recommendations "$total_current_xruns" "perfect"
    elif [ "$total_current_xruns" -lt 5 ] && [ "$severe_xruns" -eq 0 ]; then
        get_dynamic_xrun_recommendations "$total_current_xruns" "mild"
    else
        get_dynamic_xrun_recommendations "$total_current_xruns" "severe"
    fi
    if [ $USB_IRQS_OPTIMIZED -lt $USB_IRQS_TOTAL ] || [ $AUDIO_IRQS_OPTIMIZED -lt $AUDIO_IRQS_TOTAL ]; then
        echo "   ⚡ Run 'sudo $0 once' aus, um alle to activate IRQ optimizations"
    fi

    # Zusätzliche Empfehlungen bei anhaltenden Problemen
    detailed_xruns=$(get_system_xruns)
    recent_count=$(echo "$detailed_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    if [ "$recent_count" -gt 3 ]; then
        echo ""
        echo "   🎛️ Zusätzliche Empfehlungen bei anhaltenden Audio-Problemen:"
        get_dynamic_xrun_recommendations "$recent_count" "severe"
    fi
}

# Erweiterte Status-Anzeige
show_status() {
    echo "=== MOTU M4 Dynamic Optimizer v4 Status ==="
    echo ""

    motu_connected=$(check_motu_m4)
    current_state="unknown"

    if [ -e "$STATE_FILE" ]; then
        current_state=$(cat "$STATE_FILE")
    fi

    echo "🎛️  MOTU M4 detected: $motu_connected"
    echo "🔄 Aktueller Zustand: $current_state"

    # Aktuelle JACK-Settings anzeigen
    jack_info=$(get_jack_settings)
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
    echo ""

    # Detailed MOTU M4 information
    echo "🎵 MOTU M4 Details:"
    MOTU_CARD=""
    for card in /proc/asound/card*; do
        if [ -e "$card/id" ]; then
            card_id=$(cat "$card/id" 2>/dev/null)
            if [ "$card_id" = "M4" ]; then
                MOTU_CARD=$(basename "$card")
                echo "   Karte: $(cat /proc/asound/$MOTU_CARD/id 2>/dev/null)"
                if [ -e "/proc/asound/$MOTU_CARD/stream0" ]; then
                    echo "   Verbindung: $(cat /proc/asound/$MOTU_CARD/stream0 2>/dev/null)"
                fi
                if [ -e "/proc/asound/$MOTU_CARD/usbmixer" ]; then
                    echo "   USB-Details: $(head -1 /proc/asound/$MOTU_CARD/usbmixer 2>/dev/null)"
                fi
                break
            fi
        fi
    done

    if [ -z "$MOTU_CARD" ]; then
        echo "   MOTU M4 card not found in ALSA"
    fi

    # USB-Gerät Status
    MOTU_USB=$(lsusb | grep "Mark of the Unicorn")
    if [ -n "$MOTU_USB" ]; then
        echo "   USB-Gerät: $MOTU_USB"
        USB_BUS=$(echo "$MOTU_USB" | awk '{print $2}')
        echo "   USB Bus: $USB_BUS"
    else
        echo "   MOTU M4 not found in USB devices"
    fi
    echo ""

    # CPU-Isolation prüfen
    isolation_info=$(check_cpu_isolation)
    echo "🔒 CPU-Isolation: $isolation_info"
    echo ""

    echo "🖥️  CPU Governor Status (Hybrid Strategy):"
    if [ "$current_state" = "optimized" ]; then
        echo "   🚀 P-Cores: Performance | 🔋 Background E-Cores: Powersave | ⚡ IRQ E-Cores: Performance"
    else
        echo "   🔋 STANDARD: All CPUs on $DEFAULT_GOVERNOR governor"
    fi
    echo ""

    echo "   P-Cores (DAW/Plugins: 0-5, JACK/PipeWire: 6-7):"
    for cpu in 0 1 2 3 4 5 6 7; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            freq=""
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq=" @ $(($freq_khz / 1000))MHz"
            fi
            echo "     CPU $cpu: $governor$freq"
        fi
    done

    echo "   E-Cores (Background: 8-13, IRQ-Handling: 14-19):"
    for cpu in 8 9 10 11 12 13 14 15 16 17 18 19; do
        if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor" ]; then
            governor=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor")
            freq=""
            if [ -e "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq" ]; then
                freq_khz=$(cat "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq")
                freq=" @ $(($freq_khz / 1000))MHz"
            fi
            usage=""
            if [ $cpu -ge 14 ] && [ $cpu -le 19 ]; then
                usage=" [IRQ]"
            elif [ $cpu -ge 8 ] && [ $cpu -le 13 ]; then
                usage=" [BG]"
            fi
            echo "     CPU $cpu: $governor$freq$usage"
        fi
    done

    echo ""
    echo "⚡ USB controller IRQ assignments:"
    USB_IRQS_OPTIMIZED=0
    USB_IRQS_TOTAL=0
    cat /proc/interrupts | grep "xhci_hcd" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            threading=$(cat /proc/irq/$irq/threading 2>/dev/null || echo "standard")
            balance=$(cat /proc/irq/$irq/balance_disabled 2>/dev/null || echo "0")
            balance_text="enabled"; [ "$balance" = "1" ] && balance_text="disabled"

            status_icon="✅"
            if [ "$affinity" != "$IRQ_CPUS" ]; then
                status_icon="⚠️"
            fi
            echo "   $status_icon IRQ $irq: CPUs $affinity, Threading: $threading, Balance: $balance_text"
        fi
    done

    echo ""
    echo "🔊 Audio-IRQs:"
    cat /proc/interrupts | grep -i "snd" | while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            balance=$(cat /proc/irq/$irq/balance_disabled 2>/dev/null || echo "0")
            balance_text="enabled"; [ "$balance" = "1" ] && balance_text="disabled"

            status_icon="✅"
            if [ "$affinity" != "$IRQ_CPUS" ]; then
                status_icon="⚠️"
            fi
            echo "   $status_icon Audio IRQ $irq: CPUs $affinity, Balance: $balance_text"
        fi
    done

    echo ""
    echo "🎵 Active audio processes:"

    # Erstelle Liste aller ltoenden Audio-Prozesse - Verwendet die vereinheitlichte AUDIO_PROCESSES Liste
    local audio_pattern=""
    for process in "${AUDIO_PROCESSES[@]}"; do
        if [ -z "$audio_pattern" ]; then
            audio_pattern="$process"
        else
            audio_pattern="$audio_pattern|$process"
        fi
    done
    audio_processes=$(ps -eo pid,comm --no-headers | awk -v pattern="^($audio_pattern)$" 'tolower($2) ~ tolower(pattern) {print $1, $2}' | sort -k2)

    if [ -n "$audio_processes" ]; then
        echo "$audio_processes" | while read pid process_name; do
            if [ -n "$pid" ] && [ -n "$process_name" ]; then
                affinity="N/A"
                priority="N/A"
                if command -v taskset &> /dev/null; then
                    affinity=$(taskset -cp $pid 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "N/A")
                fi
                if command -v chrt &> /dev/null; then
                    priority=$(chrt -p $pid 2>/dev/null | awk '{print $NF}' || echo "N/A")
                fi
                echo "   $process_name ($pid): CPUs=$affinity, Prio=$priority"
            fi
        done
    else
        echo "   No audio processes found"
    fi

    echo ""
    echo "🔧 Script-Performance:"
    script_pid=$$
    script_affinity="N/A"
    script_priority="N/A"
    script_ionice="N/A"
    if command -v taskset &> /dev/null; then
        script_affinity=$(taskset -cp $script_pid 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "N/A")
    fi
    if command -v chrt &> /dev/null; then
        script_priority=$(chrt -p $script_pid 2>/dev/null | awk '{print $NF}' || echo "N/A")
    fi
    if command -v ionice &> /dev/null; then
        script_ionice=$(ionice -p $script_pid 2>/dev/null || echo "N/A")
    fi
    echo "   Optimizer ($script_pid): CPUs=$script_affinity, Prio=$script_priority, IO=$script_ionice"

    echo ""
    echo "🔋 MOTU M4 USB Power Management:"
    for usb_device in /sys/bus/usb/devices/*; do
        if [ -e "$usb_device/idVendor" ] && [ -e "$usb_device/idProduct" ]; then
            VENDOR=$(cat "$usb_device/idVendor" 2>/dev/null)
            PRODUCT=$(cat "$usb_device/idProduct" 2>/dev/null)

            if [ "$VENDOR" = "07fd" ] && [ "$PRODUCT" = "000b" ]; then
                echo "   USB-Gerät: $usb_device"
                if [ -e "$usb_device/power/control" ]; then
                    control=$(cat "$usb_device/power/control")
                    echo "   Power Control: $control"
                fi
                if [ -e "$usb_device/power/autosuspend_delay_ms" ]; then
                    delay=$(cat "$usb_device/power/autosuspend_delay_ms")
                    echo "   Autosuspend Delay: $delay ms"
                fi
                if [ -e "$usb_device/speed" ]; then
                    speed=$(cat "$usb_device/speed")
                    echo "   USB Speed: $speed"
                fi
                break
            fi
        fi
    done

    echo ""
    echo "⚙️  Kernel parameter status:"
    if [ -e /proc/sys/kernel/sched_rt_runtime_us ]; then
        rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us)
        if [ "$rt_runtime" = "-1" ]; then
            echo "   RT-Scheduling-Limit: Unbegrenzt ✓"
        else
            echo "   RT-Scheduling-Limit: $rt_runtime µs"
        fi
    fi
    if [ -e /proc/sys/vm/swappiness ]; then
        swappiness=$(cat /proc/sys/vm/swappiness)
        echo "   Swappiness: $swappiness"
    fi

    echo ""
    echo "📊 Optimierungs-Zusammenfassung:"

    # USB IRQ Optimierung prüfen
    USB_IRQS_OPTIMIZED=0
    USB_IRQS_TOTAL=0
    while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            USB_IRQS_TOTAL=$((USB_IRQS_TOTAL + 1))
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            if [ "$affinity" = "$IRQ_CPUS" ]; then
                USB_IRQS_OPTIMIZED=$((USB_IRQS_OPTIMIZED + 1))
            fi
        fi
    done < <(cat /proc/interrupts | grep "xhci_hcd")

    # Audio IRQ Optimierung prüfen
    AUDIO_IRQS_OPTIMIZED=0
    AUDIO_IRQS_TOTAL=0
    while read line; do
        irq=$(echo $line | awk '{print $1}' | tr -d ':')
        if [ -e "/proc/irq/$irq/smp_affinity_list" ]; then
            AUDIO_IRQS_TOTAL=$((AUDIO_IRQS_TOTAL + 1))
            affinity=$(cat /proc/irq/$irq/smp_affinity_list)
            if [ "$affinity" = "$IRQ_CPUS" ]; then
                AUDIO_IRQS_OPTIMIZED=$((AUDIO_IRQS_OPTIMIZED + 1))
            fi
        fi
    done < <(cat /proc/interrupts | grep -i "snd")

    RT_AUDIO_PROCS=$(ps -eo pid,class,rtprio,comm,cmd | grep -E "FF|RR" | grep -iE "pulse|pipe|jack|audio|pianoteq|organteq|reaper|ardour|bitwig|cubase|logic|ableton|fl_studio|studio|daw|yoshimi|grandorgue|renoise|carla|jalv|qtractor|rosegarden|musescore|zynaddsubfx|qsynth|fluidsynth|bristol|hydrogen|drumgizmo|guitarix|rakarrack" | grep -v "\[.*\]" | wc -l)

    echo "   USB controller IRQs optimized: $USB_IRQS_OPTIMIZED/$USB_IRQS_TOTAL"
    echo "   Audio IRQs optimized: $AUDIO_IRQS_OPTIMIZED/$AUDIO_IRQS_TOTAL"
    echo "   Audio processes with RT priority: $RT_AUDIO_PROCS"

    # Vollständige Xrun-Status für konsistente Bewertung (wie in detaillierter Ansicht)
    xrun_stats=$(get_xrun_stats)
    system_xruns=$(get_system_xruns)
    live_jack_xruns=$(get_live_jack_xruns)

    # Parse alle Xrun-Daten
    jack_xruns=$(echo "$xrun_stats" | cut -d'|' -f1 | cut -d':' -f2)
    pipewire_xruns=$(echo "$xrun_stats" | cut -d'|' -f2 | cut -d':' -f2)
    recent_xruns=$(echo "$system_xruns" | cut -d'|' -f1 | cut -d':' -f2)
    severe_xruns=$(echo "$system_xruns" | cut -d'|' -f2 | cut -d':' -f2)

    # Gesamte aktuelle Xruns berechnen (wie in detaillierter Ansicht)
    total_current_xruns=$((jack_xruns + pipewire_xruns + live_jack_xruns))

    # JACK-Settings in kompakter Status-Anzeige
    jack_info=$(get_jack_settings)
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "   🎵 JACK: $jack_status"
    if [ "$jack_status" = "✅ Active" ]; then
        settings_text="${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            settings_text="$settings_text, $nperiods periods"
        fi
        echo "       $settings_text"
    fi

    # Audio-Performance mit konsistenter Bewertung (identisch zur detaillierten Ansicht)
    if [ "$total_current_xruns" -eq 0 ] && [ "$recent_xruns" -eq 0 ]; then
        echo "   ✅ Audio performance: No problems"
        if [ "$jack_status" = "✅ Active" ]; then
            echo "       $settings_text running optimally stable"
        fi
    elif [ "$total_current_xruns" -lt 5 ] && [ "$severe_xruns" -eq 0 ]; then
        echo "   🟡 Audio-Performance: Gelegentliche Probleme ($total_current_xruns Xruns)"
        if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ]; then
            if [ "$bufsize" -le 128 ]; then
                echo "       💡 For frequent problems: Increase buffer from $bufsize to 256 samples"
            elif [ "$bufsize" -le 256 ]; then
                echo "       💡 For frequent problems: Increase buffer from $bufsize to 512 samples"
            fi
        fi
    else
        echo "   🔴 Audio-Performance: Häufige Probleme ($total_current_xruns Xruns)"
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
                echo "       💡 Or reduce sample rate from ${samplerate}Hz to 48kHz reduzieren"
            fi
        fi
    fi

    if [ "$severe_xruns" -gt 0 ]; then
        echo "   ❌ Zusätzlich: Hardware-Fehler ($severe_xruns in 5min)"
    fi

    echo ""
    echo "💡 Dynamische Buffer-Empfehlungen basierend to aktuellen Settings:"
    if [ "$jack_status" = "✅ Active" ] && [ "$bufsize" != "unknown" ] && [ "$samplerate" != "unknown" ]; then
        # Berechne aktuelle Latenz mit Fallback
        if command -v bc &> /dev/null; then
            latency_ms=$(echo "scale=1; $bufsize * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / $samplerate))")
        else
            latency_ms="~$(($bufsize * 1000 / $samplerate))"
        fi

        echo "   🎯 Aktuell: $bufsize Samples @ ${samplerate}Hz = ${latency_ms}ms"

        # Dynamische Empfehlungen basierend to Xrun-Situation
        if [ "$total_current_xruns" -gt 20 ]; then
            # Aggressive Empfehlungen bei vielen Xruns
            if [ "$bufsize" -le 256 ]; then
                safe_buffer=1024
                if command -v bc &> /dev/null; then
                    safe_latency=$(echo "scale=1; $safe_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($safe_buffer * 1000 / $samplerate))")
                else
                    safe_latency="~$(($safe_buffer * 1000 / $samplerate))"
                fi
                echo "   🔴 Problems detected: $safe_buffer Samples = ${safe_latency}ms recommended"
            else
                echo "   🔴 Buffer already high - prüfen Sie System-Performance"
            fi
        elif [ "$total_current_xruns" -gt 5 ]; then
            # Moderate Empfehlungen bei einigen Xruns
            if [ "$bufsize" -le 128 ]; then
                safe_buffer=512
                if command -v bc &> /dev/null; then
                    safe_latency=$(echo "scale=1; $safe_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($safe_buffer * 1000 / $samplerate))")
                else
                    safe_latency="~$(($safe_buffer * 1000 / $samplerate))"
                fi
                echo "   🟡 Stabilität: $safe_buffer Samples = ${safe_latency}ms recommended"
            fi
        else
            # Standard-Empfehlungen bei wenigen/keinen Xruns
            if [ "$bufsize" -le 64 ]; then
                next_buffer=128
                if command -v bc &> /dev/null; then
                    next_latency=$(echo "scale=1; $next_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($next_buffer * 1000 / $samplerate))")
                else
                    next_latency="~$(($next_buffer * 1000 / $samplerate))"
                fi
                echo "   🟡 Stabiler: $next_buffer Samples = ${next_latency}ms"
            elif [ "$bufsize" -le 128 ]; then
                safe_buffer=256
                if command -v bc &> /dev/null; then
                    safe_latency=$(echo "scale=1; $safe_buffer * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($safe_buffer * 1000 / $samplerate))")
                else
                    safe_latency="~$(($safe_buffer * 1000 / $samplerate))"
                fi
                echo "   🟢 Stabiler: $safe_buffer Samples = ${safe_latency}ms"
            else
                echo "   ✅ Buffer already in stable range"
            fi
        fi

        # Samplerate-Alternativen wenn nötig
        if [ "$samplerate" -gt 48000 ] && [ "$total_current_xruns" -gt 10 ]; then
            if command -v bc &> /dev/null; then
                alt_latency=$(echo "scale=1; $bufsize * 1000 / 48000" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / 48000))")
            else
                alt_latency="~$(($bufsize * 1000 / 48000))"
            fi
            echo "   🔄 Alternative: $bufsize@48kHz = ${alt_latency}ms (more stable)"
        fi

        # Periods-Empfehlung bei Problemen
        if [ "$nperiods" != "unknown" ] && [ "$nperiods" -eq 2 ] && [ "$total_current_xruns" -gt 5 ]; then
            echo "   🔧 Important: Use 3 periods instead of $nperiods für bessere Latenz-Toleranz"
        fi
    else
        echo "   🟢 Stabil (256): Sehr stabil, niedrige Latenz (~5.3ms @ 48kHz)"
        echo "   🟡 Optimal (128): Gute Latenz, moderate CPU-Last (~2.7ms @ 48kHz)"
        echo "   🟠 Aggressiv (64): Niedrige Latenz, hohe CPU-Last (~1.3ms @ 48kHz)"
        echo "   🔴 Extrem (32): Nur für Tests (~0.7ms @ 48kHz)"
    fi
    echo ""
    echo "🎯 v4 Hybrid: Stability through optimized CPU assignment, performance where needed!"
}

# Hauptfunktion
main_monitoring_loop() {
    log_message "🚀 MOTU M4 Dynamic Optimizer v4 gestartet"
    log_message "🏗️  Hybrid Strategy: P-Cores Performance, Background E-Cores Powersave, IRQ E-Cores Performance"
    log_message "📊 System: Ubuntu 24.04, $(nproc) CPU-Kerne"
    log_message "🎯 Process pinning:"
    log_message "   P-Cores DAW/Plugins: $DAW_CPUS"
    log_message "   P-Cores JACK/PipeWire: $AUDIO_MAIN_CPUS"
    log_message "   E-Cores IRQ-Handling: $IRQ_CPUS"
    log_message "   E-Cores Background: $BACKGROUND_CPUS"
    log_message "🎵 Xrun monitoring: Activated"

    # Script-Performance optimieren
    optimize_script_performance

    # Initiale CPU-Isolation-Prüfung
    check_cpu_isolation

    current_state="unknown"
    check_counter=0
    xrun_check_counter=0
    xrun_warning_threshold=10
    last_xrun_count=0

    while true; do
        motu_connected=$(check_motu_m4)

        if [ "$motu_connected" = "true" ]; then
            if [ "$current_state" != "optimized" ]; then
                activate_audio_optimizations
                current_state="optimized"
                check_counter=0
            else
                # Check process affinity only every 30 seconds (performance optimization)
                check_counter=$((check_counter + 1))
                if [ $check_counter -ge 6 ]; then
                    optimize_audio_process_affinity
                    check_counter=0
                fi
            fi

            # Xrun monitoring every 10 seconds (2 cycles)
            xrun_check_counter=$((xrun_check_counter + 1))
            if [ $xrun_check_counter -ge 2 ]; then
                # Check xruns of last 30 seconds
                if command -v journalctl &> /dev/null; then
                    current_xruns=$(journalctl --since "30 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")

                    if [ "$current_xruns" -gt "$xrun_warning_threshold" ]; then
                        log_message "⚠️ Xrun-Warnung: $current_xruns Xruns in 30s (Grenze: $xrun_warning_threshold)"
                        log_message "💡 Empfehlung: Buffer-Größe erhöhen oder CPU-Last reduzieren"
                    elif [ "$current_xruns" -gt 0 ] && [ "$current_xruns" -ne "$last_xrun_count" ]; then
                        log_message "🎵 Xrun-Monitor: $current_xruns Xruns in letzten 30s"
                    fi

                    last_xrun_count=$current_xruns
                fi
                xrun_check_counter=0
            fi
        else
            if [ "$current_state" != "standard" ]; then
                deactivate_audio_optimizations
                current_state="standard"
            fi
        fi

        sleep 5
    done
}

# Live Xrun-Monitoring mit verbesserter PipeWire-JACK-Tunnel Erkennung
live_xrun_monitoring() {
    echo "=== MOTU M4 Live Xrun-Monitor ==="
    echo "⚡ Monitors JACK/PipeWire xruns in real-time"
    echo "📊 Session gestartet: $(date '+%H:%M:%S')"

    # Zeige aktuelle JACK-Settings zu Beginn der Session
    jack_info=$(get_jack_settings)
    jack_status=$(echo "$jack_info" | cut -d'|' -f1)
    bufsize=$(echo "$jack_info" | cut -d'|' -f2)
    samplerate=$(echo "$jack_info" | cut -d'|' -f3)
    nperiods=$(echo "$jack_info" | cut -d'|' -f4)

    echo "🎵 JACK Status: $jack_status"
    if [ "$jack_status" = "✅ Active" ]; then
        settings_text="${bufsize}@${samplerate}Hz"
        if [ "$nperiods" != "unknown" ]; then
            settings_text="$settings_text, $nperiods periods"
        fi
        if command -v bc &> /dev/null; then
            latency_ms=$(echo "scale=1; $bufsize * 1000 / $samplerate" | bc -l 2>/dev/null || echo "~$(($bufsize * 1000 / $samplerate))")
        else
            latency_ms="~$(($bufsize * 1000 / $samplerate))"
        fi
        echo "   Settings: $settings_text (${latency_ms}ms Latenz)"

        # Warnung bei aggressiven Settings
        if [ "$bufsize" -le 64 ]; then
            echo "   ⚠️ Sehr aggressive Buffer-Größe - Xruns wahrscheinlich"
        elif [ "$bufsize" -le 128 ]; then
            echo "   🟡 Moderate Buffer-Größe - Bei Xruns to 256+ erhöhen"
        fi
    fi
    echo "🛑 Drücken Sie Ctrl+C zum Beenden"
    echo ""

    # Initialer Xrun-Zähler vom aktuellen Log-Stand
    initial_xruns=0
    if command -v journalctl &> /dev/null; then
        initial_xruns=$(journalctl --since "1 minute ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")
    fi

    xrun_total=0
    xrun_session_start=$(date +%s)
    max_xruns_per_interval=0
    last_log_line=""

    # Xrun-Rate-Tracking für letzte 30 Sekunden
    xrun_timestamps=()

    while true; do
        # Aktuelle Xruns aus Logs seit Session-Start
        current_total_xruns=0
        new_xruns_this_interval=0

        if command -v journalctl &> /dev/null; then
            # Alle Xruns seit Session-Start
            session_start_time=$(date -d "@$xrun_session_start" '+%Y-%m-%d %H:%M:%S')
            current_total_xruns=$(journalctl --since "$session_start_time" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")

            # New xruns of last 5 seconds
            new_xruns_this_interval=$(journalctl --since "5 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | wc -l || echo "0")
        fi

        # Session-Xruns berechnen (minus initiale)
        xrun_total=$((current_total_xruns - initial_xruns))
        if [ "$xrun_total" -lt 0 ]; then
            xrun_total=0
        fi

        # Tracking für neue Xruns
        current_timestamp=$(date +%s)
        if [ "$new_xruns_this_interval" -gt 0 ]; then
            xrun_timestamps+=($current_timestamp)
        fi

        # Remove old timestamps (older than 30 seconds)
        cutoff_time=$((current_timestamp - 30))
        new_timestamps=()
        for ts in "${xrun_timestamps[@]}"; do
            if [ "$ts" -gt "$cutoff_time" ]; then
                new_timestamps+=($ts)
            fi
        done
        xrun_timestamps=("${new_timestamps[@]}")

        # Xrun rate in last 30 seconds
        xrun_rate_30s=${#xrun_timestamps[@]}

        # Max xruns per interval tracking
        if [ "$new_xruns_this_interval" -gt "$max_xruns_per_interval" ]; then
            max_xruns_per_interval=$new_xruns_this_interval
        fi

        # Audio-Prozess-Info
        audio_processes=$(ps -eo pid,comm --no-headers | grep -E "jackd|pipewire|yoshimi|pianoteq|qjackctl" | wc -l)

        # MOTU M4 Status
        motu_status="❌ Not detected"
        if [ "$(check_motu_m4)" = "true" ]; then
            motu_status="✅ Verbunden"
        fi

        # Session-Zeit
        session_duration=$((current_timestamp - xrun_session_start))
        session_minutes=$((session_duration / 60))
        session_seconds=$((session_duration % 60))

        # Status-Icon basierend to aktuellen Xruns
        status_icon="✅"
        if [ "$new_xruns_this_interval" -gt 0 ]; then
            status_icon="⚠️"
        fi
        if [ "$new_xruns_this_interval" -gt 2 ]; then
            status_icon="❌"
        fi

        # Live display with JACK settings (compact)
        current_display_time=$(date '+%H:%M:%S')

        # Compact JACK info for live display
        jack_compact=""
        current_jack_info=$(get_jack_settings)
        current_jack_status=$(echo "$current_jack_info" | cut -d'|' -f1)
        if [ "$current_jack_status" = "✅ Active" ]; then
            current_bufsize=$(echo "$current_jack_info" | cut -d'|' -f2)
            current_samplerate=$(echo "$current_jack_info" | cut -d'|' -f3)
            jack_compact=" | 🎵 ${current_bufsize}@${current_samplerate}Hz"
        else
            jack_compact=" | 🎵 Inaktiv"
        fi

        printf "\r[%s] %s MOTU M4: %s | 🎯 Audio: %d%s | ⚠️ Session: %d | 🔥 30s: %d | 📈 Max: %d | ⏱️ %02d:%02d" \
               "$current_display_time" "$status_icon" "$motu_status" "$audio_processes" "$jack_compact" "$xrun_total" "$xrun_rate_30s" "$max_xruns_per_interval" "$session_minutes" "$session_seconds"

        # On new xruns: New line with details and recommendations
        if [ "$new_xruns_this_interval" -gt 0 ]; then
            echo ""
            # Zeige die neueste Xrun-Meldung
            latest_xrun=$(journalctl --since "5 seconds ago" --no-pager -q 2>/dev/null | grep -i "mod\.jack-tunnel.*xrun" | tail -1)
            echo "🚨 [$current_display_time] New xruns: $new_xruns_this_interval"
            if [ -n "$latest_xrun" ]; then
                xrun_details=$(echo "$latest_xrun" | cut -d' ' -f5-)
                echo "📋 Details: $xrun_details"
            fi

            # Dynamische Empfehlung bei Xruns
            if [ "$current_jack_status" = "✅ Active" ]; then
                current_bufsize=$(echo "$current_jack_info" | cut -d'|' -f2)
                current_samplerate=$(echo "$current_jack_info" | cut -d'|' -f3)
                current_nperiods=$(echo "$current_jack_info" | cut -d'|' -f4)

                if [ "$current_bufsize" != "unknown" ]; then
                    if [ "$current_bufsize" -le 64 ]; then
                        echo "💡 Recommendation: Increase buffer from $current_bufsize to 128+ samples"
                    elif [ "$current_bufsize" -le 128 ] && [ "$xrun_rate_30s" -gt 5 ]; then
                        echo "💡 Recommendation: Increase buffer from $current_bufsize to 256 samples"
                    elif [ "$current_nperiods" != "unknown" ] && [ "$current_nperiods" -eq 2 ] && [ "$xrun_rate_30s" -gt 3 ]; then
                        echo "💡 Tipp: 3 periods statt $current_nperiods für bessere Latenz-Toleranz"
                    fi
                fi
            fi
        fi

        sleep 2
    done
}

# Hauptmenü
case "${1:-monitor}" in
    "monitor"|"daemon")
        main_monitoring_loop
        ;;
    "live-xruns"|"xrun-monitor")
        live_xrun_monitoring
        ;;
    "once"|"run")
        motu_connected=$(check_motu_m4)
        if [ "$motu_connected" = "true" ]; then
            log_message "🎵 Einmalige Aktivierung der Hybrid Audio-Optimierungen"
            activate_audio_optimizations
        else
            log_message "🔧 MOTU M4 not detected - Deactivating optimizations"
            deactivate_audio_optimizations
        fi
        ;;
    "once-delayed")
        motu_connected=$(check_motu_m4)
        if [ "$motu_connected" = "true" ]; then
            log_message "🎵 Delayed system service: Waiting for user session audio processes"

            # Intelligent wait time for user audio services
            AUDIO_WAIT=0
            MAX_AUDIO_WAIT=45
            FOUND_USER_AUDIO=false

            while [ $AUDIO_WAIT -lt $MAX_AUDIO_WAIT ]; do
                # Prüfe to User-Audio-Prozesse (nicht nur System-Audio)
                USER_PIPEWIRE=$(pgrep -f "pipewire" | wc -l)
                USER_JACK=$(pgrep -f "jackdbus" | wc -l)

                if [ "$USER_PIPEWIRE" -ge 2 ] || [ "$USER_JACK" -ge 1 ]; then
                    log_message "🎯 User audio services detected after ${AUDIO_WAIT}s (PipeWire: $USER_PIPEWIRE, JACK: $USER_JACK)"
                    FOUND_USER_AUDIO=true
                    break
                fi

                sleep 2
                AUDIO_WAIT=$((AUDIO_WAIT + 2))

                # Progress log every 10 seconds
                if [ $((AUDIO_WAIT % 10)) -eq 0 ]; then
                    log_message "⏳ Waiting for user audio services... ${AUDIO_WAIT}/${MAX_AUDIO_WAIT}s (PipeWire: $USER_PIPEWIRE, JACK: $USER_JACK)"
                fi
            done

            if [ "$FOUND_USER_AUDIO" = "true" ]; then
                # Additional 3 seconds for service initialization
                sleep 3
                log_message "🎵 Starte verzögerte Audio-Optimierung für User-Session-Prozesse"
                activate_audio_optimizations
            else
                log_message "⚠️  Timeout: No user audio services after ${MAX_AUDIO_WAIT}s detected, starting standard optimization"
                activate_audio_optimizations
            fi
        else
            log_message "🔧 MOTU M4 not detected - Deactivating optimizations"
            deactivate_audio_optimizations
        fi
        ;;
    "status")
        show_status
        ;;
    "detailed"|"detail"|"monitor-detail")
        show_detailed_status
        ;;
    "stop"|"reset")
        log_message "🛑 Manueller Reset angefordert"
        deactivate_audio_optimizations
        ;;
    *)
        echo "MOTU M4 Dynamic Optimizer v4 - Hybrid Strategy (Stability-optimized)"
        echo ""
        echo "Usage: $0 [monitor|once|status|detailed|live-xruns|stop]"
        echo ""
        echo "Kommandos:"
        echo "  monitor     - Continuous monitoring (default)"
        echo "  once        - Einmalige Optimierung"
        echo "  status      - Standard status display"
        echo "  detailed    - Detailed hardware monitoring"
        echo "  live-xruns  - Live xrun monitoring (real-time)"
        echo "  stop        - Optimierungen deaktivieren"
        echo ""
        echo "CPU-Strategie v4 (Hybrid für Stabilität):"
        echo "  P-Cores 0-7:        Performance (Audio-Processing)"
        echo "  E-Cores 8-13:       Powersave (Background, weniger Störungen)"
        echo "  E-Cores 14-19:      Performance (IRQ-Handling)"
        echo ""
        echo "Process pinning remains optimal:"
        echo "  P-Cores 0-5: DAW/Plugins (maximum single-thread performance)"
        echo "  P-Cores 6-7: JACK/PipeWire (dedizierte Audio-Engine)"
        echo "  E-Cores 8-13: Background-Tasks"
        echo "  E-Cores 14-19: IRQ handling (stable latency)"
        echo ""
        echo "🎯 v4 Vorteil: Optimale Balance aus Performance und Stabilität!"
        exit 1
        ;;
esac
