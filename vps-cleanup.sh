#!/bin/bash

# VPS-Auto-Cleanup Script v3.0 - (Chinese Localization)
# Author: RY-zzcn
# Project: https://github.com/RY-zzcn/VPS-Auto-Cleanup-Script
#
# 一个安全、跨平台、功能强大的 VPS 自动化维护脚本。
# 功能:
# - 支持 Debian/Ubuntu, CentOS/Fedora, Arch Linux。
# - 使用包管理器安全清理依赖和旧内核。
# - 智能的日志管理。
# - 可选 Systemd Timer (推荐) 或 Cron作为定时任务。
# - 支持交互式 (直接运行) 和非交互式 (带参数运行) 两种模式。

set -e

# --- 默认配置 ---
LOG_RETENTION_DAYS=7
LOG_TRUNCATE_SIZE_MB=50
OWN_LOG_FILE="/var/local/log/vps-auto-clean.log"

# --- 全局变量 ---
green='\033[0;32m'; yellow='\033[1;33m'; cyan='\033[1;36m'; plain='\033[0m'
PKG_MANAGER=""; PKG_INSTALL_CMD=""; PKG_CLEAN_CMD=""; PKG_AUTOREMOVE_CMD=""
DAILY_SCRIPT_PATH="/usr/local/bin/vps-auto-clean-daily.sh"
CRON_IS_INSTALLED=false
INTERACTIVE_MODE=true
SCHEDULE_MODE=""
SCHEDULE_TIME=""
SCHEDULE_HOUR=""
SCHEDULE_MINUTE=""

# --- 函数定义 ---

usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "此脚本用于清理 VPS 并可选地设置每日定时任务。"
    echo "如果未提供任何选项，脚本将以交互模式运行。"
    echo ""
    echo "选项:"
    echo "  -m, --mode [systemd|cron|none]   设置定时任务模式。"
    echo "                                     - systemd: (推荐) 使用 Systemd 定时器。"
    echo "                                     - cron:    使用传统的 Cron。"
    echo "                                     - none:    不设置定时任务。"
    echo "  -t, --time <HH:MM>                 设置定时任务的执行时间 (24小时制, 例如 03:00)。"
    echo "                                     当 --mode 为 'systemd' 或 'cron' 时必须提供。"
    echo "  -h, --help                         显示此帮助信息。"
    echo ""
    echo "示例: $0 --mode systemd --time 04:00"
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
        echo -e "${yellow}错误: 不支持的包管理器。${plain}" >&2; exit 1
    fi
}

run_cleanup() {
    echo -e "${yellow}[准备工作] 安装依赖组件并准备日志目录...${plain}"
    $PKG_INSTALL_CMD bc > /dev/null 2>&1; mkdir -p "$(dirname "$OWN_LOG_FILE")"
    echo "======== $(date '+%Y-%m-%d %H:%M:%S') - 清理任务开始 ========" >> "$OWN_LOG_FILE"
    echo -e "${yellow}[磁盘使用] 正在计算清理前的磁盘占用...${plain}"
    pre_clean_used_kb=$(df -k / | awk 'NR==2 {print $3}')
    echo -e "${yellow}[系统清理] 正在使用 ${PKG_MANAGER} 清理软件包...${plain}"
    $PKG_CLEAN_CMD &> /dev/null; $PKG_AUTOREMOVE_CMD &> /dev/null
    echo -e "${yellow}[日志清理] 正在清理旧的日志文件...${plain}"
    find /var/log -type f -mtime +"$LOG_RETENTION_DAYS" -delete
    find /var/log -type f -size +"${LOG_TRUNCATE_SIZE_MB}M" -exec truncate -s 0 {} \;
    journalctl --vacuum-time=1d > /dev/null 2>&1 || true
    echo -e "${green}✅ 清理任务执行完毕！${plain}"
    echo ""; echo -e "${yellow}[结果统计]${plain}"
    post_clean_used_kb=$(df -k / | awk 'NR==2 {print $3}')
    cleared_kb=$((pre_clean_used_kb - post_clean_used_kb))
    if [ "$cleared_kb" -lt 0 ]; then cleared_kb=0; fi
    cleared_mb=$(echo "scale=2; $cleared_kb / 1024" | bc)
    echo -e "本轮成功释放空间: ${green}${cleared_mb} MB${plain}"
    echo ""; echo -e "${yellow}[当前磁盘]${plain}"; df -h /
    echo "$(date '+%Y-%m-%d %H:%M:%S') 释放: ${cleared_mb} MB" >> "$OWN_LOG_FILE"
    echo "======== $(date '+%Y-%m-%d %H:%M:%S') - 清理任务结束 ========" >> "$OWN_LOG_FILE"; echo "" >> "$OWN_LOG_FILE"
}

