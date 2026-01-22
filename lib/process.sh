#!/bin/bash

# MOTU M4 Dynamic Optimizer - Process Module
# Handles audio process affinity and priority management

# ============================================================================
# PROCESS AFFINITY OPTIMIZATION
# ============================================================================

# Set audio process affinity to optimal P-Cores
optimize_audio_process_affinity() {
    log_message "🎯 Set audio process affinity to optimal P-Cores..."

    # JACK processes to dedicated P-Cores (6-7)
    for pid in $(pgrep -x "jackd" 2>/dev/null); do
        _set_process_affinity "$pid" "$AUDIO_MAIN_CPUS" "JACK"
        _set_process_rt_priority "$pid" "$RT_PRIORITY_JACK" "JACK"
    done

    for pid in $(pgrep -x "jackdbus" 2>/dev/null); do
        _set_process_affinity "$pid" "$AUDIO_MAIN_CPUS" "JACK DBus"
        _set_process_rt_priority "$pid" "$RT_PRIORITY_JACK" "JACK DBus"
    done

    # PipeWire processes to P-Cores
    for pid in $(pgrep -x "pipewire" 2>/dev/null); do
        _set_process_affinity "$pid" "$AUDIO_MAIN_CPUS" "PipeWire"
        _set_process_rt_priority "$pid" "$RT_PRIORITY_PIPEWIRE" "PipeWire"
    done

    # PipeWire-Pulse to P-Cores
    for pid in $(pgrep -x "pipewire-pulse" 2>/dev/null); do
        _set_process_affinity "$pid" "$AUDIO_MAIN_CPUS" "PipeWire-Pulse"
        _set_process_rt_priority "$pid" "$RT_PRIORITY_PULSE" "PipeWire-Pulse"
    done

    # WirePlumber to P-Cores
    for pid in $(pgrep -x "wireplumber" 2>/dev/null); do
        _set_process_affinity "$pid" "$AUDIO_MAIN_CPUS" "WirePlumber"
        _set_process_rt_priority "$pid" "$RT_PRIORITY_PULSE" "WirePlumber"
    done

    # Optimize all audio applications from the unified list
    _optimize_audio_applications
}

# Optimize audio applications (DAWs, synths, plugins)
_optimize_audio_applications() {
    for audio_app in "${AUDIO_PROCESSES[@]}"; do
        # Skip JACK/PipeWire - they are handled separately on AUDIO_MAIN_CPUS
        case "$audio_app" in
            jackd|jackdbus|pipewire|pipewire-pulse|wireplumber)
                continue
                ;;
        esac

        # Find processes matching the audio app name (case-insensitive)
        for pid in $(pgrep -i -x "$audio_app" 2>/dev/null); do
            # Set CPU affinity to DAW P-Cores (0-5) for maximum single-thread performance
            _set_process_affinity "$pid" "$DAW_CPUS" "$audio_app"
            # RT priority 70 for all audio software (lower than JACK)
            _set_process_rt_priority "$pid" "$RT_PRIORITY_AUDIO" "$audio_app"
        done
    done
}

# ============================================================================
# PROCESS AFFINITY RESET
# ============================================================================

