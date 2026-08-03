#!/bin/bash
# =====================================================================
# Linux Swap 内存一键安全清理脚本 (放置于 .scripts 隐藏目录)
# =====================================================================

set -e

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

echo "=========================================="
echo " 📊 正在获取系统内存与 Swap 占用状态..."
echo "=========================================="
free -h
echo ""

# 获取可用物理内存与已用 Swap 字节数 (单位: KB)
MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
SWAP_TOTAL=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
SWAP_FREE=$(awk '/SwapFree/ {print $2}' /proc/meminfo)

if [ -z "$SWAP_TOTAL" ] || [ "$SWAP_TOTAL" -eq 0 ]; then
    echo "ℹ️ 当前系统未启用 Swap 分区/文件。"
    exit 0
fi

SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))

MEM_AVAIL_MB=$((MEM_AVAIL / 1024))
SWAP_USED_MB=$((SWAP_USED / 1024))

echo "🔍 内存与 Swap 安全指标校验："
echo "   - 物理可用内存 (Available RAM): ${MEM_AVAIL_MB} MB"
echo "   - 当前 Swap 已用 (Used Swap):   ${SWAP_USED_MB} MB"
echo ""

if [ "$SWAP_USED" -le 0 ]; then
    echo "✅ Swap 占用为 0，系统健康，无需清理！"
    exit 0
fi

if [ "$MEM_AVAIL" -le "$SWAP_USED" ]; then
    echo "❌ 风险警告: 可用物理内存 (${MEM_AVAIL_MB} MB) 小于已用 Swap (${SWAP_USED_MB} MB)！"
    echo "   如果此时强行回写 Swap，可能触发 Linux 内核 OOM Killer 导致程序异常退出。"
    echo "   建议先关闭部分高内存占用程序后再试。"
    exit 1
fi

echo "🚀 安全校验通过，开始释放 Swap 缓存..."
echo "------------------------------------------"

# 1. 将脏页刷回磁盘
echo "[1/3] 正在同步数据磁盘缓存 (sync)..."
sync

# 2. 释放 PageCache、dentries 与 inodes
echo "[2/3] 正在释放内存 PageCache 与 Inode 缓存..."
$SUDO sysctl vm.drop_caches=3 >/dev/null 2>&1 || echo 3 | $SUDO tee /proc/sys/vm/drop_caches >/dev/null

# 3. 关闭 Swap 并重新开启 (将 Swap 内容回写至物理内存)
echo "[3/3] 正在重置 Swap 分区 (swapoff -a && swapon -a)..."
$SUDO swapoff -a
$SUDO swapon -a

echo "------------------------------------------"
echo "🎉 Swap 清理完成！更新后的系统内存状态："
echo ""
free -h
