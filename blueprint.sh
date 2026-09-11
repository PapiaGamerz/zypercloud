#!/bin/bash

# =========================================================
# BLUEPRINT FRAMEWORK MANAGER
# Docker + Pterodactyl /var/www/pterodactyl
# =========================================================

set +e

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

# =========================================================
# CONFIG
# =========================================================

export PTERODACTYL_DIRECTORY="/var/www/pterodactyl"

WEBUSER="www-data"
OWNERSHIP="www-data:www-data"

BLUEPRINT_RELEASE_URL="https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip"
BLUEPRINT_CLI="/usr/local/bin/blueprint"
RELEASE_ZIP="$PTERODACTYL_DIRECTORY/release.zip"

# =========================================================
# ROOT CHECK
# =========================================================

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Please run this script as root.${NC}"
    exit 1
fi

# =========================================================
# BANNER
# =========================================================

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

    echo -e "${PURPLE}╭──────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${GOLD}${BOLD}           PTERODACTYL BLUEPRINT FRAMEWORK MANAGER                       ${PURPLE}│${NC}"
    echo -e "${PURPLE}├──────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}Target:${NC} ${WHITE}$PTERODACTYL_DIRECTORY${NC}"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────────────────────────╯${NC}"
    echo ""
}

# =========================================================
# WAIT / MENU
# =========================================================

pause_return() {
    echo ""
    read -rp "Press Enter to return to menu..." _
    show_menu
}

# =========================================================
# CHECK PTERODACTYL
# =========================================================

check_panel() {

    if [ ! -d "$PTERODACTYL_DIRECTORY" ]; then
        echo -e "${RED}[!] Pterodactyl directory not found:${NC}"
        echo "    $PTERODACTYL_DIRECTORY"
        return 1
    fi

    return 0
}

# =========================================================
# DOCKER / APP PATH FIX
# =========================================================

fix_docker_path() {

    echo -e "${YELLOW}[*] Checking Docker /app path...${NC}"

    if [ -f "/.dockerenv" ]; then

        echo -e "${CYAN}[+] Docker environment detected.${NC}"

        if [ -e "/app" ] && [ ! -L "/app" ]; then
            echo -e "${YELLOW}[!] /app exists and is not a symlink. Leaving it untouched.${NC}"
        elif [ ! -e "/app" ]; then
            ln -s "$PTERODACTYL_DIRECTORY" /app
            echo -e "${GREEN}[✔] Created /app -> $PTERODACTYL_DIRECTORY${NC}"
        else
            echo -e "${GREEN}[✔] /app already exists.${NC}"
        fi

    else
        echo -e "${GRAY}[*] Docker not detected. Skipping /app fix.${NC}"
    fi
}

# =========================================================
# BLUEPRINT CONFIG
# =========================================================

write_blueprintrc() {

    echo -e "${YELLOW}[*] Writing .blueprintrc...${NC}"

    cat > "$PTERODACTYL_DIRECTORY/.blueprintrc" <<EOF
WEBUSER="$WEBUSER";
OWNERSHIP="$OWNERSHIP";
USERSHELL="/bin/bash";
FOLDER="$PTERODACTYL_DIRECTORY";
PTERODACTYL_DIRECTORY="$PTERODACTYL_DIRECTORY";
EOF

    chmod 644 "$PTERODACTYL_DIRECTORY/.blueprintrc"

    echo -e "${GREEN}[✔] .blueprintrc configured.${NC}"
}

# =========================================================
# BLUEPRINT DIRECTORIES
# =========================================================

create_blueprint_structure() {

    echo -e "${YELLOW}[*] Creating Blueprint directory structure...${NC}"

    mkdir -p \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug" \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/db" \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/build" \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/assets" \
        "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem"

    echo -e "${GREEN}[✔] Blueprint directories ready.${NC}"
}

# =========================================================
# DOWNLOAD RELEASE
# =========================================================

