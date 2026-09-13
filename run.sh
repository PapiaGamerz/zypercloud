#!/usr/bin/env bash
# ================================================================
#                     ZYREXPTERO CONTROL CENTER
#                  Modern Pterodactyl Manager v2.0
# ================================================================
# Fixes:
#   • Reliable interactive menu / input handling
#   • Correct release selector (no captured menu output bug)
#   • Node.js 22 + NVM preparation
#   • Synchronous Yarn handling
#   • Safer external installer execution
#   • Better command / OS / service checks
#   • Safer updater with rollback of .env
#   • Nginx / phpMyAdmin helper launcher
#   • Explicit uninstall confirmation
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

INSTALLER_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/installed.sh"
DOMAIN_SSL_URL="https://raw.githubusercontent.com/PapiaGamerz/zypercloud/refs/heads/main/wings.sh"
PHPMYADMIN_URL="https://raw.githubusercontent.com/nobita329/Nobita-Cloud/refs/heads/main/panel/pterodactyl/phpMyAdmin.sh"

NODE_MAJOR="22"
NVM_VERSION="v0.40.3"
YARN_VERSION="1.22.22"

# --------------------------- Utilities ---------------------------
term_width() {
    local w
    w="$(tput cols 2>/dev/null || echo 80)"
    [[ "$w" =~ ^[0-9]+$ ]] || w=80
    (( w < 70 )) && w=70
    echo "$w"
}

ok()   { printf '  %b✓%b  %s\n' "$GREEN" "$RESET" "$*"; }
err()  { printf '  %b✗%b  %s\n' "$RED" "$RESET" "$*" >&2; }
info() { printf '  %b›%b  %s\n' "$CYAN" "$RESET" "$*"; }
warn() { printf '  %b!%b  %s\n' "$YELLOW" "$RESET" "$*"; }
step() { printf '  %b•%b  %s\n' "$PURPLE" "$RESET" "$*"; }

