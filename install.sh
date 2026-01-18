#!/bin/bash

# MOTU M4 Dynamic Optimizer - Installer
# Handles installation, uninstallation, and updates
#
# Usage:
#   ./install.sh install    - Install the optimizer
#   ./install.sh uninstall  - Remove the optimizer
#   ./install.sh update     - Update existing installation
#   ./install.sh status     - Check installation status

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_NAME="motu-m4-dynamic-optimizer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Installation paths
INSTALL_BIN="/usr/local/bin"
INSTALL_LIB="/usr/local/lib/${SCRIPT_NAME}"
SYSTEMD_DIR="/etc/systemd/system"
UDEV_DIR="/etc/udev/rules.d"
LOG_FILE="/var/log/motu-m4-optimizer.log"

# Source files
MAIN_SCRIPT="${SCRIPT_DIR}/motu-m4-dynamic-optimizer.sh"
LIB_DIR="${SCRIPT_DIR}/lib"
SERVICE_FILE="${SCRIPT_DIR}/motu-m4-dynamic-optimizer.service"
DELAYED_SERVICE_FILE="${SCRIPT_DIR}/motu-m4-dynamic-optimizer-delayed.service"
UDEV_RULES="${SCRIPT_DIR}/99-motu-m4-audio-optimizer.rules"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  MOTU M4 Dynamic Optimizer - Installer${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_step() {
    echo -e "${BLUE}➤ $1${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (sudo)"
        echo "   Please run: sudo $0 $1"
        exit 1
    fi
}

check_source_files() {
    local missing=0

    print_step "Checking source files..."

    if [ ! -f "$MAIN_SCRIPT" ]; then
        print_error "Main script not found: $MAIN_SCRIPT"
        missing=1
    fi

    if [ ! -d "$LIB_DIR" ]; then
        print_error "Library directory not found: $LIB_DIR"
        missing=1
    else
        # Check for required modules
        local required_modules=(
            "config.sh" "logging.sh" "checks.sh" "jack.sh" "xrun.sh"
            "process.sh" "usb.sh" "kernel.sh" "optimization.sh"
            "status.sh" "monitor.sh"
        )
        for module in "${required_modules[@]}"; do
            if [ ! -f "${LIB_DIR}/${module}" ]; then
                print_error "Required module not found: lib/${module}"
                missing=1
            fi
        done
    fi

    if [ ! -f "$SERVICE_FILE" ]; then
        print_warning "Service file not found: $SERVICE_FILE (optional)"
    fi

    if [ ! -f "$UDEV_RULES" ]; then
        print_warning "Udev rules not found: $UDEV_RULES (optional)"
    fi

    if [ $missing -eq 1 ]; then
        print_error "Some required files are missing. Cannot continue."
        exit 1
    fi

    print_success "All required source files found"
}

# ============================================================================
# INSTALLATION
# ============================================================================

do_install() {
    print_header
    check_root "install"
    check_source_files

    echo ""
    print_info "Installing MOTU M4 Dynamic Optimizer..."
    echo ""

    # Stop existing service if running
    if systemctl is-active --quiet "${SCRIPT_NAME}.service" 2>/dev/null; then
        print_step "Stopping existing service..."
        systemctl stop "${SCRIPT_NAME}.service" 2>/dev/null || true
        print_success "Service stopped"
    fi

    # Create library directory
    print_step "Creating library directory..."
    mkdir -p "$INSTALL_LIB"
    print_success "Created $INSTALL_LIB"

    # Copy library modules
    print_step "Installing library modules..."
    cp -r "${LIB_DIR}/"*.sh "$INSTALL_LIB/"
    chmod 644 "${INSTALL_LIB}/"*.sh
    print_success "Installed $(ls -1 "${INSTALL_LIB}/"*.sh | wc -l) modules to $INSTALL_LIB"

    # Create wrapper script that uses installed library
    print_step "Installing main script..."

    # Create a modified version that points to installed lib location
    cat > "${INSTALL_BIN}/${SCRIPT_NAME}.sh" << 'WRAPPER_EOF'
#!/bin/bash

# MOTU M4 Dynamic Optimizer v4 - Hybrid Strategy (Stability-optimized)
# Installed wrapper script

# Note: Do NOT use "set -e" here - many operations may fail non-critically
# (e.g., IRQ threading not supported, some kernel params not available)

# Use installed library location
SCRIPT_DIR="/usr/local/lib/motu-m4-dynamic-optimizer"
LIB_DIR="$SCRIPT_DIR"

# Check if lib directory exists
if [ ! -d "$LIB_DIR" ]; then
    echo "❌ Error: Library directory not found: $LIB_DIR"
    echo "   Please reinstall the optimizer."
    exit 1
fi

# List of required modules in load order
REQUIRED_MODULES=(
    "config.sh" "logging.sh" "checks.sh" "jack.sh" "xrun.sh"
    "process.sh" "usb.sh" "kernel.sh" "optimization.sh"
    "status.sh" "monitor.sh"
)

# Load all modules
for module in "${REQUIRED_MODULES[@]}"; do
    module_path="$LIB_DIR/$module"
    if [ -f "$module_path" ]; then
        source "$module_path"
    else
        echo "❌ Error: Required module not found: $module_path"
        exit 1
    fi
done

# Show help
show_help() {
    echo "$OPTIMIZER_NAME v$OPTIMIZER_VERSION - $OPTIMIZER_STRATEGY"
    echo ""
    echo "Usage: $0 [monitor|once|status|detailed|live-xruns|stop]"
    echo ""
    echo "Commands:"
    echo "  monitor     - Continuous monitoring (default)"
    echo "  once        - One-time optimization"
    echo "  status      - Standard status display"
    echo "  detailed    - Detailed hardware monitoring"
    echo "  live-xruns  - Live xrun monitoring (real-time)"
    echo "  stop        - Deactivate optimizations"
    echo ""
    echo "🎯 v4 Advantage: Optimal balance of performance and stability!"
}

# Main command handler
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
            log_message "🎵 One-time activation of Hybrid Audio Optimizations"
            activate_audio_optimizations
        else
            log_message "🔧 MOTU M4 not detected - Deactivating optimizations"
            deactivate_audio_optimizations
        fi
        ;;
    "once-delayed")
        delayed_service_start
        ;;
    "status")
        show_status
        ;;
    "detailed"|"detail"|"monitor-detail")
        show_detailed_status
        ;;
    "stop"|"reset")
        log_message "🛑 Manual reset requested"
        deactivate_audio_optimizations
        ;;
    "help"|"-h"|"--help")
        show_help
        exit 0
        ;;
    *)
        show_help
        exit 1
        ;;
