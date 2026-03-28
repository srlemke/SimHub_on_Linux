#!/bin/bash

# Get the running game's AppId
game=$(ps -aux | grep SteamLaunch | grep -oP 'AppId=\K\d+')

if [[ -z "$game" ]]; then
    echo "Game variable is empty, no game running."
    echo "You should not run this script before running the game,"
    echo "otherwise it will lock the gameprefix and Steam won't be able to start the game."
    echo ""
    read -p "Press ENTER to exit..."
    exit 1
fi

echo "Detected game: $game"
echo ""

# Launch SimHub that is installed within game prefix
echo "Launching SimHub..."
export PYTHONWARNINGS="ignore::UserWarning"
protontricks-launch --appid "$game" ~/.steam/steam/steamapps/compatdata/"$game"/pfx/drive_c/"Program Files (x86)"/SimHub/SimHubWPF.exe > /dev/null 2>&1 &

# Run dash.exe only if game is RaceRoom (211500)
if [ "$game" = "211500" ]; then
    echo "RaceRoom Racing Experience detected, launching Dash..."
    echo ""
    
    # Create cache directory for dash
    CACHE_DIR="$HOME/.cache/dash"
    mkdir -p "$CACHE_DIR"
    
    # Check if dash.exe already exists in cache
    DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)
    
    if [ -z "$DASH_EXE" ]; then
        # dash.exe not found, need to download and extract
        echo "Downloading Dash..."
        if which wget > /dev/null 2>&1; then
            wget -q "https://sector3studios.github.io/webhud/public/dash.zip" -O "$CACHE_DIR/dash.zip"
        elif which curl > /dev/null 2>&1; then
            curl -sL -o "$CACHE_DIR/dash.zip" "https://sector3studios.github.io/webhud/public/dash.zip"
        else
            echo "Error: wget or curl not found!"
            exit 1
        fi
        
        # Check if download was successful
        if [ ! -f "$CACHE_DIR/dash.zip" ]; then
            echo "Error: Failed to download dash.zip!"
            exit 1
        fi
        
        # Extract dash
        echo "Extracting Dash..."
        if which unzip > /dev/null 2>&1; then
            unzip -q "$CACHE_DIR/dash.zip" -d "$CACHE_DIR"
        else
            echo "Error: unzip not found!"
            exit 1
        fi
        
        # Find dash.exe after extraction
        DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)
        if [ -z "$DASH_EXE" ]; then
            echo "Error: dash.exe not found in extracted files!"
            exit 1
        fi
    else
        echo "Using cached Dash..."
    fi
    
    sleep 2
    
    # Run dash
    echo "Running Dash..."
    protontricks-launch --appid "$game" "$DASH_EXE" 2>&1 | grep -v -i 'fixme\|W:'
else
    echo "SimHub has been launched."
fi

echo ""
echo "Done!"
