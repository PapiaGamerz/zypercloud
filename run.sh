#!/bin/bash

# ====================================================
#          APOTHEOSIS CONTROL CENTER v2.1
# ====================================================

# --- COLORS & STYLING ---
RED='\033[38;5;196m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;214m'
BLUE='\033[38;5;33m'
PURPLE='\033[38;5;141m'
CYAN='\033[38;5;51m'
WHITE='\033[38;5;255m'
BOLD='\033[1m'
NC='\033[0m'
GRAY='\033[38;5;242m'
HEADER_LINE="${GRAY}────────────────────────────────────────────────────────────${NC}"

# --- UI HELPER FUNCTIONS ---

show_header() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
█▀█ ▀█▀ █▀▀ █▀█ █▀█ █▀▄ ▄▀█ █▀▀ ▀█▀ █▄█ █░░
█▀▀ ░█░ ██▄ █▀▄ █▄█ █▄▀ █▀█ █▄▄ ░█░ ░█░ █▄▄
EOF
    echo -e "         ${WHITE}⚡ MANAGEMENT SYSTEM v2.1 ⚡${NC}"
    echo -e "${HEADER_LINE}"
    echo -e "  ${GRAY}Module:${NC} ${WHITE}$1${NC}"
    echo -e "${HEADER_LINE}\n"
}

status_msg() {
    case $1 in
        "OK")   echo -e "  ${GREEN}[✔]${NC} $2" ;;
        "ERR")  echo -e "  ${RED}[✘]${NC} $2" ;;
        "INFO") echo -e "  ${BLUE}[ℹ]${NC} $2" ;;
        "WAIT") echo -e "  ${YELLOW}[⏳]${NC} $2" ;;
    esac
}

pause() {
    echo -e "\n${HEADER_LINE}"
    read -p "  Press [Enter] to return to dashboard..."
}

# ================== INSTALL FUNCTION ==================
install_ptero() {
    show_header "PANEL INSTALLATION"
    status_msg "INFO" "Initiating automated installation sequence..."
    sleep 1
    
    bash <(curl -s https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/installed.sh)
    
    echo ""
    status_msg "OK" "Installation Sequence Complete."
    pause
}

# ================== CREATE USER ==================
create_user() {
    show_header "USER MANAGEMENT"

    if [ ! -d /var/www/pterodactyl ]; then
        status_msg "ERR" "Panel directory not found (/var/www/pterodactyl)."
        status_msg "ERR" "Please run a fresh installation first."
        pause
        return
    fi

    echo -e "  ${PURPLE}•${NC} ${WHITE}Select Creation Mode:${NC}"
    echo -e "    ${GRAY}1.${NC} Custom User Create (Interactive)"
    echo -e "    ${GRAY}2.${NC} Auto Create Admin User (Randomized Credentials)"
    echo ""
    read -p "  ╰─> Choose option [1-2]: " choice

    cd /var/www/pterodactyl || exit

    if [ "$choice" = "1" ]; then
        status_msg "WAIT" "Launching manual user creation..."
        php artisan p:user:make

    elif [ "$choice" = "2" ]; then
        status_msg "WAIT" "Generating secure auto admin user..."

        USERNAME="user$(openssl rand -hex 2)"
        PASSWORD="$(openssl rand -base64 10)"
        EMAIL="$(openssl rand -base64 4)@email.com"
        FIRST="$(openssl rand -base64 6)"
        LAST="$(openssl rand -base64 4)"
        
        php artisan p:user:make -n \
            --email=${EMAIL} \
            --username=${USERNAME} \
            --password=${PASSWORD} \
            --admin=1 \
            --name-first=${FIRST} \
            --name-last=${LAST}

        echo ""
        status_msg "OK" "Auto Admin Created Successfully!"
        echo -e "  ${GRAY}────────────────────────────────────────${NC}"
        echo -e "  ${GRAY}Username :${NC} ${WHITE}$USERNAME${NC}"
        echo -e "  ${GRAY}Password :${NC} ${WHITE}$PASSWORD${NC}"
        echo -e "  ${GRAY}Email    :${NC} ${WHITE}$EMAIL${NC}"
        echo -e "  ${GRAY}────────────────────────────────────────${NC}"
    else
        status_msg "ERR" "Invalid option selected."
    fi

    pause
}

