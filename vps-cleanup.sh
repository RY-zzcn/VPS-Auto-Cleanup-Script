#!/bin/bash

# VPS-Auto-Cleanup Script v3.0 - GitHub Distribution Edition
# Author: RY-zzcn
# Project: https://github.com/RY-zzcn/VPS-Auto-Cleanup-Script
#
# A safe, cross-platform, and versatile script for automating VPS maintenance.
# Features:
# - Supports Debian/Ubuntu, CentOS/Fedora, Arch Linux.
# - Safe cleanup: Uses package managers for kernel/dependency removal.
# - Intelligent log management.
# - Choice of scheduler: Systemd Timer (recommended) or Cron.
# - Both interactive (for direct use) and non-interactive (for automation/one-liners) modes.

set -e

# --- Default Configuration ---
LOG_RETENTION_DAYS=7
LOG_TRUNCATE_SIZE_MB=50
OWN_LOG_FILE="/var/local/log/vps-auto-clean.log"

# --- Global Variables ---
green='\033[0;32m'; yellow='\033[1;33m'; cyan='\033[1;36m'; plain='\033[0m'
PKG_MANAGER=""; PKG_INSTALL_CMD=""; PKG_CLEAN_CMD=""; PKG_AUTOREMOVE_CMD=""
DAILY_SCRIPT_PATH="/usr/local/bin/vps-auto-clean-daily.sh"
CRON_IS_INSTALLED=false
INTERACTIVE_MODE=true
SCHEDULE_MODE=""
SCHEDULE_TIME=""
SCHEDULE_HOUR=""
SCHEDULE_MINUTE=""

# --- Function Definitions ---

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "This script cleans up a VPS and optionally sets up a daily scheduled task."
    echo "If no options are provided, it runs in interactive mode."
    echo ""
    echo "Options:"
    echo "  -m, --mode [systemd|cron|none]   Set the schedule mode."
    echo "                                     - systemd: (Recommended) Use Systemd Timer."
    echo "                                     - cron: Use traditional Cron."
    echo "                                     - none: Do not set up a scheduled task."
    echo "  -t, --time <HH:MM>                 Set the schedule time in 24-hour format (e.g., 03:00)."
    echo "                                     Required if --mode is 'systemd' or 'cron'."
    echo "  -h, --help                         Display this help message."
    echo ""
    echo "Example: $0 --mode systemd --time 04:00"
}

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"; PKG_INSTALL_CMD="apt-get install -y"; PKG_CLEAN_CMD="apt-get clean -y"; PKG_AUTOREMOVE_CMD="apt-get autoremove --purge -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"; PKG_INSTALL_CMD="dnf install -y"; PKG_CLEAN_CMD="dnf clean all"; PKG_AUTOREMOVE_CMD="dnf autoremove -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"; PKG_INSTALL_CMD="yum install -y"; PKG_CLEAN_CMD="yum clean all"; PKG_AUTOREMOVE_CMD="yum autoremove -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"; PKG_INSTALL_CMD="pacman -S --noconfirm"; PKG_CLEAN_CMD="paccache -r -k1 && paccache -ruk0"; PKG_AUTOREMOVE_CMD="pacman -Qtdq | pacman -Rns --noconfirm - || true"
    else
        echo -e "${yellow}Error: Unsupported package manager.${plain}" >&2; exit 1
    fi
}

run_cleanup() {
    echo -e "${yellow}[Preparation] Installing dependencies and preparing log directory...${plain}"
    $PKG_INSTALL_CMD bc > /dev/null 2>&1; mkdir -p "$(dirname "$OWN_LOG_FILE")"
    echo "======== $(date '+%Y-%m-%d %H:%M:%S') - Cleanup task started ========" >> "$OWN_LOG_FILE"
    echo -e "${yellow}[Disk Usage] Calculating disk space before cleanup...${plain}"
    pre_clean_used_kb=$(df -k / | awk 'NR==2 {print $3}')
    echo -e "${yellow}[System Cleanup] Cleaning packages using ${PKG_MANAGER}...${plain}"
    $PKG_CLEAN_CMD &> /dev/null; $PKG_AUTOREMOVE_CMD &> /dev/null
    echo -e "${yellow}[Log Cleanup] Cleaning old log files...${plain}"
    find /var/log -type f -mtime +"$LOG_RETENTION_DAYS" -delete
    find /var/log -type f -size +"${LOG_TRUNCATE_SIZE_MB}M" -exec truncate -s 0 {} \;
    journalctl --vacuum-time=1d > /dev/null 2>&1 || true
    echo -e "${green}✅ Cleanup task completed!${plain}"
    echo ""; echo -e "${yellow}[Result]${plain}"
    post_clean_used_kb=$(df -k / | awk 'NR==2 {print $3}')
    cleared_kb=$((pre_clean_used_kb - post_clean_used_kb))
    if [ "$cleared_kb" -lt 0 ]; then cleared_kb=0; fi
    cleared_mb=$(echo "scale=2; $cleared_kb / 1024" | bc)
    echo -e "Successfully freed space: ${green}${cleared_mb} MB${plain}"
    echo ""; echo -e "${yellow}[Current Disk]${plain}"; df -h /
    echo "$(date '+%Y-%m-%d %H:%M:%S') Freed: ${cleared_mb} MB" >> "$OWN_LOG_FILE"
    echo "======== $(date '+%Y-%m-%d %H:%M:%S') - Cleanup task finished ========" >> "$OWN_LOG_FILE"; echo "" >> "$OWN_LOG_FILE"
}

