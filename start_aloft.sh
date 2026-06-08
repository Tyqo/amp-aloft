#!/bin/bash

# ==========================================
# CONFIGURATION
# ==========================================
GAME_DIR="/AMP/aloft/1660080/"
EXE_NAME="Aloft.exe" # Change to the exact case-sensitive .exe name if needed
GAME_USER="amp"

# Wine Environment Settings
WINE_PREFIX_DIR="/AMP/aloft/.wine"
WINE_ARCH="win64"

# Aloft Game Server Settings
MAP_NAME="Narnia"
SERVER_NAME="My Linux Aloft Server"
PLAYER_COUNT="8"
IS_VISIBLE="true" # "true" for public server browser, "false" for private
SERVER_PORT="0"

# World Generation Parameters (Used only if creating a new world)
# Format: create#[Name]#[IslandCount]#[GameMode]#
# Game Modes: 0 = Survival, 1 = Creative, 2 = Custom
ISLAND_COUNT="300"
GAME_MODE="0"

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


# Initialize Wine prefix if it doesn't exist
if [ ! -d "$WINEPREFIX" ]; then
    echo "Creating isolated 64-bit Wine prefix..."
    wineboot -u
    # Set Wine to Windows 10 mode silently via registry override
    wine reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
fi

# ==========================================
# VIRTUAL DISPLAY SETUP (Crucial for Unity)
# ==========================================
if ! pgrep -x "Xvfb" > /dev/null; then
    echo "Starting virtual frame buffer (Xvfb) on :99..."
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
WORLD_FILE_PATH="$WINE_PREFIX_DIR/drive_c/users/$GAME_USER/AppData/LocalLow/Astrolabe Interactive/Aloft/Data06/Saves"

if [ ! -d "$WORLD_FILE_PATH" ]; then
    echo "setting up symlink"
    mkdir -p "$WORLD_FILE_PATH"
    mkdir -p "$GAME_DIR/Data06/Saves"

    echo "$WORLD_FILE_PATH"
    echo "$GAME_DIR/Data06/Saves"

    ln -s "$WORLD_FILE_PATH" "$GAME_DIR/Data06/Saves"
else
    echo "Symlink is set"
fi

# ==========================================
# RUNNING THE SERVER
# ==========================================
echo "Starting Aloft Dedicated Server..."
echo "-----------------------------------------------"

SAVE_PATH="$WORLD_FILE_PATH/w_$MAP_NAME/"
# Check if the map already exists. If not, generate a new one.
if [ ! -d "$SAVE_PATH" ]; then
    echo "World file not found at: $SAVE_PATH"
    echo "Initializing NEW world creation configuration..."
    LAUNCH_ARGS="-batchmode -nographics -server  create#${MAP_NAME}# islandcount#${ISLAND_COUNT}# corruptioncount#normal# creative#${GAME_MODE}# log#ERROR# disablevideo#true#"
    wine "$EXE_NAME" $LAUNCH_ARGS
else
    echo "Existing world found. Setting server to LOAD mode."
    LAUNCH_ARGS="-batchmode -nographics \
            -server load#${MAP_NAME}# servername#${SERVER_NAME}# isvisible#${IS_VISIBLE}# playercount#${PLAYER_COUNT}# serverport#${SERVER_PORT}# admin#-1# admin#-2# log#ERROR# disablevideo#true#"
    wine "$EXE_NAME" $LAUNCH_ARGS
fi
