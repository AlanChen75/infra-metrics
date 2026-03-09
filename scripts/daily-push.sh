#!/bin/bash
# daily-push.sh — Centralized daily push from ac-mac
# 1. Collect CSVs from all nodes via SSH/SCP
# 2. Copy local ac-mac + ai-hub data
# 3. Git commit + push
# Runs on ac-mac cron at 00:10

set -uo pipefail

REPO_DIR="/home/ac-mac/infra-metrics"
LOCAL_DATA="/var/lib/infra-metrics"
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
LOG_FILE="/var/lib/infra-metrics/daily-push.log"
RETRY_FLAG="/var/lib/infra-metrics/.retry-pending"

# Nodes to collect from (excluding ac-mac, handled locally)
REMOTE_NODES=("ac-3090" "ac-rpi5" "acmacmini2" "ac-2012")

log() {
    echo "[$(date +%Y-%m-%dT%H:%M:%S)] $1" >> "${LOG_FILE}"
}

log "=== Daily push started ==="

# 1. Copy local ac-mac data
for DATE in "${YESTERDAY}" "${TODAY}"; do
    for SUBDIR in "" "ai-hub"; do
        if [ -n "${SUBDIR}" ]; then
            SRC="${LOCAL_DATA}/${SUBDIR}/${DATE}.csv"
            DST_DIR="${REPO_DIR}/data/ai-hub"
        else
            SRC="${LOCAL_DATA}/${DATE}.csv"
            DST_DIR="${REPO_DIR}/data/ac-mac"
        fi
        if [ -f "${SRC}" ]; then
            mkdir -p "${DST_DIR}"
            cp "${SRC}" "${DST_DIR}/${DATE}.csv"
            log "Copied local: ${SRC} -> ${DST_DIR}/"
        fi
    done
done

# 2. Pull CSVs from remote nodes
for NODE in "${REMOTE_NODES[@]}"; do
    DST_DIR="${REPO_DIR}/data/${NODE}"
    mkdir -p "${DST_DIR}"
    for DATE in "${YESTERDAY}" "${TODAY}"; do
        SRC="/var/lib/infra-metrics/${DATE}.csv"
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "${NODE}" "test -f ${SRC}" 2>/dev/null; then
            scp -o ConnectTimeout=10 -o BatchMode=yes "${NODE}:${SRC}" "${DST_DIR}/${DATE}.csv" 2>/dev/null
            if [ $? -eq 0 ]; then
                log "Pulled: ${NODE}:${SRC}"
            else
                log "WARN: Failed to pull ${NODE}:${SRC}"
            fi
        else
            log "WARN: ${NODE}:${SRC} not found, skipping"
        fi
    done
done

# 3. Git commit + push
cd "${REPO_DIR}"
git pull --rebase origin main 2>/dev/null || true

# Check if there are changes
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    log "No changes to commit"
    rm -f "${RETRY_FLAG}"
    exit 0
fi

git add data/
git commit -m "data: metrics ${YESTERDAY} ~ ${TODAY}" 2>/dev/null

if git push origin main 2>/dev/null; then
    log "Push succeeded"
    rm -f "${RETRY_FLAG}"
else
    log "ERROR: Push failed, will retry next run"
    touch "${RETRY_FLAG}"
fi

log "=== Daily push finished ==="
