#!/bin/bash

# =========================================================
# BLUEPRINT FRAMEWORK MANAGER (GUI MENU - DIRECTORY FIXED)
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
    echo '██████╗ ██╗     ██╗   ██╗███████╗██████╗ ██████╗ ██╗███╗   ██╗████████╗'
    echo '██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔══██╗██║████╗  ██║╚══██╔══╝'
    echo '██████╦╝██║     ██║   ██║█████╗  ██████╔╝██████╔╝██║██╔██╗ ██║   ██║   '
    echo '██╔══██╗██║     ██║   ██║██╔══╝  ██╔═══╝ ██╔══██╗██║██║ ╚████║   ██║   '
    echo '██████╦╝███████╗╚██████╔╝███████╗██║     ██║  ██║██║██║  ╚███║   ██║   '
    echo '╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚══╝   ╚═╝   '
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
    echo -e "${PURPLE}│${GOLD}${BOLD}               🛠️ PTERODACTYL BLUEPRINT FRAMEWORK MANAGER                  ${PURPLE}│${NC}"
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

    echo -e "${YELLOW}[1/8] Installing basic dependencies & build tools...${NC}"
    apt update -y
    apt install -y ca-certificates curl git gnupg unzip wget zip build-essential python3

    echo -e "${YELLOW}[2/8] Cleaning old APT Nodesource lists to prevent keyring conflicts...${NC}"
    rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/sources.list.d/nodesource*.list

    echo -e "${YELLOW}[3/8] Setting up Node.js 22.x...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt update -y
    apt install -y nodejs

    echo -e "${YELLOW}[4/8] Setting up Yarn Classic (v1.x)...${NC}"
    npm uninstall -g yarn 2>/dev/null || true
    corepack enable
    corepack prepare yarn@1.22.22 --activate

    echo -e "${YELLOW}[5/8] Downloading & extracting latest Blueprint release...${NC}"
    cd "$PTERODACTYL_DIRECTORY" || exit
    wget "https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip" -O "$PTERODACTYL_DIRECTORY/release.zip"
    unzip -o release.zip
    rm -f release.zip

    echo -e "${YELLOW}[6/8] Pre-creating required Blueprint log & asset structure...${NC}"
    mkdir -p "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug"
    mkdir -p "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem"
    touch "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt"
    touch "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem/emblem.jpg"

    echo -e "${YELLOW}[7/8] Configuring .blueprintrc...${NC}"
    cat <<'EOF' > "$PTERODACTYL_DIRECTORY/.blueprintrc"
WEBUSER="www-data";
OWNERSHIP="www-data:www-data";
USERSHELL="/bin/bash";
FOLDER="/var/www/pterodactyl";
PTERODACTYL_DIRECTORY="/var/www/pterodactyl";
EOF

    echo -e "${YELLOW}[8/8] Setting Yarn to Classic and compiling dependencies...${NC}"
    cd "$PTERODACTYL_DIRECTORY" || exit
    yarn set version classic
    yarn cache clean
    yarn install --ignore-engines || npm install --legacy-peer-deps

    chmod +x "$PTERODACTYL_DIRECTORY/blueprint.sh"
    chown -R www-data:www-data "$PTERODACTYL_DIRECTORY"
    
    echo -e "\n${GREEN}[✔] Pre-installation complete! Executing blueprint.sh...${NC}\n"
    cd "$PTERODACTYL_DIRECTORY" && bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

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
        cd "$PTERODACTYL_DIRECTORY" || exit
        if [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then
            bash "$PTERODACTYL_DIRECTORY/blueprint.sh" -u 2>/dev/null || bash "$PTERODACTYL_DIRECTORY/blueprint.sh" --uninstall 2>/dev/null
        fi
        rm -rf "$PTERODACTYL_DIRECTORY/.blueprintrc"
        rm -rf "$PTERODACTYL_DIRECTORY/.blueprint"
        rm -f "$PTERODACTYL_DIRECTORY/blueprint.sh"
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

    cd "$PTERODACTYL_DIRECTORY" || exit
    echo -e "${YELLOW}[1/3] Fetching latest release zip...${NC}"
    wget "https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip" -O "$PTERODACTYL_DIRECTORY/release.zip"
    unzip -o release.zip
    rm -f release.zip

    echo -e "${YELLOW}[2/3] Ensuring Yarn Classic and resolving dependencies...${NC}"
    yarn set version classic
    yarn install --ignore-engines || npm install --legacy-peer-deps

    echo -e "${YELLOW}[3/3] Running Blueprint update process...${NC}"
    chmod +x "$PTERODACTYL_DIRECTORY/blueprint.sh"
    cd "$PTERODACTYL_DIRECTORY" && bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

    echo -e "\n${GREEN}[✔] Blueprint updated successfully!${NC}"
    auto_redirect
}

# Start Dashboard Menu
show_menu