esac
WRAPPER_EOF

    chmod +x "${INSTALL_BIN}/${SCRIPT_NAME}.sh"
    print_success "Installed main script to ${INSTALL_BIN}/${SCRIPT_NAME}.sh"

    # Create symlink without .sh extension for convenience
    print_step "Creating convenience symlink..."
    ln -sf "${INSTALL_BIN}/${SCRIPT_NAME}.sh" "${INSTALL_BIN}/${SCRIPT_NAME}"
    print_success "Created symlink: ${INSTALL_BIN}/${SCRIPT_NAME}"

    # Install systemd service
    if [ -f "$SERVICE_FILE" ]; then
        print_step "Installing systemd service..."
        cp "$SERVICE_FILE" "${SYSTEMD_DIR}/"
        chmod 644 "${SYSTEMD_DIR}/${SCRIPT_NAME}.service"
        print_success "Installed service file"
    fi

    # Install delayed service if exists
    if [ -f "$DELAYED_SERVICE_FILE" ]; then
        print_step "Installing delayed systemd service..."
        cp "$DELAYED_SERVICE_FILE" "${SYSTEMD_DIR}/"
        chmod 644 "${SYSTEMD_DIR}/${SCRIPT_NAME}-delayed.service"
        print_success "Installed delayed service file"
    fi

    # Install udev rules
    if [ -f "$UDEV_RULES" ]; then
        print_step "Installing udev rules..."
        cp "$UDEV_RULES" "${UDEV_DIR}/"
        chmod 644 "${UDEV_DIR}/99-motu-m4-audio-optimizer.rules"
        print_success "Installed udev rules"
    fi

    # Create log file with correct permissions
    print_step "Setting up log file..."
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    print_success "Created log file: $LOG_FILE"

    # Reload systemd and udev
    print_step "Reloading system daemons..."
    systemctl daemon-reload
    if [ -f "$UDEV_RULES" ]; then
        udevadm control --reload-rules
        udevadm trigger --subsystem-match=usb
    fi
    print_success "System daemons reloaded"

    # Enable service (but don't start - udev will handle that)
    if [ -f "${SYSTEMD_DIR}/${SCRIPT_NAME}.service" ]; then
        print_step "Enabling service..."
        systemctl enable "${SCRIPT_NAME}.service" 2>/dev/null || true
        print_success "Service enabled (will start automatically when MOTU M4 is connected)"
    fi

    echo ""
    print_success "Installation complete!"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Usage:"
    echo "    ${SCRIPT_NAME} status      - Show current status"
    echo "    ${SCRIPT_NAME} detailed    - Detailed hardware info"
    echo "    ${SCRIPT_NAME} live-xruns  - Live xrun monitoring"
    echo "    ${SCRIPT_NAME} once        - One-time optimization"
    echo ""
    echo "  The optimizer will automatically activate when MOTU M4 is connected."
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# UNINSTALLATION
# ============================================================================

