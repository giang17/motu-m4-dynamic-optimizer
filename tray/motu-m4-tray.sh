#!/bin/bash

# MOTU M4 Dynamic Optimizer - System Tray Application
# Provides a system tray icon for status display and quick actions
#
# Usage:
#   motu-m4-tray         - Start the tray icon
#   motu-m4-tray --help  - Show help
#
# Requirements:
#   - yad (Yet Another Dialog) package
#   - Running desktop environment with system tray support
#
# The tray icon reads status from /var/run/motu-m4-tray-state
# which is written by the main optimizer service.

set -u

# ============================================================================
# CONFIGURATION
# ============================================================================

TRAY_NAME="MOTU M4 Optimizer"
STATE_FILE="${TRAY_STATE_FILE:-/var/run/motu-m4-tray-state}"
ICON_DIR="${TRAY_ICON_DIR:-/usr/share/icons/motu-m4}"
UPDATE_INTERVAL="${TRAY_UPDATE_INTERVAL:-5}"
OPTIMIZER_CMD="motu-m4-dynamic-optimizer"

# FIFO for yad communication
FIFO_DIR="/tmp"
FIFO_NAME="motu-m4-tray-$(id -u)"
FIFO_PATH="${FIFO_DIR}/${FIFO_NAME}"

# Icons
ICON_OPTIMIZED="${ICON_DIR}/motu-optimized.svg"
ICON_CONNECTED="${ICON_DIR}/motu-connected.svg"
ICON_WARNING="${ICON_DIR}/motu-warning.svg"
ICON_DISCONNECTED="${ICON_DIR}/motu-disconnected.svg"

# PID tracking
YAD_PID=""
MONITOR_PID=""

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

show_help() {
    cat << EOF
$TRAY_NAME - System Tray Application

Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h      Show this help message
  --version, -v   Show version information

Description:
  Displays a system tray icon showing the current status of the
  MOTU M4 Dynamic Optimizer. Right-click the icon for quick actions.

Menu Options:
  - Status anzeigen     : Show detailed status in terminal
  - Live Xrun-Monitor   : Open live xrun monitoring
  - Optimierung starten : Activate audio optimizations
  - Optimierung stoppen : Deactivate optimizations
  - Beenden             : Close the tray icon

Requirements:
  - yad package (Yet Another Dialog)
  - Desktop environment with system tray support

Configuration:
  The tray reads status from: $STATE_FILE
  Icons are loaded from: $ICON_DIR

EOF
}

show_version() {
    echo "$TRAY_NAME - Tray Application v1.0"
}

check_dependencies() {
    if ! command -v yad &> /dev/null; then
        echo "Error: yad is not installed."
        echo "Install it with: sudo apt install yad"
        exit 1
    fi
}

# Get current icon based on state file
get_current_icon() {
    local state="disconnected"

    if [ -f "$STATE_FILE" ]; then
        state=$(grep "^state=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    fi

    case "$state" in
        optimized)
            echo "$ICON_OPTIMIZED"
            ;;
        connected)
            echo "$ICON_CONNECTED"
            ;;
        warning)
            echo "$ICON_WARNING"
            ;;
        disconnected|*)
            echo "$ICON_DISCONNECTED"
            ;;
    esac
}

# Get tooltip text based on state file
# Returns a single-line tooltip (yad doesn't support multi-line tooltips well)
get_tooltip() {
    local state="disconnected"
    local jack="inactive"
    local jack_settings="unknown"
    local xruns="0"

    if [ -f "$STATE_FILE" ]; then
        state=$(grep "^state=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
        jack=$(grep "^jack=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
        jack_settings=$(grep "^jack_settings=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
        xruns=$(grep "^xruns_30s=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
    fi

    local tooltip="$TRAY_NAME"

    case "$state" in
        optimized)
            tooltip+=" | Optimiert"
            ;;
        connected)
            tooltip+=" | Verbunden"
            ;;
        warning)
            tooltip+=" | Warnung!"
            ;;
        disconnected|*)
            tooltip+=" | Getrennt"
            ;;
    esac

    if [ "$jack" = "active" ] && [ "$jack_settings" != "unknown" ]; then
        tooltip+=" | JACK: $jack_settings"
    fi

    if [ "$xruns" != "0" ] && [ -n "$xruns" ]; then
        tooltip+=" | Xruns: $xruns"
    fi

    echo "$tooltip"
}

# ============================================================================
# MENU ACTIONS
# ============================================================================
# Note: These functions are exported and called by yad via menu commands.
# ShellCheck SC2317 warnings about unreachable code can be ignored.

# shellcheck disable=SC2317
action_status() {
    # Open terminal with status display
    if command -v x-terminal-emulator &> /dev/null; then
        x-terminal-emulator -e bash -c "$OPTIMIZER_CMD status; echo ''; echo 'Druecke Enter zum Schliessen...'; read" &
    elif command -v gnome-terminal &> /dev/null; then
        gnome-terminal -- bash -c "$OPTIMIZER_CMD status; echo ''; echo 'Druecke Enter zum Schliessen...'; read" &
    elif command -v xterm &> /dev/null; then
        xterm -e "$OPTIMIZER_CMD status; echo ''; echo 'Druecke Enter zum Schliessen...'; read" &
    else
        notify-send "$TRAY_NAME" "Kein Terminal gefunden" 2>/dev/null
    fi
}

