#!/usr/bin/env bash
# ================================================================
#                     ZYREXPTERO CONTROL CENTER
#                     Modern Pterodactyl Manager
# ================================================================
# Features:
#   • Fresh Pterodactyl installer launcher
#   • User/admin creation
#   • Safe panel updater with version selector
#   • Domain / SSL manager launcher
#   • phpMyAdmin launcher
#   • Safe uninstall with confirmation
#   • Node.js 22 + NVM detection
# ================================================================

set -u
export DEBIAN_FRONTEND=noninteractive

# ----------------------------- Theme -----------------------------
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[38;5;203m'
GREEN='\033[38;5;114m'
YELLOW='\033[38;5;221m'
BLUE='\033[38;5;117m'
CYAN='\033[38;5;81m'
PURPLE='\033[38;5;141m'
WHITE='\033[38;5;255m'
GRAY='\033[38;5;245m'
DARK='\033[38;5;238m'

PANEL_DIR="/var/www/pterodactyl"
PTERO_SERVICE="pteroq.service"
GITHUB_REPO="pterodactyl/panel"

# External helpers retained from the original manager.
INSTALLER_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/installed.sh"
DOMAIN_SSL_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/wings.sh"
PHPMYADMIN_URL="https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/phpMyAdmin.sh"

trap 'printf "\n%s\n" "${GRAY}Tip: run the manager again any time with: sudo bash $0${RESET}"' EXIT

# --------------------------- Utilities ---------------------------
term_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 80)
    (( w < 70 )) && w=70
    echo "$w"
}

line() {
    local ch="${1:--}"
    printf '%*s\n' "$(term_width)" '' | tr ' ' "$ch"
}

title() {
    local text="$1"
    local w
    w=$(term_width)
    clear
    echo
    printf '  %s╭%s╮%s\n' "$PURPLE" "$(printf '─%.0s' $(seq 1 $((w-6))))" "$RESET"
    printf '  %s│%s %s%-*s%s %s│%s\n' "$PURPLE" "$RESET" "$BOLD$WHITE" $((w-10)) "$text" "$RESET" "$PURPLE" "$RESET"
    printf '  %s╰%s╯%s\n' "$PURPLE" "$(printf '─%.0s' $(seq 1 $((w-6))))" "$RESET"
    echo
}

ok()   { printf '  %s✓%s  %s\n' "$GREEN" "$RESET" "$1"; }
err()  { printf '  %s✗%s  %s\n' "$RED" "$RESET" "$1"; }
info() { printf '  %s›%s  %s\n' "$CYAN" "$RESET" "$1"; }
warn() { printf '  %s!%s  %s\n' "$YELLOW" "$RESET" "$1"; }
step() { printf '  %s•%s  %s\n' "$PURPLE" "$RESET" "$1"; }