download_release() {

    echo -e "${YELLOW}[*] Downloading latest Blueprint release...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    rm -f "$RELEASE_ZIP"

    if command -v curl >/dev/null 2>&1; then

        curl -fL \
            "$BLUEPRINT_RELEASE_URL" \
            -o "$RELEASE_ZIP"

    elif command -v wget >/dev/null 2>&1; then

        wget -O "$RELEASE_ZIP" \
            "$BLUEPRINT_RELEASE_URL"

    else

        echo -e "${RED}[!] curl/wget not found.${NC}"
        return 1
    fi

    if [ ! -s "$RELEASE_ZIP" ]; then
        echo -e "${RED}[!] Blueprint release download failed.${NC}"
        return 1
    fi

    echo -e "${GREEN}[✔] Release downloaded.${NC}"
    ls -lh "$RELEASE_ZIP"

    return 0
}

# =========================================================
# EXTRACT RELEASE
# =========================================================

extract_release() {

    echo -e "${YELLOW}[*] Extracting Blueprint release...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    if ! unzip -t "$RELEASE_ZIP" >/dev/null 2>&1; then
        echo -e "${RED}[!] release.zip is corrupted.${NC}"
        return 1
    fi

    unzip -q -o "$RELEASE_ZIP"

    echo -e "${GREEN}[✔] Release extracted.${NC}"

    return 0
}

# =========================================================
# REPAIR RELEASE STRUCTURE
# =========================================================

