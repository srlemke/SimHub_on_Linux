#!/bin/sh

#Argument: simhub or crewchief
TARGET="$1"

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
echo ""

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
#export STEAM_COMPAT_DATA_PATH="$HOME/.steam/steam/steamapps/compatdata/$selected_id"

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
echo ""

# Check if game is running
echo "Checking if game is running:"
if pgrep -f "$selected_id" > /dev/null 2>&1; then
    echo ""
    echo "ERROR: The game or some app is currently blocking this profile."
    echo "Please close the game/app before installing $1."
    echo "You can close it with: (this closes all apps on that profile, game included ifs running.)"
    echo "WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/"$selected_id"/pfx" wineserver -k"
    echo ""
    printf "Press Enter to exit..."
    read -r dummy
    rm -f /tmp/steam_games_$$
    exit 1
fi

echo "Game is not running, continuing ..."
echo ""

# Check if game has been run at least once (Proton prefix exists)
echo "Checking if game has been run before:"
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

echo "Game prefix found, continuing..."
echo ""

# Check if a winetricks installed dotnet48 is present:
DOTNET_DIR="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"

if [ -f "$DOTNET_DIR/mscorlib.dll" ] && [ $(stat -c%s "$DOTNET_DIR/mscorlib.dll") -gt 1000000 ]; then
    dotnet48_present=0 #Already Installed
    echo "dotnet48 already present!"
else
    dotnet48_present=1 #Not Installed
fi


if  [ $dotnet48_present -eq 0 ]; then
    install_result=0
else
    # Ask if user wants to install dotnet48
    printf "Install dotnet48 for $selected_name? (y/n): y"
    read -r install_dotnet
    echo

    # Default to yes if empty
    if [ -z "$install_dotnet" ]; then
        install_dotnet="y"
    fi

if [ "$install_dotnet" = "y" ] || [ "$install_dotnet" = "Y" ]; then
    echo "Installing dotnet48..."
    echo "This may take 5 minutes or more depending on your hardware."
    echo "Please be patient and do not interrupt the process."
    echo ""
    echo "NOTE: A popup may appear saying 'Failed to start rundll32.exe'."
    echo "This is normal and can be safely ignored. Those errors are not uncommon"
    echo "and you can always ignore by clicking No"
    echo ""
    wineserver -k || true
    #Since its not winetricks dotn48 lets remove fake/stub Dotnet 4.8 that steam adds by default:
    wine reg delete "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    wine reg delete "HKLM\\Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4" /f >/dev/null 2>&1 || true
    echo "Registry verification complete. Now running dotnet48 installer, wait... (~5 min)"

    #Use wine from the Proton prefix in use:
    winetricks -q -f dotnet48 > /dev/null 2>&1;
    install_result=$?
fi
    
if [ $install_result -eq 0 ]; then
        echo "dotnet48 installation looks good!"
    else
        echo "dotnet48 installation failed!"
        echo ""
        echo "WARNING: dotnet48 is required for SimHub to work properly!"
        echo "SimHub may not function correctly without it."
        printf "Press Enter to exit..."
        read -r dummy
        rm -f /tmp/steam_games_$$
        exit 1
    fi

fi

echo ""

###########################################
# FUNCTION: SIMHUB INSTALLER
###########################################
install_simhub() {
    printf "Install SimHub for $selected_name? (y/n): y"
    read -r install_simhub
    echo

    # Default to yes if empty
    if [ -z "$install_simhub" ]; then
        install_simhub="y"
    fi

    if [ "$install_simhub" = "y" ] || [ "$install_simhub" = "Y" ]; then
        echo "Downloading SimHub 9.11.5..."

        TEMP_DIR="/tmp/simhub_install_$$"
        mkdir -p "$TEMP_DIR"
        cd "$TEMP_DIR"

        if which wget > /dev/null 2>&1; then
            wget -q "https://github.com/SHWotever/SimHub/releases/download/9.11.5/SimHub.9.11.5.zip"
        else
            curl -sL -o "SimHub.9.11.5.zip" "https://github.com/SHWotever/SimHub/releases/download/9.11.5/SimHub.9.11.5.zip"
        fi

        if [ ! -f "SimHub.9.11.5.zip" ]; then
            echo "Error: Failed to download SimHub!"
            cd /
            rm -rf "$TEMP_DIR"
            return
        fi

        echo "Extracting..."
        unzip -q "SimHub.9.11.5.zip"

        SIMHUB_SETUP_EXE=$(find "$TEMP_DIR" -name "SimHubSetup_*.exe" -type f)

        if [ -z "$SIMHUB_SETUP_EXE" ]; then
            echo "Error: SimHubSetup_*.exe not found!"
            cd /
            rm -rf "$TEMP_DIR"
            return
        fi

        echo ""
        echo "=========================================="
        echo "IMPORTANT TIPS BEFORE SIMHUB INSTALLATION"
        echo "=========================================="
        echo "1. Uncheck: Install Microsoft .Net and C++ redistributable"
        echo "2. Do NOT run SimHub at the end of the installer"
        echo "=========================================="
        echo ""
        printf "Press Enter to start the SimHub installer..."
        read -r dummy
        echo ""
        echo "Possibly there will be a rundll32.exe error, you can click No to ignore it."

        protontricks-launch --appid "$selected_id" "$SIMHUB_SETUP_EXE" > /dev/null 2>&1;

        if [ $? -eq 0 ]; then
            echo "SimHub installation completed successfully!"
        else
            echo "SimHub installation may have failed or is still running."
        fi

        if pgrep -f "$selected_id" > /dev/null 2>&1; then
            echo "You did run SimHUB after install didnt you?"
            echo "Close it as it locks the Proton profile and your game wont be able to start."
        fi

        cd /
        rm -rf "$TEMP_DIR"
    fi
}