pause() {
    echo
    read -r -p "  Press Enter to continue..." _
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        err "Please run this manager as root."
        exit 1
    fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

panel_installed() {
    [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/.env" ]]
}

node_major() {
    if command_exists node; then
        node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true
    fi
}

ensure_nvm_node22() {
    step "Checking Node.js..."
    local major
    major="$(node_major)"

    if [[ "$major" == "22" ]]; then
        ok "Node.js 22 is already active: $(node -v)"
        return 0
    fi

    info "Node.js 22 is required for the ZyrexPtero workflow."
    local nvm_dir="${NVM_DIR:-/root/.nvm}"

    export NVM_DIR="$nvm_dir"
    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        step "Installing NVM..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    fi

    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1090
        source "$NVM_DIR/nvm.sh"
    else
        err "NVM installation failed."
        return 1
    fi

    step "Installing Node.js 22..."
    nvm install 22
    step "Activating Node.js 22..."
    nvm use 22
    nvm alias default 22 >/dev/null 2>&1 || true

    mkdir -p /etc/profile.d
    cat >/etc/profile.d/zyrexptero-node.sh <<'EOF'
export NVM_DIR="${NVM_DIR:-/root/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
EOF

    major="$(node_major)"
    if [[ "$major" != "22" ]]; then
        err "Node.js 22 could not be activated."
        return 1
    fi

    ok "Node.js 22 active: $(node -v)"
    return 0
}

install_yarn() {
    ensure_nvm_node22 || return 1
    if command_exists yarn; then
        ok "Yarn detected: $(yarn --version)"
    else
        step "Installing Yarn 1.22.22..."
        npm install -g yarn@1.22.22
        ok "Yarn installed: $(yarn --version)"
    fi
}

# -------------------------- Status card --------------------------
show_status() {
    local panel_state node_state php_state nginx_state
    panel_state="${RED}NOT INSTALLED${RESET}"
    node_state="${RED}missing${RESET}"
    php_state="${RED}missing${RESET}"
    nginx_state="${RED}missing${RESET}"

    panel_installed && panel_state="${GREEN}INSTALLED${RESET}"
    command_exists node && node_state="$(node -v)"
    command_exists php && php_state="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)"
    command_exists nginx && nginx_state="installed"

    printf '  %s┌────────────────────────────────────────────────────┐%s\n' "$DARK" "$RESET"
    printf '  %s│%s  %sPanel      %s  %s\n' "$DARK" "$RESET" "$GRAY" "$RESET" "$panel_state"
    printf '  %s│%s  %sNode       %s  %s\n' "$DARK" "$RESET" "$GRAY" "$RESET" "$node_state"
    printf '  %s│%s  %sPHP        %s  %s\n' "$DARK" "$RESET" "$GRAY" "$RESET" "$php_state"
    printf '  %s│%s  %sNginx      %s  %s\n' "$DARK" "$RESET" "$GRAY" "$RESET" "$nginx_state"
    printf '  %s└────────────────────────────────────────────────────┘%s\n' "$DARK" "$RESET"
}

# -------------------------- Installation -------------------------
install_ptero() {
    title "FRESH PANEL INSTALLATION"
    info "Launching the ZyrexPtero/Pterodactyl installation workflow."
    echo

    if panel_installed; then
        warn "A Pterodactyl panel already exists at $PANEL_DIR."
        read -r -p "  Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "Installation cancelled."; pause; return; }
    fi

    # Make Node 22 available before handing off to the installer.
    if ! install_yarn; then
        err "Node.js 22/Yarn preparation failed."
        pause
        return
    fi

    echo
    step "Starting external installer..."
    if curl -fsSL "$INSTALLER_URL" | bash; then
        ok "Installation sequence finished."
    else
        err "External installer returned an error."
    fi
    pause
}

# --------------------------- User tools ---------------------------
create_user() {
    title "USER MANAGEMENT"

    if ! panel_installed; then
        err "Panel not found at $PANEL_DIR."
        info "Install the panel first."
        pause
        return
    fi

    cd "$PANEL_DIR" || { err "Cannot enter $PANEL_DIR"; pause; return; }

    echo "  ${GREEN}1${RESET}  Create custom user"
    echo "  ${GREEN}2${RESET}  Create random admin user"
    echo
    read -r -p "  Select [1-2]: " choice

    case "$choice" in
        1)
            php artisan p:user:make
            ;;
        2)
            local username password email first last
            username="admin$(openssl rand -hex 2)"
            password="$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)"
            email="${username}@example.com"
            first="Zyrex"
            last="Admin"

            if php artisan p:user:make -n \
                --email="$email" \
                --username="$username" \
                --password="$password" \
                --admin=1 \
                --name-first="$first" \
                --name-last="$last"; then
                echo
                ok "Admin account created."
                printf '  %-12s %s\n' "Username:" "$username"
                printf '  %-12s %s\n' "Password:" "$password"
                printf '  %-12s %s\n' "Email:" "$email"
                warn "Save these credentials securely."
            else
                err "User creation failed."
            fi
            ;;
        *)
            err "Invalid option."
            ;;
    esac
    pause
}

# ---------------------------- Updater -----------------------------
fetch_versions() {
    curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases?per_page=20" |
        python3 -c '
import json,sys
for r in json.load(sys.stdin):
    if not r.get("prerelease") and r.get("tag_name","").startswith("v"):
        print(r["tag_name"])
' 2>/dev/null
}

