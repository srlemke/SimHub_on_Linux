#!/bin/bash

# Check if SimHub is already running
if pgrep -f "SimHubWPF.exe" >/dev/null; then
	echo ""
	echo "⚠️  SimHub is already running."
	echo "Starting another instance may cause issues."
	echo ""
	read -p "Press ENTER to exit..."
	exit 1
fi

# Get the running game's AppId
game=$(ps -eo args | grep -F "SteamLaunch AppId=" | grep -v grep \
	| sed -n 's/.*AppId=\([0-9]\+\).*/\1/p' | head -1)

if [[ -z "$game" ]]; then
	echo ""
	echo "Game variable is empty, no game running."
	echo "Start the game and run this again."
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
	echo "You need to run the install script again while this game is open."
	echo "Expected file:"
	echo "  $SIMHUB_EXE"
	echo ""
	read -p "Press ENTER to exit..."
	exit 1
fi

# Special handling for Le Mans Ultimate (2399420) as this is a custom proton.
if [[ "$game" = "2399420" ]]; then
	echo "Le Mans Ultimate detected, launching SimHub using LMU-specific Proton..."

# Auto-detect LMU Proton build
CUSTOM_WINE_DIR=$(find "$HOME/.steam/steam/compatibilitytools.d" \
-maxdepth 1 \
-type d \
-iname "GE-Proton*LMU*" | head -1)	

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

    LMU_PLUGIN_DIR="$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/Plugins"
    mkdir -p "$LMU_PLUGIN_DIR"

    LMU_PLUGIN1="$LMU_PLUGIN_DIR/rFactor2SharedMemoryMapPlugin64.dll"
    SIMHUB_PLUGIN1="$WINEPREFIX/drive_c/Program Files (x86)/SimHub/_Addons/GamePlugins/RFactor2/Bin64/Plugins/rFactor2SharedMemoryMapPlugin64.dll"

    LMU_PLUGIN2="$LMU_PLUGIN_DIR/LMU_SharedMemoryMapPlugin64.dll"

    LMU_JSON="$HOME/.steam/steam/steamapps/common/Le Mans Ultimate/UserData/player/CustomPluginVariables.JSON"

    ###############################################
    # Determine if LMU needs plugin or JSON fixes #
    ###############################################

    NEED_FIX=0

    # Check plugin 1
    if [[ ! -f "$LMU_PLUGIN1" ]]; then
	    NEED_FIX=1
    fi

    # Check plugin 2
    if [[ ! -f "$LMU_PLUGIN2" ]]; then
	    NEED_FIX=1
    fi

# Check JSON correctness
if [[ ! -f "$LMU_JSON" ]]; then
	NEED_FIX=1
else
	# LMU plugin must have Enabled = 1
	if ! grep -A15 '"LMU_SharedMemoryMapPlugin64.dll"' "$LMU_JSON" | grep -q '" Enabled": 1'; then
		NEED_FIX=1
	fi

    # rFactor2 plugin must have Enabled = 1
    if ! grep -A15 '"rFactor2SharedMemoryMapPlugin64.dll"' "$LMU_JSON" | grep -q '" Enabled": 1'; then
	    NEED_FIX=1
    fi
fi

    #########################################################
    # If fixes are needed AND LMU is running → ask to close #
    #########################################################

    if [[ "$NEED_FIX" -eq 1 ]]; then
	    while true; do
		    current_game=$(ps -eo args | grep -F "SteamLaunch AppId=" | grep -v grep \
			    | sed -n 's/.*AppId=\([0-9]\+\).*/\1/p' | head -1)

		    if [[ "$current_game" != "2399420" ]]; then
			    break
		    fi

		    echo ""
		    echo "⚠  You have missing telemetry plugins."
		    echo "LMU must be closed before we can add the missing plugins."
		    echo "This is only only needed on the first run. You can run the game normally afterwards."
		    echo ""
		    read -p "Close LMU and press ENTER to check again..."
	    done
    fi

    ###############################################
    # Apply fixes if needed                       #
    ###############################################

    FIXES_APPLIED=0

    if [[ "$NEED_FIX" -eq 1 ]]; then
	    FIXES_APPLIED=1

	    echo ""
	    echo "Applying LMU plugin and JSON fixes..."
	    echo ""

	# Install plugin 1
	if [[ ! -f "$LMU_PLUGIN1" ]]; then
		echo "Installing rFactor2SharedMemoryMapPlugin64.dll..."
		if [[ -f "$SIMHUB_PLUGIN1" ]]; then
			cp "$SIMHUB_PLUGIN1" "$LMU_PLUGIN_DIR/"
			echo "✔ Installed rFactor2SharedMemoryMapPlugin64.dll"
		else
			echo "❌ Missing plugin in SimHub installation:"
			echo "  $SIMHUB_PLUGIN1"
		fi
	fi

	# Install plugin 2
	if [[ ! -f "$LMU_PLUGIN2" ]]; then
		echo "Installing LMU_SharedMemoryMapPlugin64.dll..."

		TMP_DIR="$HOME/.cache/lmu_plugin"
		mkdir -p "$TMP_DIR"

		ZIP_URL="https://github.com/tembob64/LMU_SharedMemoryMapPlugin/releases/download/LMU_SharedMemory_Plugin_v4.0.16.7/LMU_SharedMemoryMapPlugin64.zip"
		ZIP_FILE="$TMP_DIR/LMU_SharedMemoryMapPlugin64.zip"

		if command -v wget >/dev/null; then
			wget -q "$ZIP_URL" -O "$ZIP_FILE"
		elif command -v curl >/dev/null; then
			curl -sL -o "$ZIP_FILE" "$ZIP_URL"
		fi

		if [[ -f "$ZIP_FILE" ]]; then
			unzip -q "$ZIP_FILE" -d "$TMP_DIR"
		fi

		if [[ -f "$TMP_DIR/LMU_SharedMemoryMapPlugin64.dll" ]]; then
			mv "$TMP_DIR/LMU_SharedMemoryMapPlugin64.dll" "$LMU_PLUGIN_DIR/"
			echo "✔ Installed LMU_SharedMemoryMapPlugin64.dll"
		else
			echo "❌ Failed to extract LMU_SharedMemoryMapPlugin64.dll"
		fi

		rm -f "$ZIP_FILE"
	fi

	# Write JSON
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

    ###############################################
    # Decide whether to launch SimHub             #
    ###############################################

    if [[ "$FIXES_APPLIED" -eq 1 ]]; then
	    echo ""
	    echo "✔ Fixes applied successfully."
	    echo "You can now start Le Mans Ultimate again and once it started run this script, all should be good."
	    echo ""
	    exit 0
    else
	    echo ""
	    echo "Launching SimHub with LMU Wine..."
	    WINEPREFIX="$WINEPREFIX" "$CUSTOM_WINE" "$SIMHUB_EXE" >/dev/null 2>&1 &
	    echo ""
	    echo "SimHub launched for LMU."
	    echo "Done!"
	    exit 0
    fi
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

