#!/bin/bash

# =========================================================
# BLUEPRINT FRAMEWORK MANAGER
# Docker + Pterodactyl /var/www/pterodactyl
# Node.js 22+ + Yarn Classic 1.22.22
# Themes + ZYREXHOST Extensions GUI
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

THEME_SCRIPT_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/theme.sh"

EXTENSION_SCRIPT_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/extension.sh"

BLUEPRINT_CLI="/usr/local/bin/blueprint"

RELEASE_ZIP="$PTERODACTYL_DIRECTORY/release.zip"

THEME_TEMP="/tmp/blueprint-theme-manager.sh"
EXTENSION_TEMP="/tmp/zyrexhost-extension-installer.sh"

REQUIRED_NODE_MAJOR="22"
REQUIRED_YARN_VERSION="1.22.22"

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
    echo '╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝╚═╝  ╚══╝   ╚═╝   '
    echo -e "${NC}"

    echo -e "${PURPLE}╭──────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${GOLD}${BOLD}           PTERODACTYL BLUEPRINT FRAMEWORK MANAGER                       ${PURPLE}│${NC}"
    echo -e "${PURPLE}├──────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${PURPLE}│${NC} ${CYAN}Target:${NC} ${WHITE}$PTERODACTYL_DIRECTORY${NC}"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────────────────────────╯${NC}"
    echo ""
}

# =========================================================
# PAUSE
# =========================================================

pause_return() {

    echo ""
    read -rp "Press Enter to return to menu..." _
    show_menu
}

# =========================================================
# PANEL CHECK
# =========================================================

check_panel() {

    if [ ! -d "$PTERODACTYL_DIRECTORY" ]; then

        echo -e "${RED}[!] Pterodactyl directory not found:${NC}"
        echo "    $PTERODACTYL_DIRECTORY"

        return 1
    fi

    if [ ! -f "$PTERODACTYL_DIRECTORY/artisan" ]; then

        echo -e "${YELLOW}[!] Laravel artisan not found.${NC}"
        echo "    $PTERODACTYL_DIRECTORY/artisan"

        return 1
    fi

    return 0
}

# =========================================================
# DOCKER /APP
# =========================================================

fix_docker_path() {

    echo -e "${YELLOW}[*] Checking Docker /app path...${NC}"

    if [ -f "/.dockerenv" ]; then

        echo -e "${CYAN}[+] Docker environment detected.${NC}"

        if [ -L "/app" ]; then

            CURRENT_TARGET="$(readlink -f /app 2>/dev/null)"

            if [ "$CURRENT_TARGET" = "$PTERODACTYL_DIRECTORY" ]; then

                echo -e "${GREEN}[✔] /app already points to Pterodactyl.${NC}"

            else

                echo -e "${YELLOW}[!] /app points to another location.${NC}"
                echo "    Current: $CURRENT_TARGET"

            fi

        elif [ -e "/app" ]; then

            echo -e "${YELLOW}[!] /app exists and is not a symlink. Leaving untouched.${NC}"

        else

            ln -s "$PTERODACTYL_DIRECTORY" /app

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[✔] Created /app -> $PTERODACTYL_DIRECTORY${NC}"
            else
                echo -e "${RED}[✘] Failed to create /app symlink.${NC}"
                return 1
            fi
        fi

    else

        echo -e "${GRAY}[*] Docker not detected.${NC}"

    fi

    return 0
}

# =========================================================
# BLUEPRINT CONFIG
# =========================================================