pause() {
    echo
    read -r -p "  Press Enter to continue..." _ || true
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        err "Please run this manager as root."
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

panel_installed() {
    [[ -f "$PANEL_DIR/artisan" && -f "$PANEL_DIR/.env" ]]
}

node_major() {
    if command_exists node; then
        node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true
    else
        true
    fi
}

# Run a remote helper only after checking that curl is available.
run_remote_helper() {
    local label="$1"
    local url="$2"

    title "$label"

    if ! command_exists curl; then
        err "curl is not installed."
        pause
        return 1
    fi

    info "Source: $url"
    echo
    read -r -p "  Run this helper? [y/N]: " confirm || true
    [[ "$confirm" =~ ^[Yy]$ ]] || {
        info "Cancelled."
        pause
        return 0
    }

    echo
    step "Downloading helper..."
    local tmp="/tmp/zyrexptero-helper-$$.sh"

    if ! curl -fsSL --retry 3 --connect-timeout 10 "$url" -o "$tmp"; then
        err "Could not download helper."
        rm -f "$tmp"
        pause
        return 1
    fi

    if [[ ! -s "$tmp" ]]; then
        err "Downloaded helper is empty."
        rm -f "$tmp"
        pause
        return 1
    fi

    step "Launching helper..."
    if bash "$tmp"; then
        ok "Helper completed."
    else
        err "Helper returned an error."
    fi

    rm -f "$tmp"
    pause
}

# -------------------------- Node / Yarn --------------------------
ensure_nvm_node22() {
    step "Checking Node.js ${NODE_MAJOR}..."

    export NVM_DIR="${NVM_DIR:-/root/.nvm}"

    # Load an existing NVM installation first.
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1090
        source "$NVM_DIR/nvm.sh"
    fi

    local major=""
    major="$(node_major)"

    if [[ "$major" == "$NODE_MAJOR" ]]; then
        ok "Node.js ${NODE_MAJOR} already active: $(node -v)"
    else
        info "Active Node.js: ${major:-not installed}"
        step "Installing/activating Node.js ${NODE_MAJOR} with NVM..."

        if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
            curl -fsSL --retry 3 \
                "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

            [[ -s "$NVM_DIR/nvm.sh" ]] || {
                err "NVM installation failed."
                return 1
            }

            # shellcheck disable=SC1090
            source "$NVM_DIR/nvm.sh"
        fi

        nvm install "$NODE_MAJOR"
        nvm use "$NODE_MAJOR"
        nvm alias default "$NODE_MAJOR" >/dev/null 2>&1 || true
    fi

    hash -r 2>/dev/null || true

    major="$(node_major)"
    if [[ "$major" != "$NODE_MAJOR" ]]; then
        err "Node.js ${NODE_MAJOR} activation failed. Current: ${major:-unknown}"
        return 1
    fi

    mkdir -p /etc/profile.d
    cat > /etc/profile.d/zyrexptero-node.sh <<'EOF'
export NVM_DIR="/root/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm use 22 >/dev/null 2>&1 || true
fi
EOF

    ok "Node.js active: $(node -v)"
    return 0
}

install_yarn() {
    ensure_nvm_node22 || return 1

    local yarn_major=""
    if command_exists yarn; then
        yarn_major="$(yarn --version 2>/dev/null || true)"
    fi

    if [[ "$yarn_major" == 1.* ]]; then
        ok "Yarn ${yarn_major} already installed."
    else
        step "Installing Yarn ${YARN_VERSION}..."
        npm install --global "yarn@${YARN_VERSION}" || {
            err "Yarn installation failed."
            return 1
        }
    fi

    hash -r 2>/dev/null || true
    yarn_major="$(yarn --version 2>/dev/null || true)"

    [[ "$yarn_major" == 1.* ]] || {
        err "Expected Yarn 1.x, found: ${yarn_major:-unknown}"
        return 1
    }

    ok "Yarn active: ${yarn_major}"
    return 0
}

# -------------------------- Status card --------------------------
show_status() {
    local panel_state node_state php_state nginx_state redis_state queue_state
    panel_state="${RED}NOT INSTALLED${RESET}"
    node_state="${RED}missing${RESET}"
    php_state="${RED}missing${RESET}"
    nginx_state="${RED}missing${RESET}"
    redis_state="${GRAY}unknown${RESET}"
    queue_state="${GRAY}unknown${RESET}"

    panel_installed && panel_state="${GREEN}INSTALLED${RESET}"
    command_exists node && node_state="$(node -v)"
    command_exists php && php_state="$(php -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)"
    command_exists nginx && nginx_state="${GREEN}installed${RESET}"
    command_exists systemctl && redis_state="$(systemctl is-active redis-server 2>/dev/null || echo inactive)"
    command_exists systemctl && queue_state="$(systemctl is-active "$PTERO_SERVICE" 2>/dev/null || echo inactive)"

    printf '  %b┌────────────────────────────────────────────────────────┐%b\n' "$DARK" "$RESET"
    printf '  %b│%b  %-12s %b\n' "$DARK" "$RESET" "Panel" "$panel_state"
    printf '  %b│%b  %-12s %b\n' "$DARK" "$RESET" "Node" "$node_state"
    printf '  %b│%b  %-12s %b\n' "$DARK" "$RESET" "PHP" "$php_state"
    printf '  %b│%b  %-12s %b\n' "$DARK" "$RESET" "Nginx" "$nginx_state"
    printf '  %b│%b  %-12s %s\n' "$DARK" "$RESET" "Redis" "$redis_state"
    printf '  %b│%b  %-12s %s\n' "$DARK" "$RESET" "Queue" "$queue_state"
    printf '  %b└────────────────────────────────────────────────────────┘%b\n' "$DARK" "$RESET"
}

# ----------------------------- UI --------------------------------
title() {
    local text="$1"
    local w inner
    w="$(term_width)"
    inner=$((w-6))
    (( inner < 20 )) && inner=20

    clear 2>/dev/null || true
    echo
    printf '  %b╭%s╮%b\n' "$PURPLE" "$(printf '─%.0s' $(seq 1 "$inner"))" "$RESET"
    printf '  %b│%b %b%-*s%b %b│%b\n' \
        "$PURPLE" "$RESET" "$BOLD$WHITE" $((inner-2)) "$text" "$RESET" "$PURPLE" "$RESET"
    printf '  %b╰%s╯%b\n' "$PURPLE" "$(printf '─%.0s' $(seq 1 "$inner"))" "$RESET"
    echo
}

banner() {
    clear 2>/dev/null || true
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

# -------------------------- Installation -------------------------
install_ptero() {
    title "FRESH PANEL INSTALLATION"

    if panel_installed; then
        warn "A Pterodactyl panel already exists at $PANEL_DIR."
        read -r -p "  Continue anyway? (y/N): " confirm || true
        [[ "$confirm" =~ ^[Yy]$ ]] || {
            info "Installation cancelled."
            pause
            return
        }
    fi

    echo
    info "The external installer will open its own configuration wizard."
    info "Nothing is executed until you confirm inside that installer."
    echo

    # Prepare Node 22 first. The external installer also verifies it.
    if ! install_yarn; then
        err "Node.js 22 / Yarn preparation failed."
        pause
        return
    fi

    echo
    read -r -p "  Launch Pterodactyl installer now? [y/N]: " confirm || true
    [[ "$confirm" =~ ^[Yy]$ ]] || {
        info "Installation cancelled."
        pause
        return
    }

    echo
    step "Downloading installer..."
    local tmp="/tmp/zyrexptero-installer-$$.sh"

    if ! curl -fsSL --retry 3 --connect-timeout 10 "$INSTALLER_URL" -o "$tmp"; then
        err "Could not download the installer."
        rm -f "$tmp"
        pause
        return
    fi

    if [[ ! -s "$tmp" ]]; then
        err "Installer download is empty."
        rm -f "$tmp"
        pause
        return
    fi

    step "Starting installer..."
    if bash "$tmp"; then
        ok "Installation sequence finished."
    else
        err "Installer returned an error."
        warn "Check the error shown above before retrying."
    fi

    rm -f "$tmp"
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

    cd "$PANEL_DIR" || {
        err "Cannot enter $PANEL_DIR"
        pause
        return
    }

    echo "  ${GREEN}1${RESET}  Create custom user"
    echo "  ${GREEN}2${RESET}  Create random admin user"
    echo
    read -r -p "  Select [1-2]: " choice || true

    case "$choice" in
        1)
            php artisan p:user:make
            ;;
        2)
            local username password email first last
            username="admin$(openssl rand -hex 2)"
            password="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9@#%+=_' | cut -c1-20)"
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
    command_exists curl || return 1

    curl -fsSL --retry 3 \
        "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=20" |
        python3 -c '
import json, sys
try:
    data=json.load(sys.stdin)
except Exception:
    sys.exit(1)
for r in data:
    tag=r.get("tag_name","")
    if tag.startswith("v") and not r.get("prerelease") and not r.get("draft"):
        print(tag)
' 2>/dev/null
}