select_version() {
    local tags=() tag choice idx
    while IFS= read -r tag; do
        [[ -n "$tag" ]] && tags+=("$tag")
    done < <(fetch_versions)

    if ((${#tags[@]} == 0)); then
        warn "Could not fetch release list; latest will be used."
        echo "latest"
        return
    fi

    echo "  ${BOLD}${WHITE}Available releases${RESET}"
    local i=1
    for tag in "${tags[@]}"; do
        printf '  %s%2d%s  %s\n' "$CYAN" "$i" "$RESET" "$tag"
        ((i++))
    done
    echo
    read -r -p "  Select release [1 = latest]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#tags[@]})); then
        idx=$((choice-1))
        echo "${tags[$idx]}"
    else
        echo "${tags[0]}"
    fi
}

update_panel() {
    title "PANEL UPDATE"

    if ! panel_installed; then
        err "Panel not found at $PANEL_DIR."
        pause
        return
    fi

    if ! command_exists composer || ! command_exists curl || ! command_exists tar; then
        err "Required command(s) are missing: composer/curl/tar."
        pause
        return
    fi

    if ! install_yarn; then
        err "Node.js 22/Yarn preparation failed."
        pause
        return
    fi

    local version archive backup
    version="$(select_version)"
    echo
    info "Selected release: $version"
    read -r -p "  Continue with panel update? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Update cancelled."; pause; return; }

    cd "$PANEL_DIR" || { err "Cannot enter $PANEL_DIR"; pause; return; }

    backup="/var/backups/zyrexptero"
    mkdir -p "$backup"
    if [[ -f .env ]]; then
        cp -a .env "$backup/.env.$(date +%Y%m%d-%H%M%S)"
    fi

    step "Enabling maintenance mode..."
    php artisan down || true

    step "Downloading release..."
    archive="$PANEL_DIR/panel.tar.gz"
    if [[ "$version" == "latest" ]]; then
        curl -fLso "$archive" "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    else
        curl -fLso "$archive" "https://github.com/pterodactyl/panel/releases/download/${version}/panel.tar.gz"
    fi

    if [[ ! -s "$archive" ]]; then
        err "Panel archive download failed."
        php artisan up || true
        pause
        return
    fi

    # Preserve .env while replacing application files.
    local env_tmp
    env_tmp="$(mktemp)"
    cp .env "$env_tmp"

    step "Replacing panel application files..."
    find . -mindepth 1 -maxdepth 1 ! -name ".env" ! -name "storage" ! -name "panel.tar.gz" -exec rm -rf {} +
    tar -xzf "$archive"
    rm -f "$archive"
    cp "$env_tmp" .env
    rm -f "$env_tmp"

    step "Installing Composer dependencies..."
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction

    step "Installing frontend dependencies (waiting for Yarn to finish)..."
    # This is intentionally synchronous: the script does not continue until Yarn exits.
    yarn install --frozen-lockfile --non-interactive

    step "Refreshing application..."
    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force

    step "Fixing permissions..."
    chown -R www-data:www-data "$PANEL_DIR"
    chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" 2>/dev/null || true

    step "Restarting workers..."
    php artisan queue:restart || true
    systemctl daemon-reload
    systemctl restart "$PTERO_SERVICE" 2>/dev/null || true
    php artisan up

    ok "Panel update completed successfully."
    pause
}

# --------------------------- Uninstaller --------------------------
uninstall_logic() {
    local env_file="$PANEL_DIR/.env"
    local db_name="panel" db_user="pterodactyl" db_host="127.0.0.1"

    if [[ -f "$env_file" ]]; then
        db_name="$(grep '^DB_DATABASE=' "$env_file" | cut -d= -f2-)"
        db_user="$(grep '^DB_USERNAME=' "$env_file" | cut -d= -f2-)"
        db_host="$(grep '^DB_HOST=' "$env_file" | cut -d= -f2-)"
        [[ -n "$db_name" ]] || db_name="panel"
        [[ -n "$db_user" ]] || db_user="pterodactyl"
        [[ -n "$db_host" ]] || db_host="127.0.0.1"
    fi

    step "Stopping queue worker..."
    systemctl stop "$PTERO_SERVICE" 2>/dev/null || true
    systemctl disable "$PTERO_SERVICE" 2>/dev/null || true
    rm -f "/etc/systemd/system/$PTERO_SERVICE"
    systemctl daemon-reload

    step "Removing panel cron entry..."
    crontab -l 2>/dev/null | grep -v 'artisan schedule:run' | crontab - 2>/dev/null || true

    step "Removing panel files..."
    rm -rf "$PANEL_DIR"

    if command_exists mysql; then
        step "Removing detected database..."
        mysql -u root -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null || true
        mysql -u root -e "DROP USER IF EXISTS '$db_user'@'$db_host';" 2>/dev/null || true
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi

    step "Cleaning Nginx panel configuration..."
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    nginx -t >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null || true

    ok "Pterodactyl panel cleanup completed."
    info "Wings was not removed."
}

uninstall_ptero() {
    title "UNINSTALL PANEL"

    if ! panel_installed && [[ ! -d "$PANEL_DIR" ]]; then
        warn "Panel directory does not exist."
        pause
        return
    fi

    echo -e "  ${RED}${BOLD}WARNING${RESET}"
    echo "  This removes the Pterodactyl panel and its detected database."
    echo "  Wings is NOT removed."
    echo
    read -r -p "  Type REMOVE to continue: " confirm
    if [[ "$confirm" != "REMOVE" ]]; then
        info "Uninstallation cancelled."
        pause
        return
    fi

    echo
    uninstall_logic
    pause
}

# -------------------------- External tools -----------------------
run_external() {
    local label="$1" url="$2"
    title "$label"
    info "Launching external helper..."
    if curl -fsSL "$url" | bash; then
        ok "Helper completed."
    else
        err "Helper returned an error."
    fi
    pause
}

# ------------------------------ Menu ------------------------------
banner() {
    clear
    echo
    echo -e "  ${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${PURPLE}║${RESET} ${WHITE}${BOLD}                 Z Y R E X P T E R O                  ${RESET}${PURPLE}║${RESET}"
    echo -e "  ${PURPLE}║${RESET} ${GRAY}          Modern Pterodactyl Control Center            ${RESET}${PURPLE}║${RESET}"
    echo -e "  ${PURPLE}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo
    show_status
    echo
    echo -e "  ${BOLD}${WHITE}MANAGEMENT${RESET}"
    echo -e "  ${GREEN}[1]${RESET}  Install Panel        ${GRAY}Fresh installation${RESET}"
    echo -e "  ${BLUE}[2]${RESET}  User Management      ${GRAY}Create users/admins${RESET}"
    echo -e "  ${YELLOW}[3]${RESET}  Update Panel          ${GRAY}Upgrade release${RESET}"
    echo -e "  ${CYAN}[4]${RESET}  Domain & SSL          ${GRAY}Domain / certificate${RESET}"
    echo -e "  ${PURPLE}[5]${RESET}  phpMyAdmin             ${GRAY}Database web UI${RESET}"
    echo -e "  ${RED}[6]${RESET}  Uninstall              ${GRAY}Remove panel${RESET}"
    echo
    echo -e "  ${GRAY}────────────────────────────────────────────────────────${RESET}"
    echo -e "  ${WHITE}[0]${RESET}  Exit"
    echo
}

main() {
    require_root

    while true; do
        banner
        read -r -p "  root@zyrexptero:~# " choice
        echo

        case "$choice" in
            1) install_ptero ;;
            2) create_user ;;
            3) update_panel ;;
            4) run_external "DOMAIN & SSL MANAGER" "$DOMAIN_SSL_URL" ;;
            5) run_external "PHPMYADMIN MANAGER" "$PHPMYADMIN_URL" ;;
            6) uninstall_ptero ;;
            0) clear; echo -e "\n  ${GREEN}ZyrexPtero closed.${RESET}\n"; exit 0 ;;
            *) err "Unknown option: $choice"; sleep 1 ;;
        esac
    done
}

main "$@"
