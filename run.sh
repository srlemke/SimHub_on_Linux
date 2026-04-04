#!/bin/bash

###############################################
# ARGUMENT HANDLING
###############################################
TARGET="$1"

#Ignore python deprecated warning that comes from some apps like
#raceroom dash.exe
export PYTHONWARNINGS="ignore::UserWarning"

#Bellow function prints all the detected game data:
populate_and_print_variables() {

###############################################
# Detect running game AppId
###############################################
game=$(ps -eo args | grep -F "SteamLaunch AppId=" | grep -v grep \
    | sed -n 's/.*AppId=\([0-9]\+\).*/\1/p' | head -1)

if [[ -z "$game" ]]; then
    echo ""
    echo "Game variable is empty, no game running."
    echo "Start a game and run this again."
    echo ""
    read -p "Press ENTER to exit..."
    exit 1
fi

###############################################
# Read game name
###############################################
APP_MANIFEST="$HOME/.steam/steam/steamapps/appmanifest_${game}.acf"

if [[ -f "$APP_MANIFEST" ]]; then
    game_name=$(grep -m1 '"name"' "$APP_MANIFEST" | sed 's/.*"name"[[:space:]]*"\(.*\)".*/\1/')
else
    game_name="Unknown Game"
fi

echo ""
echo "Detected game: $game ($game_name)"
echo ""

###############################################
# SET PROTON USED BY GAME
###############################################
PROTON_VERSION=$(cat "$HOME/.steam/steam/steamapps/compatdata/$game/config_info" \
	|grep pfx |cut -d/ -f7- |sed 's|/files/share/default_pfx/.*||' )
# Extracted path looks like:
# /compatibilitytools.d/GE-Proton10-34-LMU-hid_fixes
# /Steam/steamapps/common/Proton Hotfix
# Others, depending on what Proton is in use.

if [ -z "$PROTON_VERSION" ]; then
    echo "ERROR: Could not detect Proton version from config_info."
    exit 1
fi

PROTON_DIR="$HOME/.steam/steam/$PROTON_VERSION"
PROTON_WINE="$PROTON_DIR/files/bin/wine"

# Set game WINEPREFIX:
export WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/$game/pfx"

#Sometimes the used proton variable is empty, lets make sure to populate it with in use Proton:
export PROTON_VERSION=$(basename "$PROTON_DIR")

# Normalize Proton Experimental naming
if [ "$PROTON_VERSION" = "Proton - Experimental" ]; then
    PROTON_VERSION="Proton Experimental"
fi

# Let the user know what we detected:
echo "Game Details:"
echo PROTON_VERSION: $PROTON_VERSION
echo PROTON_DIR: $PROTON_DIR
echo PROTON_WINE:  $PROTON_WINE
echo WINE_PREFIX: $WINEPREFIX
}

###############################################
# FUNCTIONS
###############################################

launch_simhub() {

###############################################
# Check if SimHub is already running
###############################################
if pgrep -f "SimHubWPF.exe" >/dev/null; then
    echo ""
    echo "⚠️  SimHub is already running."
    echo "Starting another instance may cause issues."
    echo "Close it and run this script again"
    echo ""
    read -p "Press ENTER to exit..."
    exit 1
fi

SIMHUB_EXE="$WINEPREFIX/drive_c/Program Files (x86)/SimHub/SimHubWPF.exe"

if [[ ! -f "$SIMHUB_EXE" ]]; then
    echo "SimHub is not installed for this game."
    echo "To install, close the game and run:"
    echo "sh install.sh simhub"
    echo ""
    exit 1
else
    #Seems all good, lets Print what we detected:
    echo "SIMHUB_EXE:" $SIMHUB_EXE
fi

    #if LMU call dedicated function
    if [[ "$game" = "2399420" ]]; then
        launch_simhub_lmu
    else
        #all other games:
        echo "Launching SimHub..."
        protontricks-launch --appid "$game" "$SIMHUB_EXE" >/dev/null 2>&1 &
    fi

    # if RaceRoom call dash.exe function (for SealHUD)
    if [[ "$game" = "211500" ]]; then
        launch_raceroom_dash
        else
        echo "Done."
    fi

}

