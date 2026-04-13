#!/bin/sh

#SimHUB Version that will be downloaded
version=9.11.10

# Check for required tools
echo "Checking for required tools..."
missing_tools=0

if ! command -v protontricks >/dev/null 2>&1; then
    echo "WARNING: protontricks is not installed"
    missing_tools=1
fi

if ! command -v winetricks >/dev/null 2>&1; then
    echo "WARNING: winetricks is not installed"
    missing_tools=1
fi

if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    echo "WARNING: wget or curl is not installed (needed for downloads)"
    missing_tools=1
fi

if [ $missing_tools -eq 1 ]; then
    echo
    printf "Continue anyway? (y/N): "
    read -r reply
    echo
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        exit 1
    fi
fi

# Steam directory
STEAM_DIR="$HOME/.steam/steam/steamapps"

# Parse manifest files and extract game info
echo "Scanning for installed games..."
index=0

for manifest in "$STEAM_DIR"/appmanifest_*.acf; do
    if [ -f "$manifest" ]; then
        # Extract app ID from filename (appmanifest_XXXXX.acf)
        app_id=$(basename "$manifest" | sed 's/appmanifest_//;s/.acf//')
        
        # Extract game name from manifest file
        game_name=$(grep -m1 '"name"' "$manifest" | awk -F'"' '{print $4}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Filter out entries containing Steam or Proton
        if echo "$game_name" | grep -qi "Steam\|Proton"; then
            continue
        fi

        # Index:
        if [ -n "$game_name" ]; then
            # Store in temporary file instead of arrays (more portable)
            echo "$app_id|$game_name" >> /tmp/steam_games_$$
            index=$((index + 1))
        fi
    fi
done

# Check if any games were indexed:
if [ $index -eq 0 ]; then
    echo "No games found in Steam directory."
    echo
    echo "NOTE: If your game is not listed, you need to run it at least once"
    echo "and close it. This creates the necessary Proton/Wine prefix files."
    echo
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display menu
echo
echo "=== Available Games ==="
awk -F'|' '{print NR-1 "] " $1 " - " $2}' /tmp/steam_games_$$

echo
echo "NOTE: If your game is not listed, you need to run it at least once"
echo "and close it. This creates the necessary Proton/Wine prefix files."
echo

# Get user selection
printf "Select a game (0-$((index - 1))): "
read -r selection

# Validate selection
if ! [ "$selection" -ge 0 ] 2>/dev/null || [ "$selection" -ge "$index" ]; then
    echo "Invalid selection, closing."
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display selected game
selected_line
