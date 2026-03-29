#!/bin/bash

# Check if SimHub is already running
if pgrep -f "SimHubWPF.exe" >/dev/null; then
    echo ""
    echo "⚠  SimHub is already running."
    echo "Starting another instance may cause issues."
    echo ""
    read -p "Press ENTER to exit..."
    exit 1
fi

# Get the running game's AppId
game=$(ps -eo args | grep -F "SteamLaunch AppId=" | grep -v grep \
       | sed -n 's/.*AppId=\([0-9]\+\).*/\1/p' | head -1)

if [[ -z "$game" ]]; then
    echo "Game variable is empty, no game running."
    echo "You should not run this script before running the game,"
    echo "otherwise it will lock the gameprefix and Steam won't be able to start the game."
    echo ""
    read -p "Press ENTER to exit..."
    exit 1
fi

# Try to read the game name from Steam's appmanifest file
APP_MANIFEST="$HOME/.steam/steam/steamapps/appmanifest_${game}.acf"

if [[ -f "$APP_MANIFEST" ]]; then
    game_name=$(grep -m1 '"name"' "$APP_MANIFEST" | sed 's/.*"name"[[:space:]]*"\(.*\)".*/\1/')
else
    game_name="Unknown Game"
fi

echo "Detected game: $game ($game_name)"
echo ""

# Check if SimHub install exists
SIMHUB_EXE="$HOME/.steam/steam/steamapps/compatdata/$game/pfx/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe"

if [[ ! -f "$SIMHUB_EXE" ]]; then
    echo "SimHub is not installed for this game."
    echo "Expected file:"
    echo "  $SIMHUB_EXE"
    echo ""
    read -p "Press ENTER to exit..."
    exit 1
fi

# Special handling for Le Mans Ultimate (2399420) as this is a custom proton.
if [[ "$game" = "2399420" ]]; then
    echo "Le Mans Ultimate detected, launching SimHub using LMU-specific Wine..."
    echo ""

# Check LMU Shared Memory Plugin (LMU_SharedMemoryMapPlugin64.dll)
LMU_PLUGIN2="$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/Plugins/LMU_SharedMemoryMapPlugin64.dll"

if [[ ! -f "$LMU_PLUGIN2" ]]; then
    echo "⚠  LMU Shared Memory Plugin missing!"
    echo "We will Download it from: https://github.com/tembob64/LMU_SharedMemoryMapPlugin/releases"
    read -p "Press ENTER to continue..."
    echo "Attempting to download and install LMU_SharedMemoryMapPlugin64.dll..."
    echo ""

    TMP_DIR="$HOME/.cache/lmu_plugin"
    mkdir -p "$TMP_DIR"

    ZIP_URL="https://github.com/tembob64/LMU_SharedMemoryMapPlugin/releases/download/LMU_SharedMemory_Plugin_v4.0.16.7/LMU_SharedMemoryMapPlugin64.zip"
    ZIP_FILE="$TMP_DIR/LMU_SharedMemoryMapPlugin64.zip"

    # Download plugin
    if command -v wget >/dev/null; then
        wget -q "$ZIP_URL" -O "$ZIP_FILE"
    elif command -v curl >/dev/null; then
        curl -sL -o "$ZIP_FILE" "$ZIP_URL"
    else
        echo "Error: wget or curl not found! Cannot download plugin."
        read -p "Press ENTER to continue..."
    fi

    # Extract plugin
    if [[ -f "$ZIP_FILE" ]]; then
        if command -v unzip >/dev/null; then
            unzip -q "$ZIP_FILE" -d "$TMP_DIR"
        else
            echo "Error: unzip not found! Cannot extract plugin."
            read -p "Press ENTER to continue..."
        fi
    fi

    # Move plugin into LMU Plugins folder
    if [[ -f "$TMP_DIR/LMU_SharedMemoryMapPlugin64.dll" ]]; then
        mv "$TMP_DIR/LMU_SharedMemoryMapPlugin64.dll" "$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/Plugins/"
        echo "✔ LMU Shared Memory Plugin installed successfully."
        echo "✔ You need to restart the game so it detects the new plugin."
            read -p "Press ENTER to continue..."
    else
        echo "❌ Failed to extract LMU_SharedMemoryMapPlugin64.dll!"
        echo "SimHub may not receive full telemetry."
        read -p "Press ENTER to continue..."
    fi

    rm -f "$ZIP_FILE"
fi