###########################################
# FUNCTION: CREWCHIEF INSTALLER
###########################################
install_crewchief() {
    printf "Install CrewChief for $selected_name? (y/n): y"
    read -r install_cc
    echo

    # Default to yes if empty
    if [ -z "$install_cc" ]; then
        install_cc="y"
    fi

    if [ "$install_cc" = "y" ] || [ "$install_cc" = "Y" ]; then
        echo "Downloading CrewChief..."

        TEMP_DIR="/tmp/crewchief_install_$$"
        mkdir -p "$TEMP_DIR"
        cd "$TEMP_DIR"

        # Download CrewChief ZIP
        if which wget > /dev/null 2>&1; then
            wget -q "http://thecrewchief.org/downloads/CrewChiefV4.zip"
        else
            curl -sL -o "CrewChiefV4.zip" "http://thecrewchief.org/downloads/CrewChiefV4.zip"
        fi

        if [ ! -f "CrewChiefV4.zip" ]; then
            echo "Error: Failed to download CrewChief!"
            cd /
            rm -rf "$TEMP_DIR"
            return
        fi

        echo "Extracting CrewChief..."
        unzip -q "CrewChiefV4.zip"

        # Find the EXE inside the extracted folder
        CC_EXE=$(find "$TEMP_DIR" -name "CrewChiefV4.exe" -type f)

        if [ -z "$CC_EXE" ]; then
            echo "Error: CrewChiefV4.exe not found in extracted files!"
            cd /
            rm -rf "$TEMP_DIR"
            return
        fi

        echo "Installing CrewChief..."
        echo ""
        echo "Possibly there will be a rundll32.exe error, you can click No to ignore it."
        echo "Make sure to press the update CrewChief Option"
        echo "Do not run it after the install finishes, as it locks the proron prefix"

        if pgrep -f "$selected_id" > /dev/null 2>&1; then
            echo "You did run CrewChief after install didnt you?"
            echo "Close it as it locks the Proton profile and your game wont be able to start."
        fi

        #Running the installer:
        #protontricks-launch --appid "$selected_id" "$CC_EXE" > /dev/null 2>&1;
        protontricks-launch --appid "$selected_id" "$CC_EXE"


        if [ ! -d "$WINEPREFIX/drive_c/Program Files (x86)/Britton_IT_Ltd/CrewChiefV4" ]; then
            echo "CrewChief is not fully installed. You must click YES on the update prompt."
            echo "Run the 'installer.sh' crewchief' again and make sure to run the updater."
            echo ""
            echo "If the updater window not appers click on Force Update Check on CrewChief UI"
            echo "It may then crash, but then if you run the installer again the updater windows appears."

        else
            echo "CrewChief installation complete."
        fi

        cd /
        rm -rf "$TEMP_DIR"
    fi
}

# Cleanup Global
rm -f /tmp/steam_games_$$

###########################################
# SELECT INSTALLER BASED ON ARGUMENT
###########################################

case "$TARGET" in
    simhub)
        install_simhub
        ;;
    crewchief)
        install_crewchief
        ;;
    *)
        echo "Invalid option: $TARGET"
        echo "Usage: $0 {simhub|crewchief}"
        exit 1
        ;;
esac