do_uninstall() {
    print_header
    check_root "uninstall"

    echo ""
    print_info "Uninstalling MOTU M4 Dynamic Optimizer..."
    echo ""

    # Stop and disable service
    print_step "Stopping and disabling services..."
    systemctl stop "${SCRIPT_NAME}.service" 2>/dev/null || true
    systemctl stop "${SCRIPT_NAME}-delayed.service" 2>/dev/null || true
    systemctl disable "${SCRIPT_NAME}.service" 2>/dev/null || true
    systemctl disable "${SCRIPT_NAME}-delayed.service" 2>/dev/null || true
    print_success "Services stopped and disabled"

    # Remove main script and symlink
    print_step "Removing scripts..."
    rm -f "${INSTALL_BIN}/${SCRIPT_NAME}.sh"
    rm -f "${INSTALL_BIN}/${SCRIPT_NAME}"
    print_success "Removed scripts from ${INSTALL_BIN}"

    # Remove library directory
    print_step "Removing library modules..."
    rm -rf "$INSTALL_LIB"
    print_success "Removed $INSTALL_LIB"

    # Remove systemd services
    print_step "Removing systemd services..."
    rm -f "${SYSTEMD_DIR}/${SCRIPT_NAME}.service"
    rm -f "${SYSTEMD_DIR}/${SCRIPT_NAME}-delayed.service"
    print_success "Removed service files"

    # Remove udev rules
    print_step "Removing udev rules..."
    rm -f "${UDEV_DIR}/99-motu-m4-audio-optimizer.rules"
    print_success "Removed udev rules"

    # Reload daemons
    print_step "Reloading system daemons..."
    systemctl daemon-reload
    udevadm control --reload-rules 2>/dev/null || true
    print_success "System daemons reloaded"

    # Ask about log file
    echo ""
    read -p "Do you want to remove the log file ($LOG_FILE)? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$LOG_FILE"
        print_success "Removed log file"
    else
        print_info "Log file kept at $LOG_FILE"
    fi

    # Remove state file
    rm -f /var/run/motu-m4-state

    echo ""
    print_success "Uninstallation complete!"
    echo ""
}

# ============================================================================
# UPDATE
# ============================================================================

