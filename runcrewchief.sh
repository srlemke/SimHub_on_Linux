#!/bin/bash

#Run the populate script:
cd "$(dirname "$0")"
source ./shared_functions.sh

#List installed games:
if [[ "$1" == "-l" ]]; then
    protontricks -l |grep -vi Protontricks
    exit 0
fi

#Get ID of running game, adds the ability to run the without the game running.
if [[ -n "$1" ]]; then
    # User provided an AppID → no need to auto-detect
    game="$1"
else
    # No AppID provided → detect running game
    running_game_id
fi

#If running Game is LMU check if all configs are done:
check_LMU

# Check if CrewChief install exists
CrewChief_EXE="$STEAM_DIR/steamapps/compatdata/$game/pfx/drive_c/Program Files (x86)/Britton IT Ltd/CrewChiefV4/CrewChiefV4.exe"

if [[ ! -f "$CrewChief_EXE" ]]; then
    echo "CrewChief is not installed for this game."
    echo "You need to run Install_CrewChief_Linux.sh."
    read -p "Press ENTER to exit..."
    exit 1
fi

###############################################
# Launch CrewChief normally for detected game
###############################################
echo "Launching CrewChief..."
export PYTHONWARNINGS="ignore::UserWarning"
protontricks-launch --appid "$game" "$CrewChief_EXE" >/dev/null 2>&1 &
echo "CrewChief has been launched!"

#If running Game is Raceroom launch dash.exe for SealHUD
check_Raceroom