# ================= PANEL UNINSTALL =================
uninstall_logic() {
    status_msg "WAIT" "Stopping Panel background services..."
    systemctl stop pteroq.service 2>/dev/null || true
    systemctl disable pteroq.service 2>/dev/null || true
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload

    status_msg "WAIT" "Removing cronjobs..."
    crontab -l | grep -v 'php /var/www/pterodactyl/artisan schedule:run' | crontab - || true

    status_msg "WAIT" "Purging panel web root files..."
    rm -rf /var/www/pterodactyl

    status_msg "WAIT" "Dropping database and secure users..."
    mysql -u root -e "DROP DATABASE IF EXISTS panel;"
    mysql -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
    mysql -u root -e "FLUSH PRIVILEGES;"

    status_msg "WAIT" "Cleaning Nginx site configurations..."
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    systemctl reload nginx || true
}

uninstall_ptero() {
    show_header "SYSTEM UNINSTALLATION"
    
    echo -e "  ${RED}⚠ WARNING: This will permanently wipe all panel data & databases!${NC}"
    read -p "  Are you sure you want to proceed? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        status_msg "INFO" "Uninstallation aborted."
        pause
        return
    fi

    echo ""
    uninstall_logic
    
    echo ""
    status_msg "OK" "Panel removed cleanly (Wings node remains safe)."
    pause
}

