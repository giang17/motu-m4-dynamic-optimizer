#!/bin/bash

# MOTU M4 Dynamic Optimizer - Process Module
# Handles audio process affinity and priority management
#
# ============================================================================
# MODULE API REFERENCE
# ============================================================================
#
# PUBLIC FUNCTIONS:
#
#   optimize_audio_process_affinity()
#     Pins audio processes to optimal P-Cores with RT priorities.
#     @return   : void
#     @requires : Root or CAP_SYS_NICE privileges
#     @modifies : Process CPU affinity and scheduling class
#     @calls    : _set_process_affinity, _set_process_rt_priority,
#                 _optimize_audio_applications
#
#   reset_audio_process_affinity()
#     Resets all audio processes to default scheduling.
#     @return   : void
#     @modifies : Resets CPU affinity to ALL_CPUS, scheduling to SCHED_OTHER
#
#   get_process_affinity(pid)
#     Gets CPU affinity for a process.
#     @param  pid : int - Process ID
#     @return     : string - CPU list (e.g., "0-5") or "N/A"
#     @stdout     : Affinity string
#
#   get_process_priority(pid)
#     Gets RT priority for a process.
#     @param  pid : int - Process ID
#     @return     : string - Priority value or "N/A"
#     @stdout     : Priority string
#
#   optimize_script_performance()
#     Optimizes the optimizer script itself.
#     @return   : void
#     @modifies : Script's CPU affinity, scheduling class, I/O priority
#
#   list_audio_processes()
#     Lists running audio processes with their settings.
#     @return : void
#     @stdout : Formatted list with CPU affinity and priority
#
#   get_script_performance_info()
#     Gets optimizer script's performance settings.
#     @return : string - Formatted info line
#     @stdout : "Optimizer (PID): CPUs=..., Prio=..., IO=..."
#
# PRIVATE FUNCTIONS:
#
#   _optimize_audio_applications()
#     Optimizes DAWs, synths, and plugins from AUDIO_PROCESSES list.
#     @return   : void
#     @modifies : Process CPU affinity and RT priority
#
#   _set_process_affinity(pid, cpus, name)
#     Sets CPU affinity for a process using taskset.
#     @param  pid  : int - Process ID
#     @param  cpus : string - CPU list (e.g., "0-5")
#     @param  name : string - Process name for logging
#     @exit        : 0 on success, 1 on failure
#
#   _set_process_rt_priority(pid, priority, name)
#     Sets SCHED_FIFO priority for a process using chrt.
#     @param  pid      : int - Process ID
#     @param  priority : int - Priority level 1-99
#     @param  name     : string - Process name for logging
#     @exit            : 0 on success, 1 on failure
#     @requires        : CAP_SYS_NICE or root
#
# PROCESS PRIORITY HIERARCHY:
#
#   Priority 99 : JACK server (jackd, jackdbus) on AUDIO_MAIN_CPUS
#   Priority 85 : PipeWire on AUDIO_MAIN_CPUS
#   Priority 80 : PipeWire-Pulse, WirePlumber on AUDIO_MAIN_CPUS
#   Priority 70 : DAWs, synths, plugins on DAW_CPUS
#
# EXTERNAL COMMANDS:
#
#   taskset : Sets/gets CPU affinity (util-linux)
#   chrt    : Sets/gets RT scheduling (util-linux)
#   ionice  : Sets I/O scheduling class (util-linux)
#
# DEPENDENCIES:
#   - config.sh (AUDIO_MAIN_CPUS, DAW_CPUS, BACKGROUND_CPUS, ALL_CPUS,
#                RT_PRIORITY_*, AUDIO_PROCESSES)
#   - logging.sh (log_message)
#
# ============================================================================
# PROCESS AFFINITY OPTIMIZATION
# ============================================================================
#
# CPU affinity determines which cores a process can run on.
# By pinning audio processes to specific P-Cores, we ensure:
#   - Consistent cache locality (better performance)
#   - No interference from background tasks on other cores
#   - Predictable scheduling behavior
#
# Tools used:
#   - taskset: Sets CPU affinity mask
#   - chrt: Sets real-time scheduling priority

# Set audio process affinity to optimal P-Cores
# Main entry point for process optimization. Handles different process
# types with appropriate CPU assignments and RT priorities.
#
# Priority hierarchy:
#   - JACK/PipeWire: CPUs 6-7, priority 99/85 (audio server)
#   - DAWs/synths: CPUs 0-5, priority 70 (audio applications)
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
# Iterates through AUDIO_PROCESSES list and applies optimization to each.
# Audio servers (JACK, PipeWire) are skipped as they're handled separately.
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
#
# Reset functions restore processes to default scheduling behavior,
# allowing them to run on any CPU with normal (SCHED_OTHER) priority.

# Reset audio process affinity to all CPUs
# Reverts all audio process optimizations to system defaults.
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
#
# Low-level functions for process manipulation using taskset and chrt.

# Set process CPU affinity
# Uses taskset to pin a process to specific CPUs.
#
# Args:
#   $1 - PID of the process
#   $2 - CPU list (e.g., "0-5" or "6,7")
#   $3 - Process name (for logging)
#
# Returns: 0 on success, 1 on failure
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
# Uses chrt to set SCHED_FIFO scheduling with specified priority.
# SCHED_FIFO processes preempt all normal processes and lower-priority RT tasks.
#
# Args:
#   $1 - PID of the process
#   $2 - Priority level (1-99, higher = more priority)
#   $3 - Process name (for logging)
#
# Returns: 0 on success, 1 on failure
# Note: Requires CAP_SYS_NICE or root privileges
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
#
# The optimizer script itself should not interfere with audio processing.
# We pin it to background E-Cores and set low CPU/IO priority.

# Optimize the optimizer script itself to not interfere with audio
# Ensures the monitoring loop doesn't cause audio glitches.
#
# Optimizations applied:
#   - CPU affinity: Background E-Cores (8-13)
#   - Scheduling: SCHED_OTHER with priority 0 (lowest)
#   - I/O class: idle (class 3) - only does I/O when system is idle
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
#
# Functions for displaying audio process information in status output.

# List all running audio processes with their settings
# Displays CPU affinity and priority for each audio process found.
# Output: Formatted list to stdout
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
# Returns the optimizer script's CPU affinity, priority, and I/O class.
# Used by status display to show script resource usage.
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
