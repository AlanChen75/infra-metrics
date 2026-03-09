#!/bin/bash
# collect-ai-hub.sh — Collect AI Hub service status and usage
# Runs on ac-mac only, every 5 minutes via cron

set -euo pipefail

DATA_DIR="/var/lib/infra-metrics/ai-hub"
TODAY=$(date +%Y-%m-%d)
CSV_FILE="${DATA_DIR}/${TODAY}.csv"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)
AI_HUB_URL="http://127.0.0.1:8760"

mkdir -p "${DATA_DIR}"

# Write header if new file
if [ ! -f "${CSV_FILE}" ]; then
    echo "timestamp,provider,category,busy,healthy,today_used,daily_limit,remaining" > "${CSV_FILE}"
fi

# Fetch AI Hub status
RESPONSE=$(curl -s --max-time 10 "${AI_HUB_URL}/api/status" 2>/dev/null || echo "")

if [ -z "${RESPONSE}" ]; then
    echo "${TIMESTAMP},ai_hub,system,false,false,0,0,0" >> "${CSV_FILE}"
    exit 0
fi

echo "${RESPONSE}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    ts = '${TIMESTAMP}'
    for name, info in data.items():
        category = info.get('category', 'unknown')
        busy = str(info.get('busy', False)).lower()
        healthy = str(info.get('healthy', False)).lower()
        used = info.get('today_used', 0)
        limit = info.get('daily_limit', 0)
        remaining = info.get('remaining', 0)
        print(f'{ts},{name},{category},{busy},{healthy},{used},{limit},{remaining}')
except Exception as e:
    print(f'${TIMESTAMP},ai_hub,system,false,false,0,0,0')
" >> "${CSV_FILE}"