# Check LMU telemetry plugin (rFactor2SharedMemoryMapPlugin64.dll)
LMU_PLUGIN1="$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/Plugins/rFactor2SharedMemoryMapPlugin64.dll"
SIMHUB_PLUGIN1="$HOME/.steam/steam/steamapps/compatdata/2399420/pfx/drive_c/Program Files (x86)/SimHub/_Addons/GamePlugins/RFactor2/Bin64/Plugins/rFactor2SharedMemoryMapPlugin64.dll"

if [[ ! -f "$LMU_PLUGIN1" ]]; then
    echo ""
    echo "rFactor2SharedMemoryMapPlugin64.dll missing in LMU Plugins folder."
    echo "Attempting to copy from SimHub installation..."

    if [[ -f "$SIMHUB_PLUGIN1" ]]; then
        cp "$SIMHUB_PLUGIN1" "$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/Plugins/"
        echo "✔ Plugin installed successfully."
        echo "✔ You need to restart the game so it detects the new plugin."
            read -p "Press ENTER to continue..."
    else
        echo "❌ Plugin not found in SimHub installation:"
        echo "  $SIMHUB_PLUGIN1"
        echo "SimHub telemetry may not work."
    fi
fi

# Auto-detect LMU Proton build
    CUSTOM_WINE_DIR=$(find "$HOME/.steam/steam/compatibilitytools.d" \
        -maxdepth 1 \
        -type d \
        -name "GE-Proton*-lmu*" \
        | head -1)

    if [[ -z "$CUSTOM_WINE_DIR" ]]; then
        echo "Error: No LMU-specific GE-Proton build found in compatibilitytools.d"
        read -p "Press ENTER to exit..."
        exit 1
    fi

    CUSTOM_WINE="$CUSTOM_WINE_DIR/files/bin/wine"
    WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/$game/pfx"
    SIMHUB_EXE="$WINEPREFIX/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe"

    # Validate Wine binary
    if [[ ! -x "$CUSTOM_WINE" ]]; then
        echo "Error: Wine binary not found or not executable:"
        echo "  $CUSTOM_WINE"
        read -p "Press ENTER to exit..."
        exit 1
    fi

    # Validate SimHub
    if [[ ! -f "$SIMHUB_EXE" ]]; then
        echo "Error: SimHubWPF.exe not found for LMU."
        echo "Expected:"
        echo "  $SIMHUB_EXE"
        read -p "Press ENTER to exit..."
        exit 1
    fi

    # Launch SimHub using LMU's Wine
    echo "Launching SimHub with LMU Wine..."
    WINEPREFIX="$WINEPREFIX" "$CUSTOM_WINE" "$SIMHUB_EXE" >/dev/null 2>&1 &

    echo ""
    echo "SimHub launched for LMU."
    echo "Done!"
    exit 0
fi

# Launch SimHub
echo "Launching SimHub..."
export PYTHONWARNINGS="ignore::UserWarning"
protontricks-launch --appid "$game" "$SIMHUB_EXE" >/dev/null 2>&1 &

# Run dash.exe only if game is RaceRoom (211500)
if [[ "$game" = "211500" ]]; then
    echo "RaceRoom Racing Experience detected, launching Dash..."
    echo ""

    CACHE_DIR="$HOME/.cache/dash"
    mkdir -p "$CACHE_DIR"

    DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)

    if [[ -z "$DASH_EXE" ]]; then
        echo "Downloading Dash..."

        if command -v wget >/dev/null; then
            wget -q "https://sector3studios.github.io/webhud/public/dash.zip" -O "$CACHE_DIR/dash.zip"
        elif command -v curl >/dev/null; then
            curl -sL -o "$CACHE_DIR/dash.zip" "https://sector3studios.github.io/webhud/public/dash.zip"
        else
            echo "Error: wget or curl not found!"
            exit 1
        fi

        if [[ ! -f "$CACHE_DIR/dash.zip" ]]; then
            echo "Error: Failed to download dash.zip!"
            exit 1
        fi

        echo "Extracting Dash..."
        if command -v unzip >/dev/null; then
            unzip -q "$CACHE_DIR/dash.zip" -d "$CACHE_DIR"
            rm -f "$CACHE_DIR/dash.zip"
        else
            echo "Error: unzip not found!"
            exit 1
        fi

        DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)
        if [[ -z "$DASH_EXE" ]]; then
            echo "Error: dash.exe not found in extracted files!"
            exit 1
        fi
    else
        echo "Using cached Dash..."
    fi

    sleep 2

    echo "Running Dash..."
    protontricks-launch --appid "$game" "$DASH_EXE" 2>&1 | grep -v -i 'fixme\|W:'
else
    echo "SimHub has been launched."
fi

echo ""
echo "Done!"