# shellcheck disable=SC2317
action_live_monitor() {
    # Open terminal with live xrun monitoring
    if command -v x-terminal-emulator &> /dev/null; then
        x-terminal-emulator -e bash -c "$OPTIMIZER_CMD live-xruns" &
    elif command -v gnome-terminal &> /dev/null; then
        gnome-terminal -- bash -c "$OPTIMIZER_CMD live-xruns" &
    elif command -v xterm &> /dev/null; then
        xterm -e "$OPTIMIZER_CMD live-xruns" &
    else
        notify-send "$TRAY_NAME" "Kein Terminal gefunden" 2>/dev/null
    fi
}

# shellcheck disable=SC2317
action_start_optimization() {
    # Start optimization (requires root)
    if command -v pkexec &> /dev/null; then
        pkexec "$OPTIMIZER_CMD" once
        notify-send -i "$ICON_OPTIMIZED" "$TRAY_NAME" "Optimierung gestartet" 2>/dev/null
    else
        notify-send -i "dialog-error" "$TRAY_NAME" "pkexec nicht verfuegbar" 2>/dev/null
    fi
}

# shellcheck disable=SC2317
action_stop_optimization() {
    # Stop optimization (requires root)
    if command -v pkexec &> /dev/null; then
        pkexec "$OPTIMIZER_CMD" stop
        notify-send -i "$ICON_DISCONNECTED" "$TRAY_NAME" "Optimierung gestoppt" 2>/dev/null
    else
        notify-send -i "dialog-error" "$TRAY_NAME" "pkexec nicht verfuegbar" 2>/dev/null
    fi
}

# ============================================================================
# TRAY MANAGEMENT
# ============================================================================

cleanup() {
    # Clean up on exit
    [ -n "$YAD_PID" ] && kill "$YAD_PID" 2>/dev/null
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null
    [ -p "$FIFO_PATH" ] && rm -f "$FIFO_PATH"
    exit 0
}

# Monitor state file and update tray
state_monitor() {
    local last_state=""
    local last_xruns="0"

    while true; do
        if [ -f "$STATE_FILE" ]; then
            local current_state
            local current_xruns
            current_state=$(grep "^state=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)
            current_xruns=$(grep "^xruns_30s=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2)

            # Update icon if state changed
            if [ "$current_state" != "$last_state" ]; then
                local new_icon
                new_icon=$(get_current_icon)
                echo "icon:$new_icon" > "$FIFO_PATH" 2>/dev/null

                # Update tooltip
                local tooltip
                tooltip=$(get_tooltip)
                echo "tooltip:$tooltip" > "$FIFO_PATH" 2>/dev/null

                last_state="$current_state"
            fi

            # Check for xrun increase
            if [ "$current_xruns" != "$last_xruns" ] && [ "$current_xruns" -gt 0 ] 2>/dev/null; then
                if [ "$current_xruns" -gt "${last_xruns:-0}" ]; then
                    # Show warning icon temporarily
                    echo "icon:$ICON_WARNING" > "$FIFO_PATH" 2>/dev/null
                    sleep 2
                    # Restore normal icon
                    local restore_icon
                    restore_icon=$(get_current_icon)
                    echo "icon:$restore_icon" > "$FIFO_PATH" 2>/dev/null
                fi
                last_xruns="$current_xruns"
            fi
        fi

        sleep "$UPDATE_INTERVAL"
    done
}

start_tray() {
    # Set up signal handlers
    trap cleanup EXIT INT TERM

    # Create FIFO for communication
    rm -f "$FIFO_PATH"
    mkfifo "$FIFO_PATH"

    # Get initial icon
    local initial_icon
    initial_icon=$(get_current_icon)

    # Build menu with direct shell commands
    # Format: "Label!command|Label2!command2|..."
    # Note: yad executes these as shell commands, so we use full paths and inline commands
    local menu="Status anzeigen!x-terminal-emulator -e bash -c '${OPTIMIZER_CMD} status; echo; read -p \"Druecke Enter...\"'"
    menu+="|Live Xrun-Monitor!x-terminal-emulator -e ${OPTIMIZER_CMD} live-xruns"
    menu+="|---"
    menu+="|Optimierung starten!pkexec ${OPTIMIZER_CMD} once"
    menu+="|Optimierung stoppen!pkexec ${OPTIMIZER_CMD} stop"
    menu+="|---"
    menu+="|Beenden!quit"

    # Start state monitor in background
    state_monitor &
    MONITOR_PID=$!

    # Start yad notification icon
    # The tail -f keeps the FIFO open for writing
    exec 3<> "$FIFO_PATH"

    yad --notification \
        --image="$initial_icon" \
        --text="$TRAY_NAME" \
        --menu="$menu" \
        --command="action_status" \
        --listen <&3 &

    YAD_PID=$!

    # Send initial tooltip
    local tooltip
    tooltip=$(get_tooltip)
    echo "tooltip:$tooltip" > "$FIFO_PATH"

    # Wait for yad to exit
    wait $YAD_PID

    cleanup
}

# ============================================================================
# MAIN
# ============================================================================

case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --version|-v)
        show_version
        exit 0
        ;;
    "")
        check_dependencies
        start_tray
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