# ================= UPDATE FUNCTION =================
update_panel() {
    show_header "PANEL SYSTEM UPDATE"

    if [ ! -d /var/www/pterodactyl ]; then
        status_msg "ERR" "Panel installation not found in /var/www/pterodactyl"
        pause
        return
    fi

    status_msg "INFO" "Enabling maintenance mode..."
    cd /var/www/pterodactyl
    php artisan down

    GITHUB_REPO="pterodactyl/panel"

    fetch_github_versions() {
        local repo=$1
        local json
        json=$(curl -sf "https://api.github.com/repos/$repo/releases?per_page=20" 2>/dev/null) || return 1
        echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data:
    if r.get('prerelease', False): continue
    tag = r.get('tag_name', '')
    if tag.startswith('v'): print(tag)
" 2>/dev/null || return 1
    }

    echo -e "\n  ${PURPLE}✦${NC} ${WHITE}Available Panel Release Versions${NC}"
    local tags=() disp=() i=0
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        tags+=("$tag")
        i=$((i+1))
        disp+=("  ${GRAY}$i.${NC} ${WHITE}$tag${NC}")
    done < <(fetch_github_versions "$GITHUB_REPO" 2>/dev/null) || true

    if [[ ${#tags[@]} -eq 0 ]]; then
        version_PANEL="latest"
    else
        printf '%b\n' "${disp[@]}"
        local max=${#tags[@]}
        echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Select version [1-$max]${NC} ${GRAY}[1 = latest]${NC}\n  ${GRAY}╰─>${NC} "
        if ! read -t 10 choice; then
            echo -e "\n  ${GOLD}⌛ Timeout — using latest release.${NC}"
            version_PANEL="${tags[0]}"
        elif [[ -z "$choice" || "$choice" == "1" ]]; then
            version_PANEL="${tags[0]}"
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $max ]]; then
            version_PANEL="${tags[$((choice - 1))]}"
        else
            version_PANEL="${tags[0]}"
        fi
    fi

    echo -e "\n  ${GOLD}╔═[ UPDATE TARGET ]═════════════════════════════════════╗${NC}"
    echo -e "  ${GOLD}║${NC} ${GRAY}Target Version:${NC} ${WHITE}$version_PANEL${NC}"
    echo -e "  ${GOLD}╚═══════════════════════════════════════════════════════╝${NC}"

    echo -ne "\n  ${CYAN}Proceed with update?${NC} ${WHITE}(Y/n)${NC} ${GRAY}[auto in 10s]:${NC} "
    if ! read -t 10 -n 1 -r CONFIRM; then
        CONFIRM="y"
        echo -e "\n  ${GOLD}⌛ Timeout — proceeding automatically...${NC}"
    fi
    echo ""

    if [[ "$CONFIRM" =~ [Nn] ]]; then
        status_msg "INFO" "Update cancelled by user."
        php artisan up
        pause
        return
    fi

    status_msg "WAIT" "Purging old core files & downloading new release..."
    sudo rm -rf /var/www/pterodactyl/*
    cd /var/www/pterodactyl

    if [[ "$version_PANEL" == "latest" ]]; then
        curl -Lso panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    else
        curl -Lso panel.tar.gz "https://github.com/pterodactyl/panel/releases/download/${version_PANEL}/panel.tar.gz"
    fi
    
    tar -xzf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/

    status_msg "WAIT" "Installing Composer dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
    
    status_msg "WAIT" "Executing migrations & cache clears..."
    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    status_msg "WAIT" "Restarting queue worker & bringing panel online..."
    php artisan queue:restart
    php artisan up

    echo ""
    status_msg "OK" "Panel Updated Successfully."
    pause
}

# ===================== MAIN MENU =====================
while true; do
    clear
    echo -e "${CYAN}"
    cat << "EOF"
█▀█ ▀█▀ █▀▀ █▀█ █▀█ █▀▄ ▄▀█ █▀▀ ▀█▀ █▄█ █░░
█▀▀ ░█░ ██▄ █▀▄ █▄█ █▄▀ █▀█ █▄▄ ░█░ ░█░ █▄▄
EOF
    echo -e "         ${WHITE}⚡ CONTROL CENTER DASHBOARD ⚡${NC}"
    echo -e "${HEADER_LINE}"

    # --- CHECK INSTALL STATUS ---
    if [ -d "/var/www/pterodactyl" ]; then
        echo -e "  ${GRAY}Status :${NC} ${GREEN}INSTALLED [✔]${NC}"
    else
        echo -e "  ${GRAY}Status :${NC} ${RED}NOT INSTALLED [✘]${NC}"
    fi
    echo -e "${HEADER_LINE}"

    echo -e "  ${GREEN}[1]${NC} Install     ${GRAY}:: Fresh Panel Deployment${NC}"
    echo -e "  ${GREEN}[2]${NC} User        ${GRAY}:: Manage Admins & Users${NC}"
    echo -e "  ${YELLOW}[3]${NC} Update      ${GRAY}:: Upgrade to Latest Release${NC}"
    echo -e "  ${BLUE}[4]${NC} Domain/SSL  ${GRAY}:: Configure Domain & SSL Certs${NC}"
    echo -e "  ${PURPLE}[5]${NC} phpMyAdmin  ${GRAY}:: Database Web Interface${NC}"
    echo -e "  ${RED}[6]${NC} Uninstall   ${GRAY}:: Clean Remove Panel Data${NC}"
    echo -e ""
    echo -e "  ${WHITE}[0]${NC} Exit System"
    echo -e "${HEADER_LINE}"
    
    echo -ne "  ${BOLD}${WHITE}root@apotheosis:~# ${NC}"
    read choice

    case $choice in
        1) install_ptero ;;
        2) create_user ;;
        3) update_panel ;;
        4) bash <(curl -fsSL https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/ssl.sh) ;;
        5) bash <(curl -fsSL https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/phpMyAdmin.sh) ;;
        6) uninstall_ptero ;;
        0) clear; exit ;;
        *) echo -e "\n  ${RED}⚠ Invalid option selected!${NC}"; sleep 1 ;;
    esac
done
