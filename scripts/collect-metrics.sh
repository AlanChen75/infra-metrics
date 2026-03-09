#!/bin/bash
# collect-metrics.sh — Collect system metrics every 5 minutes
# Runs locally on each node via cron
# Data stored in: /var/lib/infra-metrics/<hostname>/YYYY-MM-DD.csv

set -euo pipefail

HOSTNAME=$(hostname -s)
DATA_DIR="/var/lib/infra-metrics"
TODAY=$(date +%Y-%m-%d)
CSV_FILE="${DATA_DIR}/${TODAY}.csv"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

# Ensure data dir exists
mkdir -p "${DATA_DIR}"

# CPU usage (1-second sample)
CPU_PERCENT=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' 2>/dev/null || echo "0")

# Memory
read MEM_USED_MB MEM_TOTAL_MB <<< $(free -m | awk '/^Mem:/{print $3, $2}')

# Temperature
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP_C=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
else
    TEMP_C="0"
fi

# Disk usage (root partition)
DISK_PERCENT=$(df / | awk 'NR==2{gsub(/%/,""); print $5}')

# GPU fields (default 0)
GPU_TEMP="0"
GPU_UTIL="0"
GPU_MEM_USED="0"
GPU_MEM_TOTAL="0"

# Detect NVIDIA GPU
if command -v nvidia-smi &>/dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "0, 0, 0, 0")
    IFS=', ' read -r GPU_TEMP GPU_UTIL GPU_MEM_USED GPU_MEM_TOTAL <<< "${GPU_INFO}"
fi

# Write header if new file
if [ ! -f "${CSV_FILE}" ]; then
    echo "timestamp,cpu_percent,mem_used_mb,mem_total_mb,temp_c,disk_percent,gpu_temp,gpu_util,gpu_mem_used_mb,gpu_mem_total_mb" > "${CSV_FILE}"
fi

# Append data
echo "${TIMESTAMP},${CPU_PERCENT},${MEM_USED_MB},${MEM_TOTAL_MB},${TEMP_C},${DISK_PERCENT},${GPU_TEMP},${GPU_UTIL},${GPU_MEM_USED},${GPU_MEM_TOTAL}" >> "${CSV_FILE}"