###############################################
# LMU SPECIAL HANDLING (2399420)
###############################################

launch_simhub_lmu() {
    LMU_PLUGIN_DIR="$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/Plugins"
    mkdir -p "$LMU_PLUGIN_DIR"

    LMU_PLUGIN1="$LMU_PLUGIN_DIR/rFactor2SharedMemoryMapPlugin64.dll"
    SIMHUB_PLUGIN1="$WINEPREFIX/drive_c/Program Files (x86)/SimHub/_Addons/GamePlugins/RFactor2/Bin64/Plugins/rFactor2SharedMemoryMapPlugin64.dll"

    LMU_PLUGIN2="$LMU_PLUGIN_DIR/LMU_SharedMemoryMapPlugin64.dll"
    LMU_JSON="$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/UserData/player/CustomPluginVariables.JSON"

    NEED_FIX=0

    if [[ ! -f "$LMU_PLUGIN1" ]]; then NEED_FIX=1; fi
    if [[ ! -f "$LMU_PLUGIN2" ]]; then NEED_FIX=1; fi

    if [[ ! -f "$LMU_JSON" ]]; then
        NEED_FIX=1
    else
        if ! grep -A10 '"LMU_SharedMemoryMapPlugin64.dll"' "$LMU_JSON" | grep -q '" Enabled": 1'; then NEED_FIX=1; fi
        if ! grep -A10 '"rFactor2SharedMemoryMapPlugin64.dll"' "$LMU_JSON" | grep -q '" Enabled": 1'; then NEED_FIX=1; fi
    fi

    if [[ "$NEED_FIX" -eq 1 ]]; then
        while true; do
            current_game=$(ps -eo args | grep -F "SteamLaunch AppId=" | grep -v grep \
                | sed -n 's/.*AppId=\([0-9]\+\).*/\1/p' | head -1)

            if [[ "$current_game" != "2399420" ]]; then break; fi

            echo ""
            echo "⚠  Missing telemetry plugins."
            echo "Close LMU to apply fixes."
            echo ""
            read -p "Press ENTER to check again..."
        done
    fi

    FIXES_APPLIED=0

    if [[ "$NEED_FIX" -eq 1 ]]; then
        FIXES_APPLIED=1

        echo ""
        echo "Applying LMU plugin and JSON fixes..."
        echo ""

        if [[ ! -f "$LMU_PLUGIN1" ]]; then
            echo "Installing rFactor2SharedMemoryMapPlugin64.dll..."
            cp "$SIMHUB_PLUGIN1" "$LMU_PLUGIN_DIR/" 2>/dev/null
        fi

        if [[ ! -f "$LMU_PLUGIN2" ]]; then
            echo "Installing LMU_SharedMemoryMapPlugin64.dll..."
            TMP_DIR="$HOME/.cache/lmu_plugin"
            mkdir -p "$TMP_DIR"

            ZIP_URL="https://github.com/tembob64/LMU_SharedMemoryMapPlugin/releases/download/LMU_SharedMemory_Plugin_v4.0.16.7/LMU_SharedMemoryMapPlugin64.zip"
            ZIP_FILE="$TMP_DIR/LMU_SharedMemoryMapPlugin64.zip"

            if command -v wget >/dev/null; then
                wget -q "$ZIP_URL" -O "$ZIP_FILE"
            else
                curl -sL -o "$ZIP_FILE" "$ZIP_URL"
            fi

            unzip -q "$ZIP_FILE" -d "$TMP_DIR"
            mv "$TMP_DIR/LMU_SharedMemoryMapPlugin64.dll" "$LMU_PLUGIN_DIR/" 2>/dev/null
            rm -f "$ZIP_FILE"
        fi

#This is very sensitive, even the blank spaces,
#Dont touch it otherwise LMU owerweites it on restart.
        REQUIRED_JSON='{
  "LMU_SharedMemoryMapPlugin64.dll": {
    " Enabled": 1,
    "DebugISIInternals": 0,
    "DebugOutputLevel": 0,
    "DebugOutputSource": 1,
    "DedicatedServerMapGlobally": 0,
    "EnableDirectMemoryAccess": 0,
    "EnableHWControlInput": 1,
    "EnableRulesControlInput": 0,
    "EnableWeatherControlInput": 0,
    "UnsubscribedBuffersMask": 160
  },
  "rFactor2SharedMemoryMapPlugin64.dll": {
    " Enabled": 1,
    "DebugISIInternals": 0,
    "DebugOutputLevel": 0,
    "DebugOutputSource": 1,
    "DedicatedServerMapGlobally": 0,
    "EnableDirectMemoryAccess": 0,
    "EnableHWControlInput": 1,
    "EnableRulesControlInput": 0,
    "EnableWeatherControlInput": 0,
    "UnsubscribedBuffersMask": 160
  }
}'

        mkdir -p "$(dirname "$LMU_JSON")"
        echo "$REQUIRED_JSON" > "$LMU_JSON"
        echo "✔ CustomPluginVariables.JSON updated."
    fi

    if [[ "$FIXES_APPLIED" -eq 1 ]]; then
        echo ""
        echo "✔ Fixes applied. Start LMU again."
        echo ""
        exit 0
    else
        echo ""
        echo "Launching SimHub with LMU Wine..."
        protontricks-launch --appid "$game" "$SIMHUB_EXE" -switchgame LMU >/dev/null 2>&1 &

        echo ""
        echo "SimHub launched for LMU."
        exit 0
    fi
}