write_blueprintrc() {

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
# BLUEPRINT STRUCTURE
# =========================================================

create_blueprint_structure() {

    mkdir -p \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug" \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/db" \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/build" \
        "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/assets" \
        "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem"

    echo -e "${GREEN}[✔] Blueprint directories ready.${NC}"
}

# =========================================================
# NODE VERSION CHECK
# =========================================================

node_major_version() {

    if ! command -v node >/dev/null 2>&1; then
        echo "0"
        return
    fi

    node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo "0"
}

# =========================================================
# INSTALL NODE 22
# =========================================================

install_node22() {

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

    if [ $? -ne 0 ]; then
        echo -e "${RED}[✘] NodeSource setup failed.${NC}"
        return 1
    fi

    apt-get update -y

    apt-get install -y nodejs

    if ! command -v node >/dev/null 2>&1; then
        echo -e "${RED}[✘] Node.js installation failed.${NC}"
        return 1
    fi

    return 0
}

# =========================================================
# NODE + YARN
# =========================================================

setup_node_yarn() {

    echo -e "${YELLOW}[*] Checking Node.js...${NC}"

    CURRENT_MAJOR="$(node_major_version)"

    if [ "$CURRENT_MAJOR" -lt "$REQUIRED_NODE_MAJOR" ]; then

        echo -e "${YELLOW}[!] Node.js 22+ is required.${NC}"

        if command -v node >/dev/null 2>&1; then
            echo "    Current Node: $(node --version)"
        fi

        if ! install_node22; then
            return 1
        fi

    fi

    CURRENT_MAJOR="$(node_major_version)"

    if [ "$CURRENT_MAJOR" -lt "$REQUIRED_NODE_MAJOR" ]; then

        echo -e "${RED}[✘] Node.js 22+ could not be installed.${NC}"
        echo "    Current: $(node --version 2>/dev/null || echo 'not installed')"

        return 1
    fi

    echo -e "${GREEN}[✔] Node: $(node --version)${NC}"
    echo -e "${GREEN}[✔] NPM: $(npm --version 2>/dev/null || echo 'unknown')${NC}"

    # -----------------------------------------------------
    # Yarn Classic
    # -----------------------------------------------------

    if command -v yarn >/dev/null 2>&1; then

        CURRENT_YARN="$(yarn --version 2>/dev/null)"

        if [ "$CURRENT_YARN" = "$REQUIRED_YARN_VERSION" ]; then

            echo -e "${GREEN}[✔] Yarn: $CURRENT_YARN${NC}"

        else

            echo -e "${YELLOW}[*] Existing Yarn: $CURRENT_YARN${NC}"
            echo -e "${YELLOW}[*] Switching to Yarn $REQUIRED_YARN_VERSION...${NC}"

            npm install -g "yarn@$REQUIRED_YARN_VERSION"

        fi

    else

        echo -e "${YELLOW}[*] Yarn not found. Installing Yarn Classic...${NC}"

        npm install -g "yarn@$REQUIRED_YARN_VERSION"

    fi

    if ! command -v yarn >/dev/null 2>&1; then

        echo -e "${RED}[✘] Yarn installation failed.${NC}"
        return 1
    fi

    CURRENT_YARN="$(yarn --version 2>/dev/null)"

    if [ "$CURRENT_YARN" != "$REQUIRED_YARN_VERSION" ]; then

        echo -e "${RED}[✘] Wrong Yarn version: $CURRENT_YARN${NC}"
        echo -e "${YELLOW}    Required: $REQUIRED_YARN_VERSION${NC}"

        return 1
    fi

    echo -e "${GREEN}[✔] Yarn: $CURRENT_YARN${NC}"

    return 0
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
            --retry 3 \
            --connect-timeout 15 \
            "$BLUEPRINT_RELEASE_URL" \
            -o "$RELEASE_ZIP"

    elif command -v wget >/dev/null 2>&1; then

        wget \
            --tries=3 \
            --timeout=30 \
            -O "$RELEASE_ZIP" \
            "$BLUEPRINT_RELEASE_URL"

    else

        echo -e "${RED}[✘] curl/wget not found.${NC}"
        return 1
    fi

    if [ ! -s "$RELEASE_ZIP" ]; then

        echo -e "${RED}[✘] Blueprint release download failed.${NC}"
        return 1
    fi

    echo -e "${GREEN}[✔] Blueprint release downloaded.${NC}"

    return 0
}

# =========================================================
# EXTRACT RELEASE
# =========================================================

extract_release() {

    cd "$PTERODACTYL_DIRECTORY" || return 1

    echo -e "${YELLOW}[*] Testing release.zip...${NC}"

    if ! unzip -t "$RELEASE_ZIP" >/dev/null 2>&1; then

        echo -e "${RED}[✘] release.zip is corrupted.${NC}"
        return 1
    fi

    echo -e "${GREEN}[✔] release.zip is valid.${NC}"

    echo -e "${YELLOW}[*] Extracting Blueprint release...${NC}"

    unzip -q -o "$RELEASE_ZIP"

    if [ $? -ne 0 ]; then

        echo -e "${RED}[✘] Failed to extract Blueprint release.${NC}"
        return 1
    fi

    echo -e "${GREEN}[✔] Release extracted.${NC}"

    return 0
}

# =========================================================
# BACKUP PACKAGE LOCK
# =========================================================

handle_package_lock() {

    cd "$PTERODACTYL_DIRECTORY" || return 1

    if [ -f package-lock.json ]; then

        BACKUP_NAME="package-lock.json.backup-$(date +%Y%m%d-%H%M%S)"

        echo -e "${YELLOW}[*] Backing up package-lock.json...${NC}"

        cp -a package-lock.json "$BACKUP_NAME"

        if [ $? -eq 0 ]; then

            rm -f package-lock.json

            echo -e "${GREEN}[✔] package-lock.json backed up:${NC}"
            echo "    $BACKUP_NAME"

        else

            echo -e "${RED}[✘] Could not backup package-lock.json.${NC}"
            return 1
        fi

    fi

    return 0
}

# =========================================================
# REPAIR BLUEPRINT
# =========================================================

repair_blueprint_files() {

    echo -e "${YELLOW}[*] Repairing Blueprint files...${NC}"

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

        if [ -d "$TMP_DIR/blueprint/extensions/blueprint/private" ]; then

            cp -a \
                "$TMP_DIR/blueprint/extensions/blueprint/private" \
                "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/"

        fi

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
            2>/dev/null || \
        touch "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt"

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

    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/.blueprint" \
        2>/dev/null || true

    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" \
        2>/dev/null || true

    echo -e "${GREEN}[✔] Blueprint repair completed.${NC}"
}

# =========================================================
# DEPENDENCIES
# =========================================================

install_dependencies() {

    cd "$PTERODACTYL_DIRECTORY" || return 1

    if [ ! -f package.json ]; then

        echo -e "${YELLOW}[!] package.json not found. Skipping Yarn.${NC}"
        return 0
    fi

    echo ""
    echo -e "${GOLD}${BOLD}===== NODE DEPENDENCY INSTALL =====${NC}"
    echo ""

    # -----------------------------------------------------
    # Make sure Node 22+ is active
    # -----------------------------------------------------

    CURRENT_MAJOR="$(node_major_version)"

    if [ "$CURRENT_MAJOR" -lt "$REQUIRED_NODE_MAJOR" ]; then

        echo -e "${RED}[✘] Node.js 22+ required.${NC}"
        echo "    Current: $(node --version 2>/dev/null || echo 'unknown')"

        return 1
    fi

    # -----------------------------------------------------
    # Make sure Yarn exists
    # -----------------------------------------------------

    if ! command -v yarn >/dev/null 2>&1; then

        echo -e "${RED}[✘] Yarn is not installed.${NC}"
        return 1
    fi

    echo -e "${CYAN}Node:${NC} $(node --version)"
    echo -e "${CYAN}Yarn:${NC} $(yarn --version)"
    echo ""

    # -----------------------------------------------------
    # package-lock warning solved by backup/removal
    # -----------------------------------------------------

    if [ -f package-lock.json ]; then

        echo -e "${YELLOW}[!] package-lock.json exists.${NC}"
        echo "    Yarn will be used as the only package manager."

        handle_package_lock || return 1
    fi

    # -----------------------------------------------------
    # Check Yarn lockfile
    # -----------------------------------------------------

    if [ ! -f yarn.lock ]; then

        echo -e "${RED}[✘] yarn.lock is missing.${NC}"
        echo "    Blueprint release should contain yarn.lock."

        return 1
    fi

    echo -e "${GREEN}[✔] yarn.lock found.${NC}"
    echo ""

    # -----------------------------------------------------
    # Install
    # -----------------------------------------------------

    echo -e "${YELLOW}[*] Installing panel dependencies with Yarn...${NC}"
    echo ""

    yarn install \
        --frozen-lockfile \
        --non-interactive

    YARN_RESULT=$?

    echo ""

    if [ "$YARN_RESULT" -ne 0 ]; then

        echo -e "${RED}==============================================${NC}"
        echo -e "${RED}[✘] Yarn dependency installation FAILED.${NC}"
        echo -e "${RED}==============================================${NC}"
        echo ""

        echo -e "${YELLOW}Node:${NC} $(node --version)"
        echo -e "${YELLOW}Yarn:${NC} $(yarn --version)"

        return 1
    fi

    echo -e "${GREEN}==============================================${NC}"
    echo -e "${GREEN}[✔] Yarn dependencies installed successfully.${NC}"
    echo -e "${GREEN}==============================================${NC}"

    return 0
}

# =========================================================
# BLUEPRINT CLI
# =========================================================

ensure_blueprint_cli() {

    if [ -e "$BLUEPRINT_CLI" ]; then

        chmod 755 "$BLUEPRINT_CLI"
        chown root:root "$BLUEPRINT_CLI"

        echo -e "${GREEN}[✔] Blueprint CLI ready.${NC}"

        return 0
    fi

    echo -e "${YELLOW}[!] Blueprint CLI not found at:${NC}"
    echo "    $BLUEPRINT_CLI"
    echo ""

    echo -e "${GRAY}Blueprint CLI should be created by the Blueprint installation.${NC}"

    return 1
}

# =========================================================
# BLUEPRINT SCRIPT
# =========================================================

run_blueprint_script() {

    if [ ! -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then

        echo -e "${RED}[✘] blueprint.sh not found.${NC}"
        return 1
    fi

    chmod 755 "$PTERODACTYL_DIRECTORY/blueprint.sh"

    chown "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/blueprint.sh"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    echo -e "${YELLOW}[*] Running Blueprint process...${NC}"
    echo ""

    bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

    RESULT=$?

    echo ""

    if [ "$RESULT" -eq 0 ]; then

        echo -e "${GREEN}[✔] Blueprint process completed.${NC}"

    else

        echo -e "${YELLOW}[!] Blueprint process exited with code: $RESULT${NC}"

    fi

    return "$RESULT"
}

# =========================================================
# PERMISSIONS
# =========================================================

fix_permissions() {

    echo -e "${YELLOW}[*] Fixing permissions...${NC}"

    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/.blueprint" \
        2>/dev/null || true

    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" \
        2>/dev/null || true

    if [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then

        chmod 755 \
            "$PTERODACTYL_DIRECTORY/blueprint.sh"

    fi

    if [ -e "$BLUEPRINT_CLI" ]; then

        chown root:root "$BLUEPRINT_CLI"
        chmod 755 "$BLUEPRINT_CLI"

    fi

    echo -e "${GREEN}[✔] Permissions fixed.${NC}"
}

# =========================================================
# LARAVEL CACHE
# =========================================================

clear_laravel_cache() {

    cd "$PTERODACTYL_DIRECTORY" || return 0

    if [ -f artisan ]; then

        echo -e "${YELLOW}[*] Clearing Laravel cache...${NC}"

        php artisan optimize:clear

        if [ $? -eq 0 ]; then

            echo -e "${GREEN}[✔] Laravel cache cleared.${NC}"

        else

            echo -e "${YELLOW}[!] Laravel cache returned an error.${NC}"

        fi

    fi
}

# =========================================================
# THEMES
# =========================================================

open_theme_manager() {

    show_banner

    echo -e "${GOLD}${BOLD}🎨 BLUEPRINT THEMES${NC}"
    echo ""
    echo -e "${GRAY}Loading Theme Manager...${NC}"
    echo ""

    if ! command -v wget >/dev/null 2>&1 && \
       ! command -v curl >/dev/null 2>&1; then

        echo -e "${RED}[!] wget/curl is not installed.${NC}"

        pause_return
        return
    fi

    rm -f "$THEME_TEMP"

    echo -e "${YELLOW}[*] Downloading theme manager...${NC}"

    if command -v curl >/dev/null 2>&1; then

        curl -fLs \
            "$THEME_SCRIPT_URL" \
            -o "$THEME_TEMP"

        DOWNLOAD_RESULT=$?

    else

        wget -q \
            "$THEME_SCRIPT_URL" \
            -O "$THEME_TEMP"

        DOWNLOAD_RESULT=$?

    fi

    if [ "$DOWNLOAD_RESULT" -ne 0 ] || [ ! -s "$THEME_TEMP" ]; then

        echo ""
        echo -e "${RED}[✘] Failed to download theme.sh${NC}"
        echo -e "${GRAY}$THEME_SCRIPT_URL${NC}"

        rm -f "$THEME_TEMP"

        pause_return
        return
    fi

    chmod 700 "$THEME_TEMP"

    echo -e "${GREEN}[✔] Theme Manager loaded.${NC}"
    echo ""

    bash "$THEME_TEMP"

    rm -f "$THEME_TEMP"

    echo ""
    read -rp "Press Enter to return to Blueprint Manager..." _

    show_menu
}

# =========================================================
# ZYREXHOST EXTENSION INSTALLER
# =========================================================

open_extension_installer() {

    while true; do

        show_banner

        echo -e "${GOLD}${BOLD}╭──────────────────────────────────────────────────────────╮${NC}"
        echo -e "${GOLD}${BOLD}│              ZYREXHOST EXTENSION INSTALLER              │${NC}"
        echo -e "${GOLD}${BOLD}╰──────────────────────────────────────────────────────────╯${NC}"
        echo ""

        echo -e "${GREEN}[1]${NC} 📥 Install"
        echo -e "${RED}[0]${NC} ↩ Back to Main Menu"
        echo ""

        read -rp "⚡ Select Option [0-1]: " extension_choice

        case "$extension_choice" in

            1)

                clear

                echo -e "${GOLD}${BOLD}╭──────────────────────────────────────────────────────────╮${NC}"
                echo -e "${GOLD}${BOLD}│              ZYREXHOST EXTENSION INSTALLER              │${NC}"
                echo -e "${GOLD}${BOLD}╰──────────────────────────────────────────────────────────╯${NC}"
                echo ""

                echo -e "${YELLOW}[*] Preparing extension installer...${NC}"
                echo ""

                if ! command -v curl >/dev/null 2>&1 && \
                   ! command -v wget >/dev/null 2>&1; then

                    echo -e "${YELLOW}[*] Installing curl and wget...${NC}"

                    apt-get update -y >/dev/null 2>&1

                    apt-get install -y \
                        curl \
                        wget \
                        >/dev/null 2>&1
                fi

                rm -f "$EXTENSION_TEMP"

                echo -e "${YELLOW}[*] Downloading ZYREXHOST extension installer...${NC}"
                echo ""

                DOWNLOAD_RESULT=1

                if command -v curl >/dev/null 2>&1; then

                    curl -fLs \
                        "$EXTENSION_SCRIPT_URL" \
                        -o "$EXTENSION_TEMP"

                    DOWNLOAD_RESULT=$?

                elif command -v wget >/dev/null 2>&1; then

                    wget -q \
                        "$EXTENSION_SCRIPT_URL" \
                        -O "$EXTENSION_TEMP"

                    DOWNLOAD_RESULT=$?

                fi

                if [ "$DOWNLOAD_RESULT" -ne 0 ] || \
                   [ ! -s "$EXTENSION_TEMP" ]; then

                    echo ""
                    echo -e "${RED}[✘] Failed to download extension.sh${NC}"
                    echo ""
                    echo -e "${GRAY}$EXTENSION_SCRIPT_URL${NC}"
                    echo ""

                    rm -f "$EXTENSION_TEMP"

                    read -rp "Press Enter to return..." _
                    continue
                fi

                chmod 700 "$EXTENSION_TEMP"

                echo -e "${GREEN}[✔] ZYREXHOST Extension Installer downloaded.${NC}"
                echo ""

                echo -e "${CYAN}[*] Starting extension installer...${NC}"
                echo ""

                bash "$EXTENSION_TEMP"

                EXTENSION_RESULT=$?

                rm -f "$EXTENSION_TEMP"

                echo ""

                if [ "$EXTENSION_RESULT" -eq 0 ]; then

                    echo -e "${GREEN}[✔] ZYREXHOST extension installer finished successfully.${NC}"

                else

                    echo -e "${YELLOW}[!] ZYREXHOST extension installer exited with code: $EXTENSION_RESULT${NC}"

                fi

                echo ""

                read -rp "Press Enter to return to Extension Installer..." _

                ;;

            0)

                return
                ;;

            *)

                echo ""
                echo -e "${RED}[!] Invalid option.${NC}"
                sleep 1

                ;;

        esac

    done
}

