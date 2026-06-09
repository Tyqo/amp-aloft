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
LOG_LEVEL="ERROR"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --servername) SERVER_NAME="$2"; shift ;;
        --mapname) MAP_NAME="$2"; shift ;;
        --islands) ISLAND_COUNT="$2"; shift ;;
        --creative) GAME_MODE="$2"; shift ;;
        --visible) IS_VISIBLE="$2"; shift ;;
        --port) SERVER_PORT="$2"; shift ;;
        --admin) ADMIN="$2"; shift ;;
        --playercount) PLAYER_COUNT="$2"; shift ;;
        *) shift ;;
    esac
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

# Define an instance-safe local tmp directory
LOCAL_TMP="$GAME_DIR/.tmp"
mkdir -p "$LOCAL_TMP"

export XDG_RUNTIME_DIR="$LOCAL_TMP/runntime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# ==========================================
# ENVIRONMENT VARIABLES & WINE CONFIG
# ==========================================
export WINEPREFIX="$WINE_PREFIX_DIR"
export WINEARCH="$WINE_ARCH"
export WINEDEBUG="-all,fixme-all" # Silences heavy Wine debug spam for performance
export GST_DEBUG=0

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

    pkill -f "Xvfb :99" || true

    # Give Wine up to 5 seconds to flush save data to disk
    sleep 3
    exit 0
}

trap shutdown_handler SIGINT SIGTERM

# Initialize Wine prefix if it doesn't exist
if [ ! -d "$WINEPREFIX" ]; then
    echo "Creating isolated 64-bit Wine prefix..."
    wineboot -u
fi

# Set Wine to Windows 10 mode silently via registry override
# wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f

rm -f $LOCAL_TMP/.X99-lock
rm -f $LOCAL_TMP/.X11-unix/X99

# ==========================================
# VIRTUAL DISPLAY SETUP (Crucial for Unity)
# ==========================================
if ! pgrep -x "Xvfb" > /dev/null; then
    echo "Starting virtual frame buffer (Xvfb) on :99..."
    # Xvfb :99 -screen 0 1024x768x16 &
    Xvfb :99 -fbdir "$LOCAL_TMP" -screen 0 1024x768x16 -nolisten tcp &
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

    ln -s "$WINE_SAVE_DIR" "$GAME_DIR/Data06"
else
    echo "Symlink is set"
fi

# ==========================================
# RUNNING THE SERVER
# ==========================================
echo "Starting Aloft Dedicated Server..."
echo "-----------------------------------------------"

# Check if the map already exists. If not, generate a new one.
if [ ! -d "$SAVE_PATH" ]; then
    echo "World file not found at: $SAVE_PATH"
    echo "Initializing NEW world creation configuration..."
    CREATE_ARGS="-batchmode -nographics -server create#${MAP_NAME}# islandcount#${ISLAND_COUNT}# corruptioncount#normal# creative#${GAME_MODE}# log#${LOG_LEVEL}# disablevideo#true#"
    echo "This can take a minute or two..."
    echo "Runnig: $EXE_NAME $CREATE_ARGS"
    wine "$EXE_NAME" $CREATE_ARGS > /dev/null 2>$CREATE_LOG &
    CREATE_PID=$!

    # Wait for the creation phase to finish cleanly before proceeding
    wait $CREATE_PID
    echo "World generation complete."
    sleep 5
fi

echo "World $MAP_NAME found. Setting server to LOAD mode."
echo "This can take a minute..."
LAUNCH_ARGS="-batchmode -nographics -server load#${MAP_NAME}# servername#${SERVER_NAME}# isvisible#${IS_VISIBLE}# playercount#${PLAYER_COUNT}# serverport#${SERVER_PORT}# admin#-1# admin#-2# log#${LOG_LEVEL}# disablevideo#true#"
# wine "$EXE_NAME" $LAUNCH_ARGS 2>$LOAD_LOG &
# wine "$EXE_NAME" $LAUNCH_ARGS 2>/dev/null &
echo "Runnig: $EXE_NAME $LAUNCH_ARGS"

(
wine "$EXE_NAME" $LAUNCH_ARGS 2>&1 | while IFS= read -r line; do
	    # Check if the line contains "Player joined:" or "Player left:"
	    if [[ "$line" == *"Player joined:"* ]] || [[ "$line" == *"Player left:"* ]]; then
	        # Echo it cleanly to the console so AMP can parse it via your Regex filters
	        echo "$line"
	    fi

	    if [[ "$line" == *"Room Code"* ]]; then
	        # Echo it cleanly to the console so AMP can parse it via your Regex filters
	        echo "========================================================="
	        echo "   [ALOFT JOIN CODE]: $line"
	        echo "========================================================="
	    fi
    done
) &

# Capture the loop wrapper PID so the shutdown handler can destroy it if needed
LOOP_PID=$!

# Wait natively on the loop. When Wine exits, the loop ends, and the script finishes.
# If AMP hits 'Stop', the trap triggers, kills everything, and overrides this wait.
wait $LOOP_PID
