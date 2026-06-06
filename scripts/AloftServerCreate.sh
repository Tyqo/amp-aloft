#!/usr/bin/env bash

set -euo pipefail

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Display intro banner
echo -e "${GREEN}"
echo "  █████╗ ██╗      ██████╗ ███████╗████████╗"
echo " ██╔══██╗██║     ██╔═══██╗██╔════╝╚══██╔══╝"
echo " ███████║██║     ██║   ██║█████╗     ██║   "
echo " ██╔══██║██║     ██║   ██║██╔══╝     ██║   "
echo " ██║  ██║███████╗╚██████╔╝██║        ██║   "
echo " ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝        ╚═╝   "
echo " Dedicated Server Setup for Proxmox LXC"
echo -e "${NC}"

# Load configuration

cd /mnt/b51fcf81-a1a4-460d-bdef-08cf50523b31/SteamLibrary/steamapps/common/Aloft
BUFFER_SIZE=15

LOG_FILE="output.txt"

WINE_PREFIX="/opt/aloft_server/wineprefix"

export WINEDEBUG=-all
export WINEPREFIX=$WINE_PREFIX

# Configure Wine prefix
log "Setting up Wine prefix"
WINEPREFIX=$WINE_PREFIX WINEARCH=win64 wineboot -u
# WINEPREFIX=$WINE_PREFIX winetricks -q vcrun2019 dotnet48 dxvk

ARGS=(
    -batchmode
    -nographics
    -server
    create#LinuxWorld#
    islandcount#normal#
    corruptioncount#normal#
    creative#false#
    log#ERROR#
    disablevideo#true#
)

# Backup existing log file
if [[ -f "$LOG_FILE" ]]; then
    timestamp=$(date +"%Y%m%d_%H%M%S")
    mv "$LOG_FILE" "output_${timestamp}.txt"
fi

declare -a log_buffer=()

flush_log_buffer() {
    if (( ${#log_buffer[@]} > 0 )); then
        printf '%s\n' "${log_buffer[@]}" >> "$LOG_FILE"
        log_buffer=()
    fi
}

cleanup() {
    flush_log_buffer

    # Terminate the Wine process group
    if [[ -n "${wine_pid:-}" ]]; then
        kill -- -"$wine_pid" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

# Start Aloft under Wine in its own process group
setsid wine ./Aloft.exe "${ARGS[@]}" 2>&1 | tee -a output.txt
while IFS= read -r line; do

    if [[ "$line" == \#* ]]; then
        log_buffer+=("$line")

        # Display without leading '#'
        echo "${line:1}"
    fi

    if (( ${#log_buffer[@]} >= BUFFER_SIZE )); then
        flush_log_buffer
    fi

done &

wine_pid=$!

wait "$wine_pid"

flush_log_buffer
