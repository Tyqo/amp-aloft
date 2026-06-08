#!/bin/bash
# Set script to exit on error
set -e

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
echo -e "${NC}"


# ==========================================
# CONFIGURATION
# ==========================================
# Wine Environment Settings
WINE_ARCH="win64"

# Aloft Game Server Settings
MAP_NAME="AloftWorld"
SERVER_NAME="AloftServer"
PLAYER_COUNT="8"
IS_VISIBLE="true" # "true" for public server browser, "false" for private
SERVER_PORT="0"

# World Generation Parameters (Used only if creating a new world)
# Game Modes: 0 = Survival, 1 = Creative, 2 = Custom
ISLAND_COUNT="300"
GAME_MODE="0"

while [[ "$#" -gt 0 ]]; do
    case $1 in
    	--servername) SERVER_NAME="$2"; shift ;;
		--mapname) MAP_NAME="$2"; shift ;;
		--islands) ISLAND_COUNT="$2"; shift ;;
		--creative) GAME_MODE="$2"; shift ;;
		--visible) IS_VISIBLE="$2"; shift ;;
		--port) SERVER_PORT="$2"; shift ;;
		--admin) ADMIN="$2"; shift ;;
		--log) LOG_LEVEL="$2"; shift ;;
		--playercount) PLAYER_COUNT="$2"; shift ;;
    esac
    shift
done

# Ensure strict styling matches Aloft guidelines (strip accidental spaces)
SERVER_NAME=$(echo "$SERVER_NAME" | tr -d ' ')
MAP_NAME=$(echo "$MAP_NAME" | tr -d ' ')

# Directories Context
EXE_NAME="Aloft.exe"
GAME_DIR="/AMP/aloft/1660080"
WINE_PREFIX_DIR="/AMP/aloft/.wine"
WINE_SAVE_DIR="$WINE_PREFIX_DIR/drive_c/users/AppData/LocalLow/Astrolabe Interactive/Aloft/Data06"
SAVE_PATH="$WINE_SAVE_DIR/Saves/w_$MAP_NAME/"
ROOM_CODE_FILE="$GAME_DIR/ServerRoomCode.txt"
CREATE_LOG="$GAME_DIR/CreateServer.log"
LOAD_LOG="$GAME_DIR/LoadServer.log"

# ==========================================
# ENVIRONMENT VARIABLES & WINE CONFIG
# ==========================================
export WINEPREFIX="$WINE_PREFIX_DIR"
export WINEARCH="$WINE_ARCH"
export WINEDEBUG="-all,fixme-all" # Silences heavy Wine debug spam for performance

# Force Unity to use headless, dummy drivers under Wine
export UNITY_DISABLE_GRAPHICS=1
export FORCE_AUDIO_VDMA=1
export USER=$GAME_USER
export USERNAME=$GAME_USER

# Ensure any stale, previous room codes are cleared before launching
rm -f "$ROOM_CODE_FILE"
rm -f "$LOAD_LOG"
rm -f "$CREATE_LOG"

touch $LOAD_LOG
touch $CREATE_LOG

# ==========================================
# GRACEFUL SHUTDOWN (SIGINT TRAP)
# ==========================================
shutdown_handler() {
    echo "========================================================="
    echo "   [AMP AUTOMATION]: SIGINT Received! Shutting down..."
    echo "   Killing Wine environment processes gracefully..."
    echo "========================================================="

    # wineserver -k sends a clean termination signal to all running exes in this prefix
    /usr/bin/wineserver -k

    # Give Wine up to 5 seconds to flush save data to disk
    sleep 3
    exit 0
}

# Initialize Wine prefix if it doesn't exist
if [ ! -d "$WINEPREFIX" ]; then
    echo "Creating isolated 64-bit Wine prefix..."
    wineboot -u
fi

# Set Wine to Windows 10 mode silently via registry override
wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

# ==========================================
# VIRTUAL DISPLAY SETUP (Crucial for Unity)
# ==========================================
if ! pgrep -x "Xvfb" > /dev/null; then
    echo "Starting virtual frame buffer (Xvfb) on :1..."
    Xvfb :99 -screen 0 1024x768x16 &
    sleep 2
fi
export DISPLAY=:99

# ==========================================
# WORLD CHECK & LAUNCH ARGUMENTS
# ==========================================
cd "$GAME_DIR" || { echo "Error: Game directory not found."; exit 1; }

# Target path where Aloft saves worlds inside the Wine prefix environment
# Note: Wine maps the Windows AppData path to your user profile directory
if [ ! -d "$WINE_SAVE_DIR" ]; then
    echo "setting up symlink"
    mkdir -p "$WINE_SAVE_DIR"

    echo "$WINE_SAVE_DIR"
    echo "$GAME_DIR/Data06/"

    ln -s "$WINE_SAVE_DIR/" "Data06"
else
    echo "Symlink is set"
fi

# ==========================================
# BACKGROUND ROOM CODE MONITOR (AMP CONSOLE HOOK)
# ==========================================
# This loops safely in the background waiting for Aloft to write the join key
(
    # Timeout after 3 minutes just in case the server crashes or stalls
    for i in {1..36}; do
        if [ -f "$ROOM_CODE_FILE" ] && [ -s "$ROOM_CODE_FILE" ]; then
            ROOM_CODE=$(cat "$ROOM_CODE_FILE")
            echo "========================================================="
            echo "   [ALOFT JOIN CODE]: $ROOM_CODE"
            echo "========================================================="
            break
        fi
        sleep 5
    done
) &

# ==========================================
# RUNNING THE SERVER
# ==========================================
echo "Starting Aloft Dedicated Server..."
echo "-----------------------------------------------"

# Check if the map already exists. If not, generate a new one.
if [ ! -d "$SAVE_PATH" ]; then
    echo "World file not found at: $SAVE_PATH"
    echo "Initializing NEW world creation configuration..."
    CREATE_ARGS="-batchmode -nographics -server  create#${MAP_NAME}# islandcount#${ISLAND_COUNT}# corruptioncount#normal# creative#${GAME_MODE}# log#ERROR# disablevideo#true#"
    wine "$EXE_NAME" $CREATE_ARGS &>$CREATE_LOG
    echo "Initializing NEW world creation configuration..."
fi

echo "World $MAP_NAME found. Setting server to LOAD mode."
LAUNCH_ARGS="-batchmode -nographics \
        -server load#${MAP_NAME}# servername#${SERVER_NAME}# isvisible#${IS_VISIBLE}# playercount#${PLAYER_COUNT}# serverport#${SERVER_PORT}# admin#-1# admin#-2# log#ERROR# disablevideo#true#"
wine "$EXE_NAME" $LAUNCH_ARGS 2>$LOAD_LOG &

# Store the Wine process ID and wait on it natively
WINE_PID=$!
wait $WINE_PID
