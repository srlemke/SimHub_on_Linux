#!/bin/sh

# Check for required tools
echo "Checking for required tools..."
missing_tools=0

if ! which protontricks > /dev/null 2>&1; then
    echo "WARNING: protontricks is not installed"
    missing_tools=1
fi

if ! which winetricks > /dev/null 2>&1; then
    echo "WARNING: winetricks is not installed"
    missing_tools=1
fi

if ! which wget > /dev/null 2>&1 && ! which curl > /dev/null 2>&1; then
    echo "WARNING: wget or curl is not installed (needed for downloads)"
    missing_tools=1
fi

if [ $missing_tools -eq 1 ]; then
    echo ""
    printf "Continue anyway? (y/n): "
    read -r reply
    echo
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        exit 1
    fi
fi

echo ""

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
        
        if [ -n "$game_name" ]; then
            # Store in temporary file instead of arrays (more portable)
            echo "$app_id|$game_name" >> /tmp/steam_games_$$
            index=$((index + 1))
        fi
    fi
done

# Check if any games were found
if [ $index -eq 0 ]; then
    echo "No games found in Steam directory."
    echo ""
    echo "NOTE: If your game is not listed, you need to run it at least once"
    echo "and close it. This creates the necessary Proton/Wine prefix files."
    echo ""
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display menu
echo ""
echo "=== Available Games ==="
awk -F'|' '{print NR-1 "] " $1 " - " $2}' /tmp/steam_games_$$

echo ""
echo "NOTE: If your game is not listed, you need to run it at least once"
echo "and close it. This creates the necessary Proton/Wine prefix files."
echo ""

# Get user selection
printf "Select a game (0-$((index - 1))): "
read -r selection
echo

# Validate selection
if ! [ "$selection" -ge 0 ] 2>/dev/null || [ "$selection" -ge "$index" ]; then
    echo "Invalid selection."
    rm -f /tmp/steam_games_$$
    exit 1
fi

# Display selected game
selected_line=$(sed -n "$((selection + 1))p" /tmp/steam_games_$$)
selected_id=$(echo "$selected_line" | awk -F'|' '{print $1}')
selected_name=$(echo "$selected_line" | awk -F'|' '{print $2}')

echo ""
echo "You selected:"
echo "ID: $selected_id"
echo "Name: $selected_name"
echo ""

# Check if game is running
echo "Checking if game is running..."
if pgrep -f "$selected_id" > /dev/null 2>&1; then
    echo ""
    echo "ERROR: The game is currently running!"
    echo "Please close the game before installing SimHub or dotnet48."
    echo ""
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo "Game is not running. Continuing..."
echo ""

# Check if game has been run at least once (Proton prefix exists)
echo "Checking if game has been run before..."
PROTON_PREFIX="$HOME/.steam/steam/steamapps/compatdata/$selected_id/pfx"
if [ ! -d "$PROTON_PREFIX" ]; then
    echo ""
    echo "ERROR: Game has never been run before!"
    echo "Please run the game at least once and close it."
    echo "This creates the necessary Proton/Wine prefix files."
    echo ""
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo "Game prefix found. Continuing..."
echo ""

# Ask if user wants to install dotnet48
printf "Install dotnet48 for $selected_name? (y/n): "
read -r install_dotnet
echo

if [ "$install_dotnet" = "y" ] || [ "$install_dotnet" = "Y" ]; then
    echo "Installing dotnet48..."
    echo "This may take 5 minutes or more depending on your hardware."
    echo "Please be patient and do not interrupt the process."
    echo ""
    echo "NOTE: A popup may appear saying 'Failed to start rundll32.exe'."
    echo "This is normal and can be safely ignored. Those errors are not uncommon and you can always ignore."
    echo "Click 'No' if prompted and let the installation continue."
    echo ""
    echo "Please wait..."
    echo ""
    
    # Record start time
    start_time=$(date +%s)
    
    WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/$selected_id/pfx" winetricks -q --force dotnet48 > /dev/null 2>&1
    install_result=$?
    
    # Record end time and calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    
    if [ $install_result -eq 0 ]; then
        echo "dotnet48 installation completed successfully!"
        echo "Installation took ${minutes}m ${seconds}s"
    else
        echo "dotnet48 installation failed!"
    fi
