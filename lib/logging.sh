#!/bin/bash

# MOTU M4 Dynamic Optimizer - Logging Module
# Provides logging functionality with fallback for non-root users

# Logging function with fallback for normal users
# Writes timestamped messages to log file and stdout.
#
# Behavior:
#   - As root: Writes to system log ($LOG_FILE = /var/log/motu-m4-optimizer.log)
#   - As user: Falls back to ~/.local/share/motu-m4-optimizer.log
#   - With MOTU_QUIET_LOG=1: Only outputs to stdout, no file logging
#
# Args:
#   $1 - Message to log
#
# Example:
#   log_message "Starting optimization..."
log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"

    # Try to write to system log (suppress errors completely)
    if [ -w "$LOG_FILE" ] 2>/dev/null && echo "$message" >> "$LOG_FILE" 2>/dev/null; then
        echo "$message"
    else
        # Fallback for normal users - silent mode for status commands
        if [ "${MOTU_QUIET_LOG:-0}" = "1" ]; then
            # Just output to stdout without logging
            echo "$message"
        else
            local user_log="$HOME/.local/share/motu-m4-optimizer.log"
            mkdir -p "$(dirname "$user_log")" 2>/dev/null
            echo "$message" | tee -a "$user_log" 2>/dev/null

            # One-time warning about log location
            if [ ! -f "$HOME/.local/share/.motu-log-warning-shown" ] 2>/dev/null; then
                echo "ℹ️  Log is saved to: $user_log" >&2
                touch "$HOME/.local/share/.motu-log-warning-shown" 2>/dev/null
            fi
        fi
    fi
}

# Silent log - only logs if we have permission, otherwise discards
# Use this for debug/verbose messages that shouldn't clutter stdout.
#
# Behavior:
#   - Writes to system log only if writable (running as root)
#   - Silently discards message if no write permission
#   - Never outputs to stdout
#
# Args:
#   $1 - Message to log
#
# Example:
#   log_silent "Debug: CPU isolation check completed"
log_silent() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"

    if [ -w "$LOG_FILE" ] 2>/dev/null; then
        echo "$message" >> "$LOG_FILE" 2>/dev/null
    fi
}
