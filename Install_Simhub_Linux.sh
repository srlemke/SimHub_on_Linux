#!/bin/sh

#SimHUB Version that will be downloaded
version=9.11.10

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
selected_line=$(sed -n "$((selection + 1))p" /tmp/steam_games_$$)
selected_id=$(echo "$selected_line" | awk -F'|' '{print $1}')
selected_name=$(echo "$selected_line" | awk -F'|' '{print $2}')

echo "You selected:"
echo "ID: $selected_id"
echo "Name: $selected_name"
echo

# Extract the path for the Proton Version used by the selected game:
PROTON_VERSION=$(cat "$HOME/.steam/steam/steamapps/compatdata/$selected_id/config_info" \
	|grep pfx |cut -d/ -f7- |sed 's|/files/share/default_pfx/.*||' )
# Extracted path looks like:
# /compatibilitytools.d/GE-Proton10-34-LMU-hid_fixes
# /Steam/steamapps/common/Proton Hotfix
# Others, depending on what Proton is in use.

if [ -z "$PROTON_VERSION" ]; then
    echo "ERROR: Could not detect Proton version from config_info."
    exit 1
fi

# Set the PROTON path variables to what the selected game uses:
PROTON_DIR="$HOME/.steam/steam/$PROTON_VERSION"
PROTON_WINE="$PROTON_DIR/files/bin/wine"

# Since we use winetricks:
export WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/$selected_id/pfx"
export STEAM_COMPAT_DATA_PATH="$HOME/.steam/steam/steamapps/compatdata/$selected_id"

#Sometimes the used proton variable is empty, lets make sure to populate it with in use Proton:
export PROTON_VERSION=$(basename "$PROTON_DIR")

# Normalize Proton Experimental naming
if [ "$PROTON_VERSION" = "Proton - Experimental" ]; then
    PROTON_VERSION="Proton Experimental"
fi

# Let the user know what we detected:
echo PROTON_VERSION: $PROTON_VERSION
echo PROTON_DIR: $PROTON_DIR
echo PROTON_WINE:  $PROTON_WINE
echo Game Prefix: $WINEPREFIX
echo

# Check if game is running
echo "Checking if game is running:"
if pgrep -f "$selected_id" > /dev/null 2>&1; then
    echo
    echo "ERROR: The game is currently running!"
    echo "Please close the game before installing SimHub or dotnet48."
    echo
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo "Game is not running, continuing ..."
echo

# Check if game has been run at least once (Proton prefix exists)
echo "Checking if game has been run before:"
PROTON_PREFIX="$HOME/.steam/steam/steamapps/compatdata/$selected_id/pfx"

if [ ! -d "$PROTON_PREFIX" ]; then
    echo
    echo "ERROR: Game has never been run before!"
    echo "Please run the game at least once and close it."
    echo "This creates the necessary Proton/Wine prefix files."
    echo
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo "Game prefix found, continuing ..."
echo

##.NET:
dotnet_installed() {
# Check if a winetricks installed dotnet48 is present:
    DOTNET_DIR="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"

    if [ -f "$DOTNET_DIR/mscorlib.dll" ] && [ $(stat -c%s "$DOTNET_DIR/mscorlib.dll") -gt 1000000 ]; then
        return 0 #Already installed
    else
        return 1 #Not installed
    fi
}

install_dotnet() {
    echo "Installing dotnet48..."
    echo "This may take 5 minutes or more depending on your hardware."
    echo "Please be patient and do not interrupt the process."
    echo
    echo "NOTE: A popup may appear saying 'Failed to start rundll32.exe'."
    echo "This is normal and can be safely ignored. Those errors are not uncommon"
    echo "and you can always ignore by clicking No"
    echo
    wine reg delete "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    wine reg delete "HKLM\\Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    echo "Cleared old invalid .NET registry entries. Now running dotnet48 installer, wait... (~5 min)"
    winetricks -q -f dotnet48 > /dev/null 2>&1;
    install_result=$?
}