# Reset audio process affinity to all CPUs
reset_audio_process_affinity() {
    log_message "🔄 Reset audio process affinity..."

    # Reset all audio processes to all CPUs using unified list
    for process in "${AUDIO_PROCESSES[@]}"; do
        for pid in $(pgrep -i -x "$process" 2>/dev/null); do
            # Reset to all CPUs
            if command -v taskset &> /dev/null; then
                taskset -cp "$ALL_CPUS" "$pid" 2>/dev/null
                result=$?
                if [ $result -eq 0 ]; then
                    log_message "  Process $process ($pid) reset to all CPUs ($ALL_CPUS)"
                fi
            fi

            # Reset to normal scheduling (SCHED_OTHER)
            if command -v chrt &> /dev/null; then
                chrt -o -p 0 "$pid" 2>/dev/null
            fi
        done
    done
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Set process CPU affinity
# Args: $1 = PID, $2 = CPU list, $3 = process name (for logging)
_set_process_affinity() {
    local pid="$1"
    local cpus="$2"
    local name="$3"

    if ! command -v taskset &> /dev/null; then
        return 1
    fi

    if taskset -cp "$cpus" "$pid" 2>/dev/null; then
        log_message "  $name process $pid pinned to P-Cores $cpus"
        return 0
    fi

    return 1
}

# Set process real-time priority
# Args: $1 = PID, $2 = priority, $3 = process name (for logging)
_set_process_rt_priority() {
    local pid="$1"
    local priority="$2"
    local name="$3"

    if ! command -v chrt &> /dev/null; then
        return 1
    fi

    if chrt -f -p "$priority" "$pid" 2>/dev/null; then
        log_message "  $name process $pid set to real-time priority $priority"
        return 0
    fi

    return 1
}

# Get process affinity
# Args: $1 = PID
# Returns: CPU affinity string or "N/A"
get_process_affinity() {
    local pid="$1"

    if command -v taskset &> /dev/null; then
        taskset -cp "$pid" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "N/A"
    else
        echo "N/A"
    fi
}

# Get process priority
# Args: $1 = PID
# Returns: priority string or "N/A"
get_process_priority() {
    local pid="$1"

    if command -v chrt &> /dev/null; then
        chrt -p "$pid" 2>/dev/null | awk '{print $NF}' || echo "N/A"
    else
        echo "N/A"
    fi
}

# ============================================================================
# SCRIPT SELF-OPTIMIZATION
# ============================================================================

# Optimize the optimizer script itself to not interfere with audio
optimize_script_performance() {
    local script_pid=$$

    # Pin script to Background E-Cores (8-13)
    if command -v taskset &> /dev/null; then
        if taskset -cp "$BACKGROUND_CPUS" "$script_pid" 2>/dev/null; then
            log_message "📌 Script itself pinned to Background E-Cores $BACKGROUND_CPUS"
        fi
    fi

    # Set low priority for the script
    if command -v chrt &> /dev/null; then
        if chrt -o -p 0 "$script_pid" 2>/dev/null; then
            log_message "⬇️  Script priority set to low"
        fi
    fi

    # Reduce I/O priority
    if command -v ionice &> /dev/null; then
        if ionice -c 3 -p "$script_pid" 2>/dev/null; then
            log_message "💽 Script I/O priority set to idle"
        fi
    fi
}

# ============================================================================
# PROCESS LISTING
# ============================================================================

# List all running audio processes with their settings
list_audio_processes() {
    local output=""

    # Build pattern from AUDIO_PROCESSES array
    local audio_pattern=""
    for process in "${AUDIO_PROCESSES[@]}"; do
        if [ -z "$audio_pattern" ]; then
            audio_pattern="$process"
        else
            audio_pattern="$audio_pattern|$process"
        fi
    done

    # Find matching processes
    local audio_procs
    audio_procs=$(ps -eo pid,comm --no-headers 2>/dev/null | \
        awk -v pattern="^($audio_pattern)$" 'tolower($2) ~ tolower(pattern) {print $1, $2}' | \
        sort -k2)

    if [ -n "$audio_procs" ]; then
        echo "$audio_procs" | while read -r pid process_name; do
            if [ -n "$pid" ] && [ -n "$process_name" ]; then
                local affinity priority
                affinity=$(get_process_affinity "$pid")
                priority=$(get_process_priority "$pid")
                echo "   $process_name ($pid): CPUs=$affinity, Prio=$priority"
            fi
        done
    else
        echo "   No audio processes found"
    fi
}

# Get script's own performance info
get_script_performance_info() {
    local script_pid=$$
    local affinity priority ionice_info

    affinity=$(get_process_affinity "$script_pid")
    priority=$(get_process_priority "$script_pid")

    if command -v ionice &> /dev/null; then
        ionice_info=$(ionice -p "$script_pid" 2>/dev/null || echo "N/A")
    else
        ionice_info="N/A"
    fi

    echo "   Optimizer ($script_pid): CPUs=$affinity, Prio=$priority, IO=$ionice_info"
}