repair_blueprint_files() {

    echo -e "${YELLOW}[*] Repairing Blueprint framework structure...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    # -----------------------------------------------------
    # Framework
    # -----------------------------------------------------

    if [ ! -d "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" ]; then

        echo -e "${YELLOW}[!] BlueprintFramework missing. Restoring...${NC}"

        unzip -q -o \
            "$RELEASE_ZIP" \
            'app/BlueprintFramework/*' \
            -d "$PTERODACTYL_DIRECTORY"

    fi

    # -----------------------------------------------------
    # Extension filesystem
    # -----------------------------------------------------

    if [ ! -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/extensionfs.php" ]; then

        echo -e "${YELLOW}[!] extensionfs.php missing. Restoring...${NC}"

        TMP_DIR="$(mktemp -d)"

        unzip -q -o \
            "$RELEASE_ZIP" \
            'blueprint/extensions/blueprint/private/*' \
            -d "$TMP_DIR"

        mkdir -p \
            "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint"

        cp -a \
            "$TMP_DIR/blueprint/extensions/blueprint/private" \
            "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/"

        rm -rf "$TMP_DIR"

    fi

    # -----------------------------------------------------
    # Logs
    # -----------------------------------------------------

    mkdir -p \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug"

    if [ ! -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt" ]; then

        unzip -p \
            "$RELEASE_ZIP" \
            'blueprint/extensions/blueprint/private/debug/logs.txt' \
            > "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt" \
            2>/dev/null || touch "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt"

    fi

    # -----------------------------------------------------
    # Database files
    # -----------------------------------------------------

    mkdir -p \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/db"

    for f in randomclassname installed_extensions; do

        if [ ! -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/db/$f" ]; then

            unzip -p \
                "$RELEASE_ZIP" \
                "blueprint/extensions/blueprint/private/db/$f" \
                > "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/db/$f" \
                2>/dev/null || true

        fi

    done

    # -----------------------------------------------------
    # Emblem
    # -----------------------------------------------------

    mkdir -p \
        "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem"

    EMBLEM="$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem/emblem.jpg"

    if [ ! -s "$EMBLEM" ]; then

        echo -e "${YELLOW}[!] Restoring Blueprint emblem...${NC}"

        unzip -p \
            "$RELEASE_ZIP" \
            'blueprint/assets/Emblem/emblem.jpg' \
            > "$EMBLEM" \
            2>/dev/null || true

    fi

    # -----------------------------------------------------
    # Permissions
    # -----------------------------------------------------

    if [ -d "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" ]; then
        chown -R "$OWNERSHIP" \
            "$PTERODACTYL_DIRECTORY/app/BlueprintFramework"
    fi

    if [ -d "$PTERODACTYL_DIRECTORY/.blueprint" ]; then
        chown -R "$OWNERSHIP" \
            "$PTERODACTYL_DIRECTORY/.blueprint"
    fi

    echo -e "${GREEN}[✔] Blueprint structure repaired.${NC}"
}

# =========================================================
# NODE / YARN
# =========================================================

setup_node_yarn() {

    echo -e "${YELLOW}[*] Checking Node.js...${NC}"

    if command -v node >/dev/null 2>&1; then
        echo -e "${GREEN}[✔] Node: $(node --version)${NC}"
    else

        echo -e "${YELLOW}[*] Installing Node.js 22...${NC}"

        apt-get update -y

        apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            unzip \
            wget \
            git \
            zip \
            build-essential \
            python3

        rm -f \
            /etc/apt/sources.list.d/nodesource.list \
            /etc/apt/sources.list.d/nodesource*.list

        curl -fsSL \
            https://deb.nodesource.com/setup_22.x | bash -

        apt-get update -y

        apt-get install -y nodejs
    fi

    echo -e "${YELLOW}[*] Checking Yarn...${NC}"

    if command -v yarn >/dev/null 2>&1; then

        echo -e "${GREEN}[✔] Yarn: $(yarn --version)${NC}"

    else

        echo -e "${YELLOW}[*] Installing Yarn Classic...${NC}"

        corepack enable 2>/dev/null || true
        corepack prepare yarn@1.22.22 --activate 2>/dev/null || true

    fi

    if ! command -v yarn >/dev/null 2>&1; then

        npm install -g yarn@1.22.22

    fi

    echo -e "${GREEN}[✔] Yarn: $(yarn --version)${NC}"
}

# =========================================================
# DEPENDENCIES
# =========================================================

install_dependencies() {

    echo -e "${YELLOW}[*] Installing panel dependencies...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    if [ -f package.json ]; then

        yarn install --ignore-engines

        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}[!] Yarn failed. Trying npm fallback...${NC}"
            npm install --legacy-peer-deps
        fi

    else

        echo -e "${GRAY}[*] package.json not found. Skipping Yarn install.${NC}"

    fi
}

# =========================================================
# BLUEPRINT.SH
# =========================================================

run_blueprint_script() {

    if [ ! -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then

        echo -e "${RED}[!] blueprint.sh not found.${NC}"
        return 1

    fi

    chmod 755 "$PTERODACTYL_DIRECTORY/blueprint.sh"

    chown "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/blueprint.sh"

    echo -e "${YELLOW}[*] Running Blueprint installer/update...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

    return $?
}

# =========================================================
# BLUEPRINT CLI FIX
# =========================================================

fix_blueprint_cli() {

    echo -e "${YELLOW}[*] Checking Blueprint CLI...${NC}"

    if [ ! -e "$BLUEPRINT_CLI" ]; then

        echo -e "${YELLOW}[!] Blueprint CLI not found at $BLUEPRINT_CLI${NC}"
        echo -e "${GRAY}[*] CLI fix skipped. blueprint.sh remains usable.${NC}"

        return 0
    fi

    chmod 755 "$BLUEPRINT_CLI"

    chown root:root "$BLUEPRINT_CLI"

    echo -e "${GREEN}[✔] Blueprint CLI permission fixed.${NC}"

    ls -la "$BLUEPRINT_CLI"

    if "$BLUEPRINT_CLI" --version >/dev/null 2>&1; then

        echo -e "${GREEN}[✔] Blueprint CLI is executable.${NC}"

    else

        echo -e "${YELLOW}[!] Blueprint CLI exists but --version failed.${NC}"
        echo -e "${GRAY}[*] This does not prevent blueprint.sh from working.${NC}"

    fi
}

# =========================================================
# ARTISAN CACHE
# =========================================================

clear_laravel_cache() {

    echo -e "${YELLOW}[*] Clearing Laravel caches...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 0

    if [ -f artisan ]; then

        php artisan optimize:clear

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[✔] Laravel cache cleared.${NC}"
        else
            echo -e "${YELLOW}[!] Laravel cache clear returned an error.${NC}"
        fi

    fi
}

# =========================================================
# PERMISSIONS
# =========================================================

fix_permissions() {

    echo -e "${YELLOW}[*] Fixing Pterodactyl permissions...${NC}"

    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/.blueprint" \
        "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" \
        2>/dev/null || true

    chmod 755 \
        "$PTERODACTYL_DIRECTORY/blueprint.sh" \
        2>/dev/null || true

    # Blueprint CLI must remain root-owned and executable
    if [ -e "$BLUEPRINT_CLI" ]; then
        chown root:root "$BLUEPRINT_CLI"
        chmod 755 "$BLUEPRINT_CLI"
    fi

    echo -e "${GREEN}[✔] Permissions fixed.${NC}"
}

# =========================================================
# VERIFY
# =========================================================

verify_installation() {

    echo ""
    echo -e "${GOLD}${BOLD}===== BLUEPRINT VERIFICATION =====${NC}"

    echo ""

    if [ -d "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" ]; then
        echo -e "${GREEN}[✔] BlueprintFramework exists${NC}"
    else
        echo -e "${RED}[✘] BlueprintFramework missing${NC}"
    fi

    if [ -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/extensionfs.php" ]; then
        echo -e "${GREEN}[✔] extensionfs.php exists${NC}"
    else
        echo -e "${RED}[✘] extensionfs.php missing${NC}"
    fi

    if [ -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt" ]; then
        echo -e "${GREEN}[✔] logs.txt exists${NC}"
    else
        echo -e "${RED}[✘] logs.txt missing${NC}"
    fi

    if [ -s "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem/emblem.jpg" ]; then
        echo -e "${GREEN}[✔] emblem.jpg exists${NC}"
    else
        echo -e "${RED}[✘] emblem.jpg missing/empty${NC}"
    fi

    if [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then
        echo -e "${GREEN}[✔] blueprint.sh exists${NC}"
    else
        echo -e "${RED}[✘] blueprint.sh missing${NC}"
    fi

    if [ -x "$BLUEPRINT_CLI" ]; then
        echo -e "${GREEN}[✔] /usr/local/bin/blueprint executable${NC}"
    else
        echo -e "${RED}[✘] /usr/local/bin/blueprint not executable${NC}"
    fi

    echo ""

    if [ -f "$PTERODACTYL_DIRECTORY/artisan" ]; then

        php "$PTERODACTYL_DIRECTORY/artisan" --version

    fi

    echo ""
    echo -e "${GOLD}==================================${NC}"
}

# =========================================================
# INSTALL
# =========================================================

install_blueprint() {

    show_banner

    echo -e "${CYAN}[+] Installing Blueprint Framework...${NC}"
    echo ""

    if ! check_panel; then
        pause_return
        return
    fi

    setup_node_yarn

    fix_docker_path

    write_blueprintrc

    create_blueprint_structure

    if ! download_release; then
        pause_return
        return
    fi

    if ! extract_release; then
        pause_return
        return
    fi

    create_blueprint_structure

    repair_blueprint_files

    install_dependencies

    fix_permissions

    fix_blueprint_cli

    echo ""
    echo -e "${GREEN}[✔] Pre-installation completed.${NC}"
    echo ""

    run_blueprint_script

    clear_laravel_cache

    fix_permissions

    verify_installation

    echo ""
    echo -e "${GREEN}${BOLD}[✔] Blueprint installation process completed.${NC}"

    pause_return
}

# =========================================================
# UPDATE
# =========================================================

update_blueprint() {

    show_banner

    echo -e "${CYAN}[+] Updating Blueprint Framework...${NC}"
    echo ""

    if ! check_panel; then
        pause_return
        return
    fi

    fix_docker_path

    write_blueprintrc

    create_blueprint_structure

    setup_node_yarn

    if ! download_release; then
        pause_return
        return
    fi

    if ! extract_release; then
        pause_return
        return
    fi

    repair_blueprint_files

    install_dependencies

    fix_permissions

    fix_blueprint_cli

    echo ""
    echo -e "${YELLOW}[*] Running Blueprint update process...${NC}"
    echo ""

    run_blueprint_script

    clear_laravel_cache

    fix_permissions

    verify_installation

    echo ""
    echo -e "${GREEN}${BOLD}[✔] Blueprint update process completed.${NC}"

    pause_return
}

# =========================================================
# UNINSTALL
# =========================================================

uninstall_blueprint() {

    show_banner

    echo -e "${RED}[!] Blueprint Framework Uninstall${NC}"
    echo ""

    if ! check_panel; then
        pause_return
        return
    fi

    read -rp "Remove Blueprint Framework? (y/N): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then

        echo -e "${YELLOW}[*] Uninstallation cancelled.${NC}"
        pause_return
        return

    fi

    cd "$PTERODACTYL_DIRECTORY" || return

    if [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then

        chmod 755 "$PTERODACTYL_DIRECTORY/blueprint.sh"

        bash "$PTERODACTYL_DIRECTORY/blueprint.sh" -u 2>/dev/null || \
        bash "$PTERODACTYL_DIRECTORY/blueprint.sh" --uninstall 2>/dev/null || true

    fi

    rm -rf \
        "$PTERODACTYL_DIRECTORY/.blueprint" \
        "$PTERODACTYL_DIRECTORY/.blueprintrc"

    # Do NOT delete the entire Pterodactyl app directory.
    # Do NOT delete .env.

    echo ""
    echo -e "${GREEN}[✔] Blueprint configuration removed.${NC}"

    pause_return
}

# =========================================================
# REPAIR ONLY
# =========================================================

repair_only() {

    show_banner

    echo -e "${CYAN}[+] Running Blueprint repair...${NC}"
    echo ""

    if ! check_panel; then
        pause_return
        return
    fi

    fix_docker_path

    write_blueprintrc

    create_blueprint_structure

    if [ ! -f "$RELEASE_ZIP" ]; then

        echo -e "${YELLOW}[*] release.zip not found. Downloading...${NC}"

        if ! download_release; then
            pause_return
            return
        fi

    fi

    if ! unzip -t "$RELEASE_ZIP" >/dev/null 2>&1; then

        echo -e "${YELLOW}[*] Existing release.zip invalid. Re-downloading...${NC}"

        if ! download_release; then
            pause_return
            return
        fi

    fi

    repair_blueprint_files

    fix_permissions

    fix_blueprint_cli

    clear_laravel_cache

    verify_installation

    echo ""
    echo -e "${GREEN}${BOLD}[✔] Repair completed.${NC}"

    pause_return
}

# =========================================================
# MENU
# =========================================================

show_menu() {

    show_banner

    echo -e "${PURPLE}╭──────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${NC} ${GREEN}[1]${NC} 📥 Install Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${GREEN}[2]${NC} 🗑️  Uninstall Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${GREEN}[3]${NC} 🔄 Update Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${GREEN}[4]${NC} 🛠️  Repair Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${RED}[5]${NC} ❌ Exit"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────────────────────────╯${NC}"

    echo ""
    echo -ne "${CYAN}⚡ Select Option [1-5]: ${NC}"
    read choice

    case "$choice" in

        1)
            install_blueprint
            ;;

        2)
            uninstall_blueprint
            ;;

        3)
            update_blueprint
            ;;

        4)
            repair_only
            ;;

        5)
            echo ""
            echo -e "${GREEN}[✔] Goodbye!${NC}"
            exit 0
            ;;

        *)
            echo ""
            echo -e "${RED}[!] Invalid option.${NC}"
            sleep 2
            show_menu
            ;;

    esac
}

# =========================================================
# START
# =========================================================

show_menu