setup_systemd_timer() {
    echo ""; echo -e "${yellow}[Configuring Systemd Timer]...${plain}"
    local service_name="vps-auto-clean"; local service_file="/etc/systemd/system/${service_name}.service"; local timer_file="/etc/systemd/system/${service_name}.timer"
    cat <<EOF > "$service_file"
[Unit]
Description=Daily run of VPS auto-cleanup script
After=network.target
[Service]
Type=oneshot
ExecStart=$DAILY_SCRIPT_PATH
EOF
    cat <<EOF > "$timer_file"
[Unit]
Description=Run vps-auto-clean service daily
[Timer]
OnCalendar=*-*-* ${SCHEDULE_HOUR}:${SCHEDULE_MINUTE}:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
    echo -e "${yellow}Enabling and starting timer...${plain}"
    systemctl daemon-reload; systemctl enable "${service_name}.timer"; systemctl start "${service_name}.timer"
    echo -e "${green}✅ Systemd Timer configured for ${SCHEDULE_HOUR}:${SCHEDULE_MINUTE} daily.${plain}"
    echo -e "${yellow}Verify with: systemctl list-timers${plain}"
}

setup_cron_job() {
    echo ""; echo -e "${yellow}[Configuring Cron]...${plain}"
    if ! $CRON_IS_INSTALLED; then
        echo -e "${yellow}'crontab' not found. Attempting to install cron service...${plain}"
        local cron_package_name="cron"; local cron_service_name="cron"
        if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
            cron_package_name="cronie"; cron_service_name="crond"
        elif [[ "$PKG_MANAGER" == "pacman" ]]; then
            cron_package_name="cronie"; cron_service_name="cronie"
        fi
        $PKG_INSTALL_CMD "$cron_package_name" > /dev/null 2>&1
        echo -e "${yellow}Starting and enabling cron service...${plain}"
        systemctl start "$cron_service_name"; systemctl enable "$cron_service_name"
        echo -e "${green}✅ Cron service installed and started.${plain}"
    fi
    (crontab -l 2>/dev/null | grep -v -F "$DAILY_SCRIPT_PATH"; echo "${SCHEDULE_MINUTE} ${SCHEDULE_HOUR} * * * ${DAILY_SCRIPT_PATH} >/dev/null 2>&1") | crontab -
    echo -e "${green}✅ Cron job configured for ${SCHEDULE_HOUR}:${SCHEDULE_MINUTE} daily.${plain}"
    echo -e "${yellow}Verify with: crontab -l${plain}"
}

create_daily_script() {
cat <<EOF > "$DAILY_SCRIPT_PATH"
#!/bin/bash
set -e
OWN_LOG_FILE="${OWN_LOG_FILE}"; PKG_CLEAN_CMD="${PKG_CLEAN_CMD}"; PKG_AUTOREMOVE_CMD="${PKG_AUTOREMOVE_CMD}"
echo "======== \$(date '+%Y-%m-%d %H:%M:%S') - Background cleanup started ========" >> "\$OWN_LOG_FILE"
pre_clean_used_kb=\$(df -k / | awk 'NR==2 {print \$3}')
\$PKG_CLEAN_CMD > /dev/null 2>&1; \$PKG_AUTOREMOVE_CMD > /dev/null 2>&1
find /var/log -type f -mtime +${LOG_RETENTION_DAYS} -delete
find /var/log -type f -size +${LOG_TRUNCATE_SIZE_MB}M -exec truncate -s 0 {} \;
journalctl --vacuum-time=1d > /dev/null 2>&1 || true
post_clean_used_kb=\$(df -k / | awk 'NR==2 {print \$3}')
cleared_kb=\$((pre_clean_used_kb - post_clean_used_kb)); if [ "\$cleared_kb" -lt 0 ]; then cleared_kb=0; fi
cleared_mb=\$(echo "scale=2; \$cleared_kb / 1024" | bc)
echo "\$(date '+%Y-%m-%d %H:%M:%S') Freed: \${cleared_mb} MB" >> "\$OWN_LOG_FILE"
echo "======== \$(date '+%Y-%m-%d %H:%M:%S') - Background cleanup finished ========" >> "\$OWN_LOG_FILE"; echo "" >> "\$OWN_LOG_FILE"
EOF
    chmod +x "$DAILY_SCRIPT_PATH"
}

