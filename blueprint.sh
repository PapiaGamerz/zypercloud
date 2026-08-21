#!/bin/bash

# =========================================================
# BLUEPRINT FRAMEWORK MANAGER (GUI MENU)
# =========================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[38;5;141m'
GRAY='\033[38;5;242m'
WHITE='\033[38;5;255m'
GOLD='\033[38;5;220m'
BOLD='\033[1m'
NC='\033[0m'

export PTERODACTYL_DIRECTORY=/var/www/pterodactyl

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run as root (use sudo or root account)${NC}"
  exit 1
fi

show_banner() {
    clear
    echo -e "${CYAN}"
    echo '  ██████╗ ██╗     ██╗███████╗██████╗ ██████╗ ██╗███╗   ██╗████████╗'
    echo '  ██╔══██╗██║     ██║██╔════╝██╔══██╗██╔══██╗██║████╗  ██║╚══██╔══╝'
    echo '  ██████╔╝██║     ██║█████╗  ██████╔╝██████╔╝██║██╔██╗ ██║   ██║   '
    echo '  ██╔══██╗██║     ██║██╔══╝  ██╔═══╝ ██╔══██╗██║██║╚██╗██║   ██║   '
    echo '  ██████╔╝███████╗██║███████╗██║     ██║  ██║██║██║ ╚████║   ██║   '
    echo '  ╚═════╝ ╚══════╝╚═╝╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝   ╚═╝   '
    echo -e "${NC}"
}

auto_redirect() {
    echo ""
    echo -e "  ${GRAY}Redirecting to main menu in 3 seconds...${NC}"
    sleep 3
    show_menu
}

show_menu() {
    show_banner
    echo -e "${PURPLE}╭──────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${GOLD}${BOLD}              🛠️ PTERODACTYL BLUEPRINT FRAMEWORK MANAGER                  ${PURPLE}│${NC}"
    echo -e "${PURPLE}├──────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}${BOLD}📂 TARGET PATH:${NC} ${WHITE}$PTERODACTYL_DIRECTORY${NC}"
    echo -e "${PURPLE}├──────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${GOLD}${BOLD}🚀 SELECT AN OPTION:${NC}"
    echo -e "${PURPLE}│${NC}"
    echo -e "${PURPLE}│${NC}    ${GREEN}[1]${NC} 📥 Install Blueprint Framework"
    echo -e "${PURPLE}│${NC}    ${GREEN}[2]${NC} 🗑️  Uninstall Blueprint Framework"
    echo -e "${PURPLE}│${NC}    ${GREEN}[3]${NC} 🔄 Update Blueprint Framework"
    echo -e "${PURPLE}│${NC}    ${RED}[4]${NC} ❌ Exit"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -ne "  ${CYAN}⚡${NC} ${YELLOW}Select Option [1-4]: ${NC}"
    read choice

    case $choice in
        1) install_blueprint ;;
        2) uninstall_blueprint ;;
        3) update_blueprint ;;
        4) echo -e "\n  ${GREEN}[✔] Exiting Blueprint Manager. Goodbye!${NC}\n"; exit 0 ;;
        *) echo -e "\n  ${RED}[!] Invalid option! Please try again.${NC}"; sleep 1.5; show_menu ;;
    esac
}

install_blueprint() {
    show_banner
    echo -e "${CYAN}[+] Installing Blueprint on (${PTERODACTYL_DIRECTORY})...${NC}\n"
    
    if [ ! -d "$PTERODACTYL_DIRECTORY" ]; then
        echo -e "${RED}[!] Error: Directory ${PTERODACTYL_DIRECTORY} does not exist!${NC}"
        echo -e "${YELLOW}[!] Make sure Pterodactyl Panel is installed first.${NC}"
        auto_redirect
        return
    fi

    echo -e "${YELLOW}[1/6] Installing basic dependencies (curl, wget, unzip)...${NC}"
    apt update -y
    apt install -y curl wget unzip ca-certificates git gnupg zip

    echo -e "${YELLOW}[2/6] Downloading & extracting latest Blueprint release...${NC}"
    cd $PTERODACTYL_DIRECTORY
    wget "https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip" -O "$PTERODACTYL_DIRECTORY/release.zip"
    unzip -o release.zip
    rm -f release.zip

    echo -e "${YELLOW}[3/6] Setting up Node.js 22.x repository...${NC}"
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --overwrite
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
    apt update -y
    apt install -y nodejs

    echo -e "${YELLOW}[4/6] Installing Yarn & Node dependencies...${NC}"
    cd $PTERODACTYL_DIRECTORY
    npm i -g yarn
    yarn install

    echo -e "${YELLOW}[5/6] Generating .blueprintrc configuration...${NC}"
    touch $PTERODACTYL_DIRECTORY/.blueprintrc
    echo 'WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";' > $PTERODACTYL_DIRECTORY/.blueprintrc

    echo -e "${YELLOW}[6/6] Setting permissions and starting Blueprint setup...${NC}"
    chmod +x $PTERODACTYL_DIRECTORY/blueprint.sh
    
    echo -e "\n${GREEN}[✔] Pre-installation complete! Executing blueprint.sh...${NC}\n"
    bash $PTERODACTYL_DIRECTORY/blueprint.sh

    auto_redirect
}

uninstall_blueprint() {
    show_banner
    echo -e "${RED}[!] Uninstalling Blueprint Framework...${NC}\n"
    
    if [ ! -d "$PTERODACTYL_DIRECTORY" ]; then
        echo -e "${RED}[!] Pterodactyl directory not found!${NC}"
        auto_redirect
        return
    fi

    read -p "Are you sure you want to remove Blueprint from $PTERODACTYL_DIRECTORY? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        cd $PTERODACTYL_DIRECTORY
        if [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then
            bash $PTERODACTYL_DIRECTORY/blueprint.sh -u 2>/dev/null || bash $PTERODACTYL_DIRECTORY/blueprint.sh --uninstall 2>/dev/null
        fi
        rm -rf $PTERODACTYL_DIRECTORY/.blueprintrc
        rm -rf $PTERODACTYL_DIRECTORY/.blueprint
        rm -f $PTERODACTYL_DIRECTORY/blueprint.sh
        echo -e "\n${GREEN}[✔] Blueprint Framework successfully uninstalled.${NC}"
    else
        echo -e "\n${YELLOW}[*] Uninstallation cancelled.${NC}"
    fi

    auto_redirect
}

update_blueprint() {
    show_banner
    echo -e "${CYAN}[+] Updating Blueprint Framework...${NC}\n"

    if [ ! -d "$PTERODACTYL_DIRECTORY" ]; then
        echo -e "${RED}[!] Pterodactyl directory not found!${NC}"
        auto_redirect
        return
    fi

    cd $PTERODACTYL_DIRECTORY
    echo -e "${YELLOW}[1/2] Fetching latest release zip...${NC}"
    wget "https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip" -O "$PTERODACTYL_DIRECTORY/release.zip"
    unzip -o release.zip
    rm -f release.zip

    echo -e "${YELLOW}[2/2] Running Blueprint update process...${NC}"
    chmod +x $PTERODACTYL_DIRECTORY/blueprint.sh
    bash $PTERODACTYL_DIRECTORY/blueprint.sh

    echo -e "\n${GREEN}[✔] Blueprint updated successfully!${NC}"
    auto_redirect
}

# Start Dashboard Menu
show_menu
