#!/bin/bash

# MOTU M4 Dynamic Optimizer - Logging Module
# Provides logging functionality with fallback for non-root users

# Logging function with fallback for normal users
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