# --- Main Logic ---

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--mode) SCHEDULE_MODE="$2"; shift ;;
        -t|--time) SCHEDULE_TIME="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# If arguments were provided, switch to non-interactive mode
if [ -n "$SCHEDULE_MODE" ]; then
    INTERACTIVE_MODE=false
fi

# --- Non-Interactive Mode Logic ---
if ! $INTERACTIVE_MODE; then
    if [[ "$SCHEDULE_MODE" == "systemd" || "$SCHEDULE_MODE" == "cron" ]]; then
        if [ -z "$SCHEDULE_TIME" ]; then
            echo "Error: --time HH:MM is required when --mode is 'systemd' or 'cron'." >&2
            usage; exit 1
        fi
        if ! [[ "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            echo "Error: Invalid time format for --time. Use HH:MM." >&2
            usage; exit 1
        fi
        SCHEDULE_HOUR=$(echo "$SCHEDULE_TIME" | cut -d: -f1)
        SCHEDULE_MINUTE=$(echo "$SCHEDULE_TIME" | cut -d: -f2)
    elif [ "$SCHEDULE_MODE" != "none" ]; then
        echo "Error: Invalid mode '$SCHEDULE_MODE'. Use 'systemd', 'cron', or 'none'." >&2
        usage; exit 1
    fi
fi

# --- Script Execution ---

echo -e "${cyan}================= VPS Auto-Cleanup Script v3.0 =================${plain}"
if [ "$(id -u)" -ne 0 ]; then echo -e "${yellow}Error: This script must be run as root.${plain}" >&2; exit 1; fi

detect_package_manager
echo -e "${yellow}[System] Detected package manager: ${green}${PKG_MANAGER}${plain}"

run_cleanup

# --- Scheduler Setup ---
if $INTERACTIVE_MODE; then
    # Interactive Mode
    if command -v crontab &> /dev/null; then CRON_IS_INSTALLED=true; fi
    echo ""; echo -e "${cyan}-------------------- Scheduler Setup --------------------${plain}"
    echo "Please choose a scheduling method:"
    if $CRON_IS_INSTALLED; then cron_option_text="${yellow}2) Use Cron (traditional, already installed)${plain}"; else cron_option_text="${yellow}2) Use Cron (traditional, will be installed)${plain}"; fi
    echo -e "  ${green}1) Use Systemd Timer (recommended, no extra memory usage)${plain}"
    echo -e "  $cron_option_text"
    echo -e "  3) Do not set up a scheduler"
    echo -e "${cyan}------------------------------------------------------${plain}"
    read -p "Enter your choice [1-3] (default: 1): " choice
    SCHEDULE_MODE_CHOICE="${choice:-1}"

    case "$SCHEDULE_MODE_CHOICE" in
        1) SCHEDULE_MODE="systemd" ;;
        2) SCHEDULE_MODE="cron" ;;
        *) SCHEDULE_MODE="none" ;;
    esac

    if [[ "$SCHEDULE_MODE" == "systemd" || "$SCHEDULE_MODE" == "cron" ]]; then
         while true; do
            read -p "Enter desired daily execution time (24h format, e.g., 03:00): " user_time
            if [[ "$user_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                SCHEDULE_HOUR=$(echo "$user_time" | cut -d: -f1)
                SCHEDULE_MINUTE=$(echo "$user_time" | cut -d: -f2)
                break
            else
                echo -e "${yellow}Invalid format. Please try again.${plain}"
            fi
        done
    fi
fi

# Final setup based on mode (interactive or non-interactive)
if [[ "$SCHEDULE_MODE" == "systemd" || "$SCHEDULE_MODE" == "cron" ]]; then
    create_daily_script
    if [ "$SCHEDULE_MODE" == "systemd" ]; then
        if ! command -v systemctl &> /dev/null; then echo -e "${yellow}Error: systemctl not found. Cannot use Systemd Timer.${plain}" >&2; exit 1; fi
        setup_systemd_timer
    else # cron
        setup_cron_job
    fi
elif [ "$SCHEDULE_MODE" == "none" ]; then
    echo -e "${green}✅ No scheduled task will be set up.${plain}"
else
    # This case handles when INTERACTIVE_MODE is false but no mode was specified.
    echo -e "${green}✅ No scheduled task was specified.${plain}"
fi

echo ""
echo -e "${cyan}======================= Deployment Finished =======================${plain}"
echo -e "${yellow}[Log File]${plain} ${OWN_LOG_FILE}"