select_version() {
    local tags=() tag choice idx

    while IFS= read -r tag; do
        [[ -n "$tag" ]] && tags+=("$tag")
    done < <(fetch_versions || true)

    if ((${#tags[@]} == 0)); then
        # IMPORTANT: UI goes to stderr so command substitution receives only "latest".
        warn "Could not fetch release list; latest will be used." >&2
        printf '%s\n' "latest"
        return 0
    fi

    # IMPORTANT:
    # This function is used as version="$(select_version)".
    # Therefore all menu text MUST go to stderr.
    echo "  ${BOLD}${WHITE}Available releases${RESET}" >&2

    local i=1
    for tag in "${tags[@]}"; do
        printf '  %b%2d%b  %s\n' "$CYAN" "$i" "$RESET" "$tag" >&2
        ((i++))
    done

    echo >&2
    read -r -p "  Select release [1 = latest]: " choice || true

    if [[ "$choice" =~ ^[0-9]+$ ]] &&
       (( choice >= 1 && choice <= ${#tags[@]} )); then
        idx=$((choice-1))
        printf '%s\n' "${tags[$idx]}"
    else
        printf '%s\n' "${tags[0]}"
    fi
}

update_panel() {
    title "PANEL UPDATE"

    if ! panel_installed; then
        err "Panel not found at $PANEL_DIR."
        pause
        return
    fi

    local missing=()
    command_exists composer || missing+=("composer")
    command_exists curl || missing+=("curl")
    command_exists tar || missing+=("tar")
    command_exists python3 || missing+=("python3")

    if ((${#missing[@]} > 0)); then
        err "Required command(s) missing: ${missing[*]}"
        pause
        return
    fi

    if ! install_yarn; then
        err "Node.js 22 / Yarn preparation failed."
        pause
        return
    fi

    local version archive backup env_tmp
    version="$(select_version)"

    echo
    info "Selected release: $version"
    read -r -p "  Continue with panel update? (y/N): " confirm || true
    [[ "$confirm" =~ ^[Yy]$ ]] || {
        info "Update cancelled."
        pause
        return
    }

    cd "$PANEL_DIR" || {
        err "Cannot enter $PANEL_DIR"
        pause
        return
    }

    backup="/var/backups/zyrexptero"
    mkdir -p "$backup"

    if [[ -f .env ]]; then
        cp -a .env "$backup/.env.$(date +%Y%m%d-%H%M%S)"
    fi

    env_tmp="$(mktemp)"
    cp .env "$env_tmp"

    step "Enabling maintenance mode..."
    php artisan down || true

    archive="$PANEL_DIR/panel.tar.gz"

    step "Downloading release..."
    if [[ "$version" == "latest" ]]; then
        curl -fL --retry 3 -o "$archive" \
            "https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
    else
        curl -fL --retry 3 -o "$archive" \
            "https://github.com/pterodactyl/panel/releases/download/${version}/panel.tar.gz"
    fi

    if [[ ! -s "$archive" ]]; then
        err "Panel archive download failed."
        cp "$env_tmp" .env
        rm -f "$env_tmp"
        php artisan up || true
        pause
        return
    fi

    step "Replacing panel application files..."
    find . -mindepth 1 -maxdepth 1 \
        ! -name ".env" \
        ! -name "storage" \
        ! -name "panel.tar.gz" \
        -exec rm -rf {} +

    if ! tar -xzf "$archive"; then
        err "Could not extract the selected panel release."
        rm -f "$archive"
        cp "$env_tmp" .env
        rm -f "$env_tmp"
        php artisan up || true
        pause
        return
    fi

    rm -f "$archive"
    cp "$env_tmp" .env
    rm -f "$env_tmp"

    step "Installing Composer dependencies..."
    if ! COMPOSER_ALLOW_SUPERUSER=1 composer install \
        --no-dev --optimize-autoloader --no-interaction; then
        err "Composer installation failed."
        php artisan up || true
        pause
        return
    fi

    step "Installing frontend dependencies..."
    info "Yarn is running in the foreground; the script waits for completion."
    if ! yarn install --frozen-lockfile --non-interactive; then
        err "Yarn install failed."
        php artisan up || true
        pause
        return
    fi

    step "Refreshing application..."
    php artisan view:clear || true
    php artisan config:clear || true
    php artisan migrate --seed --force

    step "Fixing permissions..."
    chown -R www-data:www-data "$PANEL_DIR"
    chmod -R 755 "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" 2>/dev/null || true

    step "Restarting workers..."
    php artisan queue:restart || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart "$PTERO_SERVICE" 2>/dev/null || true
    php artisan up || true

    ok "Panel update completed: $version"
    pause
}

# --------------------------- Uninstaller --------------------------
uninstall_ptero() {
    title "UNINSTALL PANEL"

    if ! panel_installed && [[ ! -d "$PANEL_DIR" ]]; then
        warn "Panel directory does not exist."
        pause
        return
    fi

    local env_file="$PANEL_DIR/.env"
    local db_name="panel"
    local db_user="pterodactyl"
    local db_host="127.0.0.1"

    if [[ -f "$env_file" ]]; then
        db_name="$(grep '^DB_DATABASE=' "$env_file" | head -n1 | cut -d= -f2-)"
        db_user="$(grep '^DB_USERNAME=' "$env_file" | head -n1 | cut -d= -f2-)"
        db_host="$(grep '^DB_HOST=' "$env_file" | head -n1 | cut -d= -f2-)"

        [[ -n "$db_name" ]] || db_name="panel"
        [[ -n "$db_user" ]] || db_user="pterodactyl"
        [[ -n "$db_host" ]] || db_host="127.0.0.1"
    fi

    echo -e "  ${RED}${BOLD}WARNING${RESET}"
    echo "  This removes the Pterodactyl panel files."
    echo "  Detected database: $db_name"
    echo "  Detected database user: $db_user@$db_host"
    echo "  Wings is NOT removed."
    echo
    echo -e "  ${YELLOW}Database deletion is irreversible.${RESET}"
    echo
    read -r -p "  Type REMOVE to continue: " confirm || true

    if [[ "$confirm" != "REMOVE" ]]; then
        info "Uninstallation cancelled."
        pause
        return
    fi

    step "Stopping queue worker..."
    systemctl stop "$PTERO_SERVICE" 2>/dev/null || true
    systemctl disable "$PTERO_SERVICE" 2>/dev/null || true
    rm -f "/etc/systemd/system/$PTERO_SERVICE"
    systemctl daemon-reload 2>/dev/null || true

    step "Removing panel cron entry..."
    if command_exists crontab; then
        local current_cron
        current_cron="$(crontab -l 2>/dev/null || true)"
        if [[ -n "$current_cron" ]]; then
            printf '%s\n' "$current_cron" |
                grep -vF "${PANEL_DIR}/artisan schedule:run" |
                crontab - 2>/dev/null || true
        fi
    fi

    step "Removing panel files..."
    rm -rf "$PANEL_DIR"

    if command_exists mariadb; then
        step "Removing detected database..."
        mariadb -u root -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null || true
        mariadb -u root -e "DROP USER IF EXISTS '$db_user'@'$db_host';" 2>/dev/null || true
        mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    elif command_exists mysql; then
        step "Removing detected database..."
        mysql -u root -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null || true
        mysql -u root -e "DROP USER IF EXISTS '$db_user'@'$db_host';" 2>/dev/null || true
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi

    step "Cleaning Nginx panel configuration..."
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/zyrexptero.conf
    rm -f /etc/nginx/sites-available/zyrexptero.conf

    if command_exists nginx && nginx -t >/dev/null 2>&1; then
        systemctl reload nginx 2>/dev/null || true
    fi

    ok "Pterodactyl panel cleanup completed."
    info "Wings was not removed."
    pause
}

# ------------------------------ Main ------------------------------
main() {
    require_root

    if ! command_exists curl; then
        err "curl is required. Install it first with: apt-get update && apt-get install -y curl"
        exit 1
    fi

    while true; do
        banner
        read -r -p "  root@zyrexptero:~# " choice || choice="0"
        echo

        case "$choice" in
            1) install_ptero ;;
            2) create_user ;;
            3) update_panel ;;
            4) run_remote_helper "DOMAIN & SSL MANAGER" "$DOMAIN_SSL_URL" ;;
            5) run_remote_helper "PHPMYADMIN MANAGER" "$PHPMYADMIN_URL" ;;
            6) uninstall_ptero ;;
            0)
                clear 2>/dev/null || true
                echo -e "\n  ${GREEN}ZyrexPtero closed.${RESET}\n"
                exit 0
                ;;
            *)
                err "Unknown option: $choice"
                sleep 1
                ;;
        esac
    done
}

main "$@"
