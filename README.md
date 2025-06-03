# VPS 自动维护脚本 (VPS-Auto-Cleanup-Script)

**作者: RY-zzcn**

一个安全、跨平台、功能强大的 VPS 自动化维护脚本，旨在通过清理不必要的文件和日志来释放磁盘空间，并提供灵活的定时任务选项。

## ✨ 功能特性

- **跨平台兼容**：自动检测并支持 Debian/Ubuntu (`apt`), CentOS/Fedora (`dnf`/`yum`), 以及 Arch Linux (`pacman`)。
- **安全清理**：使用系统包管理器安全地移除孤立的依赖和旧内核，避免误删重要文件。
- **智能日志管理**：删除过期日志，并清空过大的日志文件，而不是粗暴地删除整个日志目录。
- **灵活的调度器**：
  - **Systemd Timer** (推荐): 现代、高效，无额外内存占用。
  - **Cron**: 传统、稳定，兼容性好 (若未安装会自动安装)。
- **双模式运行**：
  - **交互模式**: 对新手友好，通过菜单引导完成所有设置。
  - **非交互模式**: 支持命令行参数，完美适配自动化部署和一键安装命令。
- **日志记录**：每次运行都会将释放的空间大小记录到日志文件 (`/var/local/log/vps-auto-clean.log`)。

## 🚀 使用方法

### 一键执行 (推荐)

此方法会在 **交互模式** 下运行脚本，引导您完成所有设置。

**使用 cURL:**
```bash
bash <(curl -sL [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh))
```

**使用 Wget:**
```bash
bash <(wget -qO- [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh))
```

### 非交互式用法 (高级)

您可以通过添加参数来完全自动化部署，无需任何手动输入。

**示例 1：使用 Systemd Timer，在每天 04:00 执行**
```bash
bash <(curl -sL [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh)) --mode systemd --time 04:00
```

**示例 2：使用 Cron，在每天 02:30 执行**
```bash
bash <(curl -sL [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh)) -m cron -t 02:30
```

**示例 3：只执行一次清理，不设置任何定时任务**
```bash
bash <(curl -sL [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh)) -m none
```

### 下载后执行

如果您希望保留脚本文件方便日后复用或审查，可以使用此方法。

**使用 cURL:**
```bash
curl -L [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh) -o vps-cleanup.sh && chmod +x vps-cleanup.sh && sudo ./vps-cleanup.sh
```

**使用 Wget:**
```bash
wget [https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh](https://raw.githubusercontent.com/RY-zzcn/VPS-Auto-Cleanup-Script/main/vps-cleanup.sh) && chmod +x vps-cleanup.sh && sudo ./vps-cleanup.sh
```


## 命令行参数

| 参数 | 别名 | 描述 |
| :--- | :--- | :--- |
| `--mode [mode]` | `-m` | 设置定时任务模式。可选值: `systemd`, `cron`, `none`。 |
| `--time <HH:MM>`| `-t` | 设置每日执行时间 (24小时制)。当模式为 `systemd` 或 `cron` 时必须提供。 |
| `--help` | `-h` | 显示此帮助信息。 |


## 授权协议

本项目采用 [MIT License](LICENSE) 授权。