setup_systemd_timer() {
    echo ""; echo -e "${yellow}[配置 Systemd 定时器]...${plain}"
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
    echo -e "${yellow}正在启用并启动定时器...${plain}"
    systemctl daemon-reload; systemctl enable "${service_name}.timer"; systemctl start "${service_name}.timer"
    echo -e "${green}✅ Systemd 定时器已配置，每日 ${SCHEDULE_HOUR}:${SCHEDULE_MINUTE} 执行。${plain}"
    echo -e "${yellow}您可以使用 'systemctl list-timers' 命令查看状态。${plain}"
}

setup_cron_job() {
    echo ""; echo -e "${yellow}[配置 Cron]...${plain}"
    if ! $CRON_IS_INSTALLED; then
        echo -e "${yellow}未找到 'crontab' 命令，正在尝试安装 cron 服务...${plain}"
        local cron_package_name="cron"; local cron_service_name="cron"
        if [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
            cron_package_name="cronie"; cron_service_name="crond"
        elif [[ "$PKG_MANAGER" == "pacman" ]]; then
            cron_package_name="cronie"; cron_service_name="cronie"
        fi
        $PKG_INSTALL_CMD "$cron_package_name" > /dev/null 2>&1
        echo -e "${yellow}正在启动并启用 cron 服务...${plain}"
        systemctl start "$cron_service_name"; systemctl enable "$cron_service_name"
        echo -e "${green}✅ Cron 服务已成功安装并启动。${plain}"
    fi
    (crontab -l 2>/dev/null | grep -v -F "$DAILY_SCRIPT_PATH"; echo "${SCHEDULE_MINUTE} ${SCHEDULE_HOUR} * * * ${DAILY_SCRIPT_PATH} >/dev/null 2>&1") | crontab -
    echo -e "${green}✅ Cron 定时任务已配置，每日 ${SCHEDULE_HOUR}:${SCHEDULE_MINUTE} 执行。${plain}"
    echo -e "${yellow}您可以使用 'crontab -l' 命令查看。${plain}"
}

create_daily_script() {
cat <<EOF > "$DAILY_SCRIPT_PATH"
#!/bin/bash
set -e
OWN_LOG_FILE="${OWN_LOG_FILE}"; PKG_CLEAN_CMD="${PKG_CLEAN_CMD}"; PKG_AUTOREMOVE_CMD="${PKG_AUTOREMOVE_CMD}"
echo "======== \$(date '+%Y-%m-%d %H:%M:%S') - 后台定时清理开始 ========" >> "\$OWN_LOG_FILE"
pre_clean_used_kb=\$(df -k / | awk 'NR==2 {print \$3}')
\$PKG_CLEAN_CMD > /dev/null 2>&1; \$PKG_AUTOREMOVE_CMD > /dev/null 2>&1
find /var/log -type f -mtime +${LOG_RETENTION_DAYS} -delete
find /var/log -type f -size +${LOG_TRUNCATE_SIZE_MB}M -exec truncate -s 0 {} \;
journalctl --vacuum-time=1d > /dev/null 2>&1 || true
post_clean_used_kb=\$(df -k / | awk 'NR==2 {print \$3}')
cleared_kb=\$((pre_clean_used_kb - post_clean_used_kb)); if [ "\$cleared_kb" -lt 0 ]; then cleared_kb=0; fi
cleared_mb=\$(echo "scale=2; \$cleared_kb / 1024" | bc)
echo "\$(date '+%Y-%m-%d %H:%M:%S') 释放: \${cleared_mb} MB" >> "\$OWN_LOG_FILE"
echo "======== \$(date '+%Y-%m-%d %H:%M:%S') - 后台定时清理结束 ========" >> "\$OWN_LOG_FILE"; echo "" >> "\$OWN_LOG_FILE"
EOF
    chmod +x "$DAILY_SCRIPT_PATH"
}

# --- 主逻辑 ---

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--mode) SCHEDULE_MODE="$2"; shift ;;
        -t|--time) SCHEDULE_TIME="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知的参数: $1"; usage; exit 1 ;;
    esac
    shift
done