do_update() {
    print_header
    check_root "update"
    check_source_files

    echo ""
    print_info "Updating MOTU M4 Dynamic Optimizer..."
    echo ""

    # Check if already installed
    if [ ! -d "$INSTALL_LIB" ]; then
        print_warning "Optimizer is not installed. Running full installation..."
        do_install
        return
    fi

    # Stop service temporarily
    local was_running=false
    if systemctl is-active --quiet "${SCRIPT_NAME}.service" 2>/dev/null; then
        print_step "Stopping service for update..."
        systemctl stop "${SCRIPT_NAME}.service"
        was_running=true
        print_success "Service stopped"
    fi

    # Update library modules
    print_step "Updating library modules..."
    cp -r "${LIB_DIR}/"*.sh "$INSTALL_LIB/"
    chmod 644 "${INSTALL_LIB}/"*.sh
    print_success "Updated $(ls -1 "${INSTALL_LIB}/"*.sh | wc -l) modules"

    # Update main script (regenerate wrapper)
    print_step "Updating main script..."
    # Re-run the install to regenerate the wrapper script
    do_install > /dev/null 2>&1 || true
    print_success "Updated main script"

    # Reload daemons
    print_step "Reloading system daemons..."
    systemctl daemon-reload
    udevadm control --reload-rules 2>/dev/null || true
    print_success "System daemons reloaded"

    # Restart service if it was running
    if [ "$was_running" = true ]; then
        print_step "Restarting service..."
        systemctl start "${SCRIPT_NAME}.service"
        print_success "Service restarted"
    fi

    echo ""
    print_success "Update complete!"
    echo ""
}

# ============================================================================
# STATUS CHECK
# ============================================================================

do_status() {
    print_header

    echo "Installation Status:"
    echo ""

    # Check main script
    if [ -x "${INSTALL_BIN}/${SCRIPT_NAME}.sh" ]; then
        print_success "Main script installed: ${INSTALL_BIN}/${SCRIPT_NAME}.sh"
    else
        print_error "Main script NOT installed"
    fi

    # Check symlink
    if [ -L "${INSTALL_BIN}/${SCRIPT_NAME}" ]; then
        print_success "Symlink exists: ${INSTALL_BIN}/${SCRIPT_NAME}"
    else
        print_warning "Symlink missing"
    fi

    # Check library directory
    if [ -d "$INSTALL_LIB" ]; then
        local module_count=$(ls -1 "${INSTALL_LIB}/"*.sh 2>/dev/null | wc -l)
        print_success "Library installed: $INSTALL_LIB ($module_count modules)"
    else
        print_error "Library NOT installed"
    fi

    # Check systemd service
    if [ -f "${SYSTEMD_DIR}/${SCRIPT_NAME}.service" ]; then
        print_success "Systemd service installed"
        if systemctl is-enabled --quiet "${SCRIPT_NAME}.service" 2>/dev/null; then
            print_success "Service is enabled"
        else
            print_warning "Service is disabled"
        fi
        if systemctl is-active --quiet "${SCRIPT_NAME}.service" 2>/dev/null; then
            print_success "Service is running"
        else
            print_info "Service is not running"
        fi
    else
        print_warning "Systemd service NOT installed"
    fi

    # Check udev rules
    if [ -f "${UDEV_DIR}/99-motu-m4-audio-optimizer.rules" ]; then
        print_success "Udev rules installed"
    else
        print_warning "Udev rules NOT installed"
    fi

    # Check log file
    if [ -f "$LOG_FILE" ]; then
        local log_size=$(du -h "$LOG_FILE" | cut -f1)
        print_success "Log file exists: $LOG_FILE ($log_size)"
    else
        print_info "Log file not created yet"
    fi

    # Check MOTU M4 connection
    echo ""
    echo "Hardware Status:"
    echo ""
    if lsusb 2>/dev/null | grep -q "Mark of the Unicorn"; then
        print_success "MOTU M4 is connected"
    else
        print_info "MOTU M4 is NOT connected"
    fi

    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

show_usage() {
    echo "MOTU M4 Dynamic Optimizer - Installer"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  install    - Install the optimizer"
    echo "  uninstall  - Remove the optimizer"
    echo "  update     - Update existing installation"
    echo "  status     - Check installation status"
    echo ""
}

case "${1:-}" in
    install)
        do_install
        ;;
    uninstall|remove)
        do_uninstall
        ;;
    update|upgrade)
        do_update
        ;;
    status|check)
        do_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