# =========================================================
# VERIFY
# =========================================================

verify_installation() {

    echo ""
    echo -e "${GOLD}${BOLD}===== BLUEPRINT VERIFICATION =====${NC}"
    echo ""

    PASS=0
    FAIL=0

    # Framework
    if [ -d "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" ]; then
        echo -e "${GREEN}[✔] BlueprintFramework exists${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✘] BlueprintFramework missing${NC}"
        FAIL=$((FAIL+1))
    fi

    # extensionfs
    if [ -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/extensionfs.php" ]; then
        echo -e "${GREEN}[✔] extensionfs.php exists${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✘] extensionfs.php missing${NC}"
        FAIL=$((FAIL+1))
    fi

    # logs
    if [ -f "$PTERODACTYL_DIRECTORY/.blueprint/extensions/blueprint/private/debug/logs.txt" ]; then
        echo -e "${GREEN}[✔] logs.txt exists${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✘] logs.txt missing${NC}"
        FAIL=$((FAIL+1))
    fi

    # emblem
    if [ -s "$PTERODACTYL_DIRECTORY/.blueprint/assets/Emblem/emblem.jpg" ]; then
        echo -e "${GREEN}[✔] emblem.jpg exists${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✘] emblem.jpg missing/empty${NC}"
        FAIL=$((FAIL+1))
    fi

    # blueprint.sh
    if [ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then
        echo -e "${GREEN}[✔] blueprint.sh exists${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✘] blueprint.sh missing${NC}"
        FAIL=$((FAIL+1))
    fi

    # CLI
    if [ -x "$BLUEPRINT_CLI" ]; then
        echo -e "${GREEN}[✔] Blueprint CLI executable${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}[✘] Blueprint CLI not executable${NC}"
        FAIL=$((FAIL+1))
    fi

    # Node
    if command -v node >/dev/null 2>&1; then

        NODE_MAJOR="$(node_major_version)"

        if [ "$NODE_MAJOR" -ge "$REQUIRED_NODE_MAJOR" ]; then
            echo -e "${GREEN}[✔] Node.js $(node --version)${NC}"
            PASS=$((PASS+1))
        else
            echo -e "${RED}[✘] Node.js 22+ required: $(node --version)${NC}"
            FAIL=$((FAIL+1))
        fi

    else

        echo -e "${RED}[✘] Node.js not installed${NC}"
        FAIL=$((FAIL+1))

    fi

    # Yarn
    if command -v yarn >/dev/null 2>&1; then

        YARN_VERSION="$(yarn --version 2>/dev/null)"

        if [ "$YARN_VERSION" = "$REQUIRED_YARN_VERSION" ]; then
            echo -e "${GREEN}[✔] Yarn $YARN_VERSION${NC}"
            PASS=$((PASS+1))
        else
            echo -e "${YELLOW}[!] Yarn $YARN_VERSION${NC}"
            FAIL=$((FAIL+1))
        fi

    else

        echo -e "${RED}[✘] Yarn not installed${NC}"
        FAIL=$((FAIL+1))

    fi

    echo ""

    if [ -f "$PTERODACTYL_DIRECTORY/artisan" ]; then

        php "$PTERODACTYL_DIRECTORY/artisan" --version

    fi

    echo ""
    echo -e "${GOLD}----------------------------------${NC}"
    echo -e "${GREEN}PASS: $PASS${NC}"
    echo -e "${RED}FAIL: $FAIL${NC}"
    echo -e "${GOLD}----------------------------------${NC}"
    echo ""
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

    if ! setup_node_yarn; then
        pause_return
        return
    fi

    if ! fix_docker_path; then
        pause_return
        return
    fi

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

    # Remove npm lock before Yarn
    handle_package_lock

    if ! install_dependencies; then
        echo -e "${RED}[✘] Dependency installation failed.${NC}"
        pause_return
        return
    fi

    fix_permissions

    echo ""
    echo -e "${GREEN}[✔] Pre-installation completed.${NC}"
    echo ""

    if ! run_blueprint_script; then

        echo ""
        echo -e "${YELLOW}[!] Blueprint script returned an error.${NC}"

    fi

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

    if ! fix_docker_path; then
        pause_return
        return
    fi

    write_blueprintrc
    create_blueprint_structure

    if ! setup_node_yarn; then
        pause_return
        return
    fi

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

    handle_package_lock

    if ! install_dependencies; then

        echo -e "${RED}[✘] Dependency installation failed.${NC}"
        pause_return
        return
    fi

    fix_permissions

    echo ""
    echo -e "${YELLOW}[*] Running Blueprint update process...${NC}"
    echo ""

    if ! run_blueprint_script; then

        echo -e "${YELLOW}[!] Blueprint script returned an error.${NC}"

    fi

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

    echo ""
    echo -e "${GREEN}[✔] Blueprint configuration removed.${NC}"

    pause_return
}

# =========================================================
# REPAIR
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
    clear_laravel_cache

    verify_installation

    echo ""
    echo -e "${GREEN}${BOLD}[✔] Repair completed.${NC}"

    pause_return
}

# =========================================================
# MAIN MENU
# =========================================================

show_menu() {

    show_banner

    echo -e "${PURPLE}╭──────────────────────────────────────────────────────────────────────────╮${NC}"
    echo -e "${PURPLE}│${NC} ${GREEN}[1]${NC} 📥 Install Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${GREEN}[2]${NC} 🗑️  Uninstall Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${GREEN}[3]${NC} 🔄 Update Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${GREEN}[4]${NC} 🎨 Themes"
    echo -e "${PURPLE}│${NC} ${GREEN}[5]${NC} 📦 Extensions"
    echo -e "${PURPLE}│${NC} ${GREEN}[6]${NC} 🛠️  Repair Blueprint Framework"
    echo -e "${PURPLE}│${NC} ${RED}[7]${NC} ❌ Exit"
    echo -e "${PURPLE}╰──────────────────────────────────────────────────────────────────────────╯${NC}"

    echo ""
    echo -ne "${CYAN}⚡ Select Option [1-7]: ${NC}"
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
            open_theme_manager
            ;;

        5)
            open_extension_installer
            ;;

        6)
            repair_only
            ;;

        7)
            echo ""
            echo -e "${GREEN}[✔] Goodbye!${NC}"
            exit 0
            ;;

        *)
            echo ""
            echo -e "${RED}[!] Invalid option.${NC}"
            sleep 1
            show_menu
            ;;

    esac
}

# =========================================================
# START
# =========================================================

show_menu