# 如果提供了参数，切换到非交互模式
if [ -n "$SCHEDULE_MODE" ]; then
    INTERACTIVE_MODE=false
fi

# --- 非交互模式逻辑 ---
if ! $INTERACTIVE_MODE; then
    if [[ "$SCHEDULE_MODE" == "systemd" || "$SCHEDULE_MODE" == "cron" ]]; then
        if [ -z "$SCHEDULE_TIME" ]; then
            echo "错误: 当 --mode 为 'systemd' 或 'cron' 时, 必须提供 --time HH:MM 参数。" >&2
            usage; exit 1
        fi
        if ! [[ "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            echo "错误: --time 的时间格式无效，请使用 HH:MM。" >&2
            usage; exit 1
        fi
        SCHEDULE_HOUR=$(echo "$SCHEDULE_TIME" | cut -d: -f1)
        SCHEDULE_MINUTE=$(echo "$SCHEDULE_TIME" | cut -d: -f2)
    elif [ "$SCHEDULE_MODE" != "none" ]; then
        echo "错误: 无效的模式 '$SCHEDULE_MODE'。请使用 'systemd', 'cron', 或 'none'。" >&2
        usage; exit 1
    fi
fi

# --- 脚本执行 ---

echo -e "${cyan}================= VPS 自动维护脚本 v3.0 =================${plain}"
if [ "$(id -u)" -ne 0 ]; then echo -e "${yellow}错误: 此脚本必须以 root 身份运行。${plain}" >&2; exit 1; fi

detect_package_manager
echo -e "${yellow}[系统] 检测到包管理器: ${green}${PKG_MANAGER}${plain}"

run_cleanup

# --- 定时任务设置 ---
if $INTERACTIVE_MODE; then
    # 交互模式
    if command -v crontab &> /dev/null; then CRON_IS_INSTALLED=true; fi
    echo ""; echo -e "${cyan}-------------------- 定时任务设置 --------------------${plain}"
    echo "请选择一种定时任务方式:"
    if $CRON_IS_INSTALLED; then
        cron_option_text="${yellow}2) 使用 Cron (传统方式, 已安装)${plain}"
    else
        cron_option_text="${yellow}2) 使用 Cron (传统方式, 将自动安装)${plain}"
    fi
    echo -e "  ${green}1) 使用 Systemd Timer (推荐, 无额外内存占用)${plain}"
    echo -e "  $cron_option_text"
    echo -e "  3) 不设置定时任务"
    echo -e "${cyan}------------------------------------------------------${plain}"
    read -p "请输入选项 [1-3] (默认为 1): " choice
    SCHEDULE_MODE_CHOICE="${choice:-1}"

    case "$SCHEDULE_MODE_CHOICE" in
        1) SCHEDULE_MODE="systemd" ;;
        2) SCHEDULE_MODE="cron" ;;
        *) SCHEDULE_MODE="none" ;;
    esac

    if [[ "$SCHEDULE_MODE" == "systemd" || "$SCHEDULE_MODE" == "cron" ]]; then
         while true; do
            read -p "请输入每日执行时间 (24小时制, 格式 HH:MM, 例如 03:00): " user_time
            if [[ "$user_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                SCHEDULE_HOUR=$(echo "$user_time" | cut -d: -f1)
                SCHEDULE_MINUTE=$(echo "$user_time" | cut -d: -f2)
                break
            else
                echo -e "${yellow}格式错误，请重试。${plain}"
            fi
        done
    fi
fi

# 根据模式（交互式或非交互式）进行最终设置
if [[ "$SCHEDULE_MODE" == "systemd" || "$SCHEDULE_MODE" == "cron" ]]; then
    create_daily_script
    if [ "$SCHEDULE_MODE" == "systemd" ]; then
        if ! command -v systemctl &> /dev/null; then echo -e "${yellow}错误: 未找到 systemctl 命令，无法使用 Systemd Timer。${plain}" >&2; exit 1; fi
        setup_systemd_timer
    else # cron
        setup_cron_job
    fi
elif [ "$SCHEDULE_MODE" == "none" ]; then
    echo -e "${green}✅ 好的，不设置定时任务。${plain}"
else
    # 此情况处理非交互模式下未指定模式的情形
    echo -e "${green}✅ 未指定定时任务。${plain}"
fi

echo ""
echo -e "${cyan}======================= 部署完成 =======================${plain}"
echo -e "${yellow}[日志文件]${plain} ${OWN_LOG_FILE}"