if dotnet_installed; then
    echo "Microsoft .NET Framework 4.8 appears to already be installed."
    echo "A reinstall maybe a good idea if the windows app, like SimHUB stopped working."
    echo
    printf "Do you want to reinstall dotnet48 (y/N): " answer
    read -r answer

    if [ "$answer" = "y" ] || [ "$answer" = "Y" ] ; then
        install_dotnet
    else
        echo "Skipping reinstallation."
        echo "Consider reinstallation if the windows app is not starting."
    fi
fi

if ! dotnet_installed; then
    # Ask if user wants to install dotnet48
    printf "Install dotnet48 for $selected_name? (y/N): "
    read -r install_dotnet
fi

if [ "$install_dotnet" = "y" ] || [ "$install_dotnet" = "Y" ] ; then
    install_dotnet
elif ! dotnet_installed; then
    echo "dotnet48 installation not present!"
    echo "WARNING: dotnet48 is required for SimHub-"$version" to work!"
    echo
    echo "Tip, some games need to run at least 2 times for the dotnet48 install properly"
    echo "Maybe start stop the game and run this script again."
    echo
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

if ! dotnet_installed; then
    echo "dotnet48 missing, try again."
    exit 1
fi

echo

##SIMHUB:
# Ask if user wants to install SimHub
printf "Install SimHub-"$version" for $selected_name? (y/N): "
read -r install_simhub
echo

if [ "$install_simhub" = "y" ] || [ "$install_simhub" = "Y" ]; then
    echo "Downloading SimHub-"$version"..."
    
    # Create temporary directory for download
    TEMP_DIR="/tmp/simhub_install_$$"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Download SimHub
    if which wget > /dev/null 2>&1; then
        wget -q "https://github.com/SHWotever/SimHub/releases/download/"$version"/SimHub."$version".zip"
    elif which curl > /dev/null 2>&1; then
        curl -sL -o "SimHub."$version".zip" "https://github.com/SHWotever/SimHub/releases/download/"$version"/SimHub."$version".zip"
	fi
else
	echo "SimHub-"$version" install cancelled, bye."
	exit 1
fi
    
    # Check if download was successful
    if [ ! -f "SimHub."$version".zip" ]; then
        echo "Error: Failed to download SimHub!"
        cd /
        rm -rf "$TEMP_DIR"
        rm -f /tmp/steam_games_$$
        exit 1
    fi
    
    echo "Download completed. Extracting..."
    
    # Extract the zip file
    if which unzip > /dev/null 2>&1; then
        unzip -q "SimHub."$version".zip"
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

    # Display tips before installation
    echo
    echo "=========================================="
    echo "IMPORTANT TIPS BEFORE SIMHUB INSTALLATION"
    echo "=========================================="
    echo
    echo "1. Make sure to uncheck: Install Microsoft .Net and C++ redistributable"
    echo
    echo "2. Do not run SimHub from the installer at the end, uncheck that option."
    echo "Otherwise it locks the game prefix and you won't be able to start the game via steam."
    echo "   - In case you did run it, close it and the game should start."
    echo
    echo "If you have more games the created menu entries are unreliable due differemt game prefixes."
    echo "Run it with the other provided script (runsimhub2.sh), it auto detects the running game and proton version."
    echo "=========================================="
    echo
    printf "Press Enter to start the SimHub installer..."
    read -r dummy
    echo
    
    echo "Installing SimHub... If rundll32.exe errors appear you can ignore them by clicking No."
    
    # Run the installer
    protontricks-launch --appid "$selected_id" "$SIMHUB_SETUP_EXE" > /dev/null 2>&1;
    
if [ $? -eq 0 ]; then
    echo "SimHub installation completed successfully!"
    echo "You can update it to the latest version normally via the SimHUB UI"
	# Cleanup SimHUB Downloaded files
	rm -rf "$TEMP_DIR"

    # Check if selected_id requires additional configuration
    if [ "$selected_id" = "2399420" ] || [ "$selected_id" = "211500" ]; then
        echo "No additional SimHub configuration is required for this game."
    else
        echo "You may need to configure SimHub for this game."
        echo "In most cases this can be done directly via SimHub:"
        echo "Game Config option -> Configure Game Now."
	fi
else
    echo
    echo "SimHub installation failed or cancelled"
fi

echo

# Cleanup Global
rm -f /tmp/steam_games_$$
