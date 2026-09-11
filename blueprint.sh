```bash
#!/bin/bash

# =========================================================
# BLUEPRINT FRAMEWORK MANAGER
# Docker + Pterodactyl /var/www/pterodactyl
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

# Theme Manager
THEME_SCRIPT_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/theme.sh"

# ZYREXHOST Extension Installer
EXTENSION_SCRIPT_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/extension.sh"

BLUEPRINT_CLI="/usr/local/bin/blueprint"
RELEASE_ZIP="$PTERODACTYL_DIRECTORY/release.zip"

THEME_TEMP="/tmp/blueprint-theme-manager.sh"
EXTENSION_TEMP="/tmp/zyrexhost-extension-installer.sh"

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

    return 0
}

# =========================================================
# BLUEPRINT CLI
# =========================================================

ensure_blueprint_cli() {

    if [ -e "$BLUEPRINT_CLI" ]; then

        chmod 755 "$BLUEPRINT_CLI"
        chown root:root "$BLUEPRINT_CLI"

        return 0
    fi

    echo -e "${YELLOW}[!] Blueprint CLI not found at:${NC}"
    echo "    $BLUEPRINT_CLI"
    echo ""

    echo -e "${GRAY}Blueprint CLI is normally created by the Blueprint installation.${NC}"

    return 1
}

# =========================================================
# DOCKER /APP
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

        echo -e "${GRAY}[*] Docker not detected.${NC}"

    fi
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

        echo -e "${RED}[!] release.zip is corrupted.${NC}"
        return 1
    fi

    echo -e "${YELLOW}[*] Extracting Blueprint release...${NC}"

    unzip -q -o "$RELEASE_ZIP"

    echo -e "${GREEN}[✔] Release extracted.${NC}"

    return 0
}

# =========================================================
# REPAIR BLUEPRINT
# =========================================================

repair_blueprint_files() {

    echo -e "${YELLOW}[*] Repairing Blueprint files...${NC}"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    # Framework
    if [ ! -d "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" ]; then

        echo -e "${YELLOW}[!] BlueprintFramework missing. Restoring...${NC}"

        unzip -q -o \
            "$RELEASE_ZIP" \
            'app/BlueprintFramework/*' \
            -d "$PTERODACTYL_DIRECTORY"

    fi

    # Extension filesystem
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

    # Logs
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

    # Database files
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

    # Emblem
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

    # Permissions
    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/.blueprint" \
        2>/dev/null || true

    chown -R "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/app/BlueprintFramework" \
        2>/dev/null || true

    echo -e "${GREEN}[✔] Blueprint repair completed.${NC}"
}

# =========================================================
# NODE + YARN
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

    cd "$PTERODACTYL_DIRECTORY" || return 1

    if [ -f package.json ]; then

        echo -e "${YELLOW}[*] Installing panel dependencies...${NC}"

        yarn install --ignore-engines

        if [ $? -ne 0 ]; then

            echo -e "${YELLOW}[!] Yarn failed. Trying npm fallback...${NC}"

            npm install --legacy-peer-deps

        fi

    fi
}

# =========================================================
# BLUEPRINT SCRIPT
# =========================================================

run_blueprint_script() {

    if [ ! -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]; then

        echo -e "${RED}[!] blueprint.sh not found.${NC}"
        return 1
    fi

    chmod 755 "$PTERODACTYL_DIRECTORY/blueprint.sh"

    chown "$OWNERSHIP" \
        "$PTERODACTYL_DIRECTORY/blueprint.sh"

    cd "$PTERODACTYL_DIRECTORY" || return 1

    echo -e "${YELLOW}[*] Running Blueprint process...${NC}"

    bash "$PTERODACTYL_DIRECTORY/blueprint.sh"

    return $?
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

    chmod 755 \
        "$PTERODACTYL_DIRECTORY/blueprint.sh" \
        2>/dev/null || true

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
# ===================== THEMES ============================
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

    else

        wget -q \
            "$THEME_SCRIPT_URL" \
            -O "$THEME_TEMP"

    fi

    if [ ! -s "$THEME_TEMP" ]; then

        echo ""
        echo -e "${RED}[✘] Failed to download theme.sh${NC}"
        echo -e "${GRAY}$THEME_SCRIPT_URL${NC}"

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
# ============= ZYREXHOST EXTENSION INSTALLER =============
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

                # Make sure curl/wget exists
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

                # Run the user's extension.sh
                bash "$EXTENSION_TEMP"

                EXTENSION_RESULT=$?

                # Remove temporary installer
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

        echo -e "${GREEN}[✔] Blueprint CLI executable${NC}"

    else

        echo -e "${RED}[✘] Blueprint CLI not executable${NC}"

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
            sleep 1.5

            show_menu

            ;;

    esac
}

# =========================================================
# START
# =========================================================

show_menu
```