else
    echo "WARNING: dotnet48 is required for SimHub to work properly!"
    echo "SimHub may not function correctly without it."
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo ""

# Ask if user wants to install SimHub
printf "Install SimHub for $selected_name? (y/n): "
read -r install_simhub
echo

if [ "$install_simhub" = "y" ] || [ "$install_simhub" = "Y" ]; then
    echo "Downloading SimHub 9.11.5..."
    
    # Create temporary directory for download
    TEMP_DIR="/tmp/simhub_install_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Download SimHub
    if which wget > /dev/null 2>&1; then
        wget -q "https://github.com/SHWotever/SimHub/releases/download/9.11.5/SimHub.9.11.5.zip"
    elif which curl > /dev/null 2>&1; then
        curl -sL -o "SimHub.9.11.5.zip" "https://github.com/SHWotever/SimHub/releases/download/9.11.5/SimHub.9.11.5.zip"
    else
        echo "Error: wget or curl not found!"
        cd /
        rm -rf "$TEMP_DIR"
        rm -f /tmp/steam_games_$$
        exit 1
    fi
    
    # Check if download was successful
    if [ ! -f "SimHub.9.11.5.zip" ]; then
        echo "Error: Failed to download SimHub!"
        cd /
        rm -rf "$TEMP_DIR"
        rm -f /tmp/steam_games_$$
        exit 1
    fi
    
    echo "Download completed. Extracting..."
    
    # Extract the zip file
    if which unzip > /dev/null 2>&1; then
        unzip -q "SimHub.9.11.5.zip"
    else
        echo "Error: unzip not found!"
        cd /
        rm -rf "$TEMP_DIR"
        rm -f /tmp/steam_games_$$
        exit 1
    fi
    
    # Find the SimHub Setup executable
    SIMHUB_SETUP_EXE=$(find "$TEMP_DIR" -name "SimHubSetup_*.exe" -type f)
    
    if [ -z "$SIMHUB_SETUP_EXE" ]; then
        echo "Error: SimHubSetup_*.exe not found in extracted files!"
        cd /
        rm -rf "$TEMP_DIR"
        rm -f /tmp/steam_games_$$
        exit 1
    fi
    
    # Set Windows version to Windows 11
    echo "Setting Windows version to Windows 11..."
    WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/$selected_id/pfx" winetricks -q win11 > /dev/null 2>&1
    
    # Display tips before installation
    echo ""
    echo "=========================================="
    echo "IMPORTANT TIPS BEFORE INSTALLATION"
    echo "=========================================="
    echo ""
    echo "1. The SimHub installer will now launch in Wine/Proton"
    echo "2. Follow the installation wizard that appears"
    echo "3. Choose your preferred installation directory"
    echo "4. The installation may take several minutes"
    echo "5. Do NOT close the installer window prematurely"
    echo "6. Once installation is complete, you can close the window"
    echo "7. SimHub should now be ready to use!"
    echo ""
    echo "=========================================="
    echo ""
    printf "Press Enter to start the SimHub installer..."
    read -r dummy
    echo ""
    
    echo "Installing SimHub..."
    
    # Run the installer
    WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/$selected_id/pfx" protontricks-launch --appid "$selected_id" "$SIMHUB_SETUP_EXE"
    
    if [ $? -eq 0 ]; then
        echo "SimHub installation completed successfully!"
    else
        echo "SimHub installation may have failed or is still running."
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
fi

echo ""

# Cleanup
rm -f /tmp/steam_games_$$
echo "Done!"