launch_crewchief() {

CC_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe"

if [[ ! -f "$CC_EXE" ]]; then
        echo ""
        echo "CrewChief is not installed for this game."
        echo "To install, close the game and run:"
        echo
        echo "sh install.sh crewchief"
        echo
        exit 1
    else
        #Seems all good, lets Print what we detected:
        echo "CREWCHIEF_EXE:" $CC_EXE
        echo
    fi
        echo "Launching CrewChief..."
        protontricks-launch --appid "$game" "$CC_EXE"
        echo "CrewChief launched."
}

###############################################
# RaceRoom Dash support (AppId 211500)
###############################################
launch_raceroom_dash() {

    echo "RaceRoom Racing Experience detected, launching Dash (For SealHUD)"
    echo ""

    # Check if dash.exe is already running and close
    if pgrep -f "dash.exe" >/dev/null; then
        echo ""
        echo "⚠️  dash.exe still running."
        echo "Closing and starting a new one."
        pkill dash.exe
        echo "Former dash.exe closed"
        echo ""
    fi

    CACHE_DIR="$HOME/.cache/dash"
    mkdir -p "$CACHE_DIR"

    DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)

    if [[ -z "$DASH_EXE" ]]; then
        echo "Downloading Dash..."

        if command -v wget >/dev/null; then
            wget -q "https://sector3studios.github.io/webhud/public/dash.zip" -O "$CACHE_DIR/dash.zip"
        else
            curl -sL -o "$CACHE_DIR/dash.zip" "https://sector3studios.github.io/webhud/public/dash.zip"
        fi

        unzip -q "$CACHE_DIR/dash.zip" -d "$CACHE_DIR"
        rm -f "$CACHE_DIR/dash.zip"

        DASH_EXE=$(find "$CACHE_DIR" -name "dash.exe" -type f 2>/dev/null | head -1)
    fi

    sleep 2
    echo "Running Dash..."

    #dash.exe spits some python and WebSoket Warnings to the terminal, grep -v filters those.
    export PYTHONWARNINGS="ignore::UserWarning"
    protontricks-launch --appid "$game" "$DASH_EXE" 2>&1 \
    | grep -v -i 'fixme\|W:\|WebSocket\|Connection reset by peer'
}


###############################################
# ARGUMENT-BASED LAUNCHER
###############################################
case "$TARGET" in
    simhub)
        populate_and_print_variables
        launch_simhub
        ;;
    crewchief)
        populate_and_print_variables
        launch_crewchief
        ;;
    *)
        echo "Invalid run option, run it like:"
        echo ""
        echo "sh $0 simhub"
        echo "Or:"
        echo "sh $0 crewchief"

        echo ""
        exit 1
        ;;
esac
