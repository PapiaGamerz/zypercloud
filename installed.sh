#!/usr/bin/env bash
# ============================================================
#                    ZYREXPTERO INSTALLER
#          Modern Pterodactyl Panel Automated Installer
# ============================================================
# Supported:
#   - Ubuntu / Debian
#   - PHP 8.3
#   - Node.js 22 via NVM
#   - Yarn 1.x
#   - MariaDB + Redis + Nginx
#   - Let's Encrypt / Self-Signed / HTTP
#   - Optional Blueprint Framework package installation
#
# Run:
#   chmod +x zyrexptero.sh
#   sudo ./zyrexptero.sh
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ----------------------------- CONFIG -----------------------------
APP_NAME="ZyrexPtero"
PANEL_DIR="/var/www/pterodactyl"
GITHUB_REPO="pterodactyl/panel"
PHP_VERSION="8.3"
NODE_MAJOR="22"
NVM_VERSION="v0.40.3"
YARN_VERSION="1.22.22"

# ------------------------------ COLORS -----------------------------
CYAN='\033[38;5;51m'
BLUE='\033[38;5;45m'
PURPLE='\033[38;5;141m'
WHITE='\033[38;5;255m'
GRAY='\033[38;5;242m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
GOLD='\033[38;5;214m'
YELLOW='\033[38;5;228m'
NC='\033[0m'

LINE="${GRAY}────────────────────────────────────────────────────────────────────${NC}"

# ------------------------------- UI --------------------------------
show_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    cat <<'EOF'
 ________  ________  ________  _______   ________ _________  ________  ________
|\_____  \|\   __  \|\   __  \|\  ___ \ |\   ____\\___   ___|\   __  \|\   __  \
 \|___/  /\ \  \|\  \ \  \|\  \ \   __/|\ \  \___|    \ \  \  \ \  \|\  \ \  \|\  \
     /  / /\ \   __  \ \   ____\ \  \_|/_\ \  \      \ \  \ \ \   _  _\ \   ____\
    /  /_/__\ \  \ \  \ \  \___|\ \  \_| \ \  \      \ \  \ \ \  \\  \\ \  \___|
   |\________\ \__\ \__\ \__\    \ \__\  \ \__\      \ \__\ \ \__\\ _\\ \__\
    \|_______|\|__|\|__|\|__|     \|__|   \|__|       \|__|  \|__|\|__|\|__|
EOF
    echo -e "${NC}"
    echo -e "              ${WHITE}${APP_NAME} • MODERN PTERODACTYL DEPLOYER${NC}"
    echo -e "              ${GRAY}Node.js ${NODE_MAJOR} • PHP ${PHP_VERSION} • Redis • MariaDB${NC}"
    echo -e "${LINE}"
}

info() { echo -e "  ${BLUE}●${NC} $*"; }
ok()   { echo -e "  ${GREEN}✔${NC} $*"; }
warn() { echo -e "  ${GOLD}⚠${NC} $*"; }
die()  { echo -e "  ${RED}✖${NC} $*" >&2; exit 1; }

step() {
    echo
    echo -e "  ${PURPLE}◆${NC} ${WHITE}$*${NC}"
    echo -e "  ${GRAY}${LINE}${NC}"
}

pause() {
    echo
    read -r -p "  Press Enter to continue..." _ || true
}

ask() {
    local label="$1" default="$2" var_name="$3" input
    echo -ne "  ${PURPLE}›${NC} ${WHITE}${label}${NC} ${GRAY}[${default}]${NC}\n"
    echo -ne "    ${GRAY}╰─>${NC} "
    read -r input || true
    if [[ -z "$input" ]]; then
        printf -v "$var_name" '%s' "$default"
    else
        printf -v "$var_name" '%s' "$input"
    fi
}

ask_secret() {
    local label="$1" default="$2" var_name="$3" input
    echo -ne "  ${PURPLE}›${NC} ${WHITE}${label}${NC} ${GRAY}[hidden/default]${NC}\n"
    echo -ne "    ${GRAY}╰─>${NC} "
    read -r -s input || true
    echo
    if [[ -z "$input" ]]; then
        printf -v "$var_name" '%s' "$default"
    else
        printf -v "$var_name" '%s' "$input"
    fi
}

random_password() {
    tr -dc 'A-Za-z0-9@#%+=_' </dev/urandom | head -c 20 || true
}

trap 'echo -e "\n  ${RED}✖ Installation stopped at line ${LINENO}.${NC}"' ERR

# --------------------------- ROOT CHECK ----------------------------
[[ $EUID -eq 0 ]] || die "Please run this installer as root."

# -------------------------- OS DETECTION ---------------------------
detect_os() {
    command -v lsb_release >/dev/null 2>&1 || apt-get update -y && apt-get install -y lsb-release
    OS_ID="$(. /etc/os-release && echo "${ID}")"
    OS_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

    case "$OS_ID" in
        ubuntu|debian) ;;
        *) die "Unsupported OS: ${OS_ID}. Use Ubuntu or Debian." ;;
    esac

    ok "Detected ${OS_ID} ${OS_CODENAME}"
}

# -------------------------- INPUT / CONFIG -------------------------
collect_config() {
    step "ZyrexPtero configuration"

    ask "Panel Domain" "panel.example.com" DOMAIN
    ask "Admin Email" "admin@example.com" EMAIL
    ask "Admin Username" "admin" USERNAME

    DEFAULT_ADMIN_PASSWORD="$(random_password)"
    [[ -n "$DEFAULT_ADMIN_PASSWORD" ]] || DEFAULT_ADMIN_PASSWORD="ChangeMe-$(date +%s)"
    ask_secret "Admin Password" "$DEFAULT_ADMIN_PASSWORD" PASSWORD

    ask "Database Name" "panel" DB_NAME
    ask "Database User" "pterodactyl" DB_USER
    DEFAULT_DB_PASSWORD="$(random_password)"
    [[ -n "$DEFAULT_DB_PASSWORD" ]] || DEFAULT_DB_PASSWORD="DB-$(date +%s)"
    ask_secret "Database Password" "$DEFAULT_DB_PASSWORD" DB_PASS

    echo
    echo -e "  ${WHITE}SSL Mode${NC}"
    echo -e "  ${GRAY}1) Let's Encrypt (recommended for public domains)${NC}"
    echo -e "  ${GRAY}2) Self-Signed certificate${NC}"
    echo -e "  ${GRAY}3) HTTP only${NC}"
    echo
    ask "Select SSL mode" "1" SSL_MODE

    case "$SSL_MODE" in
        1) SSL_TYPE="letsencrypt"; SSL_NAME="Let's Encrypt" ;;
        2) SSL_TYPE="selfsigned"; SSL_NAME="Self-Signed" ;;
        3) SSL_TYPE="none"; SSL_NAME="HTTP Only" ;;
        *) warn "Invalid SSL mode; using Let's Encrypt."; SSL_TYPE="letsencrypt"; SSL_NAME="Let's Encrypt" ;;
    esac

    ask "Install Blueprint package if .blueprint files are present? (y/n)" "y" INSTALL_BLUEPRINT
}

review_config() {
    echo
    echo -e "  ${GOLD}╭─ ZYREXPTERO DEPLOYMENT REVIEW ─────────────────────────────╮${NC}"
    printf "  ${GOLD}│${NC} %-18s ${WHITE}%s${NC}\n" "App:" "$APP_NAME"
    printf "  ${GOLD}│${NC} %-18s ${WHITE}%s${NC}\n" "Domain:" "$DOMAIN"
    printf "  ${GOLD}│${NC} %-18s ${WHITE}%s${NC}\n" "Admin:" "$USERNAME"
    printf "  ${GOLD}│${NC} %-18s ${WHITE}%s${NC}\n" "Database:" "$DB_NAME"
    printf "  ${GOLD}│${NC} %-18s ${WHITE}%s${NC}\n" "SSL:" "$SSL_NAME"
    printf "  ${GOLD}│${NC} %-18s ${WHITE}Node.js ${NODE_MAJOR}${NC}\n" "Runtime:"
    echo -e "  ${GOLD}╰────────────────────────────────────────────────────────────╯${NC}"
    echo
    read -r -p "  Start installation? [Y/n]: " confirm || true
    [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]] || exit 0
}

# ------------------------ APT DEPENDENCIES -------------------------
install_base_packages() {
    step "Installing system dependencies"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y \
        curl ca-certificates gnupg unzip git tar sudo \
        lsb-release cron openssl software-properties-common \
        build-essential

    ok "Base packages installed"
}

setup_php_repo() {
    step "Preparing PHP ${PHP_VERSION}"

    if [[ "$OS_ID" == "ubuntu" ]]; then
        add-apt-repository -y ppa:ondrej/php
    else
        curl -fsSL https://packages.sury.org/php/apt.gpg \
            | gpg --dearmor --yes -o /usr/share/keyrings/sury-php.gpg
        echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ ${OS_CODENAME} main" \
            > /etc/apt/sources.list.d/sury-php.list
    fi

    apt-get update -y
}

install_services() {
    step "Installing PHP, MariaDB, Nginx and Redis"

    apt-get install -y \
        "php${PHP_VERSION}" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-tokenizer" \
        "php${PHP_VERSION}-ctype" \
        mariadb-server nginx redis-server certbot python3-certbot-nginx

    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now "php${PHP_VERSION}-fpm"

    ok "Core services are running"
}

# --------------------------- COMPOSER ------------------------------
install_composer() {
    step "Installing Composer"

    if command -v composer >/dev/null 2>&1; then
        ok "Composer already installed: $(composer --version | head -n1)"
        return
    fi

    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer-setup.php

    ok "Composer installed"
}

# -------------------------- NODE.JS 22 -----------------------------
load_nvm() {
    export NVM_DIR="${NVM_DIR:-/root/.nvm}"

    if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
        # shellcheck disable=SC1090
        source "${NVM_DIR}/nvm.sh"
        return 0
    fi

    return 1
}

install_nvm() {
    step "Preparing Node.js ${NODE_MAJOR} with NVM"

    export NVM_DIR="/root/.nvm"

    if ! load_nvm; then
        info "NVM not found. Installing NVM ${NVM_VERSION}..."
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

        export NVM_DIR="/root/.nvm"
        [[ -s "${NVM_DIR}/nvm.sh" ]] || die "NVM installation failed."
        # shellcheck disable=SC1090
        source "${NVM_DIR}/nvm.sh"
    fi

    info "Checking active Node.js version..."

    local current_major=""
    if command -v node >/dev/null 2>&1; then
        current_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
    fi

    if [[ "$current_major" != "$NODE_MAJOR" ]]; then
        info "Node.js ${NODE_MAJOR} is not active. Installing it through NVM..."
        nvm install "$NODE_MAJOR"
    else
        ok "Node.js ${NODE_MAJOR} is already active"
    fi

    nvm install "$NODE_MAJOR" >/dev/null
    nvm use "$NODE_MAJOR"
    nvm alias default "$NODE_MAJOR"

    hash -r

    NODE_VERSION="$(node -v)"
    NPM_VERSION="$(npm -v)"

    [[ "$NODE_VERSION" == v22.* ]] || die "Node.js 22 activation failed. Current: ${NODE_VERSION}"

    ok "Node.js active: ${NODE_VERSION}"
    ok "npm: ${NPM_VERSION}"

    # Make Node 22 available to root login shells.
    cat > /etc/profile.d/zyrexptero-node.sh <<'EOF'
export NVM_DIR="/root/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm use 22 >/dev/null 2>&1 || true
fi
EOF

    # Install Yarn 1.x only after Node 22 is active.
    npm install --global "yarn@${YARN_VERSION}"

    YARN_ACTIVE="$(yarn --version)"
    [[ "$YARN_ACTIVE" == 1.* ]] || die "Yarn 1.x installation failed."

    ok "Yarn active: ${YARN_ACTIVE}"
}

# -------------------------- PTERODACTYL ----------------------------
download_panel() {
    step "Downloading Pterodactyl Panel"

    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR"

    if [[ "${version_PANEL:-latest}" == "latest" ]]; then
        curl -fLso panel.tar.gz \
            https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    else
        curl -fLso panel.tar.gz \
            "https://github.com/pterodactyl/panel/releases/download/${version_PANEL}/panel.tar.gz"
    fi

    tar -xzf panel.tar.gz
    rm -f panel.tar.gz

    chmod -R 755 storage bootstrap/cache
    ok "Panel files ready in ${PANEL_DIR}"
}

setup_database() {
    step "Configuring MariaDB"

    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

    ok "Database configured"
}

setup_env() {
    step "Creating Pterodactyl environment"

    cd "$PANEL_DIR"

    [[ -f .env.example ]] || curl -fLo .env.example \
        https://raw.githubusercontent.com/pterodactyl/panel/develop/.env.example

    cp -f .env.example .env

    if [[ "$SSL_TYPE" == "none" ]]; then
        APP_URL="http://${DOMAIN}"
    else
        APP_URL="https://${DOMAIN}"
    fi

    sed -i "s|^APP_URL=.*|APP_URL=${APP_URL}|" .env
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|" .env

    if ! grep -q '^APP_ENVIRONMENT_ONLY=' .env; then
        echo "APP_ENVIRONMENT_ONLY=false" >> .env
    fi

    sed -i '/^APP_NAME=/d' .env
    echo 'APP_NAME="ZyrexPtero"' >> .env

    TIMEZONE="$(timedatectl show --property=Timezone --value 2>/dev/null || echo UTC)"
    if grep -q '^APP_TIMEZONE=' .env; then
        sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=${TIMEZONE}|" .env
    else
        echo "APP_TIMEZONE=${TIMEZONE}" >> .env
    fi

    ok "Environment configured"
}

install_php_dependencies() {
    step "Installing PHP dependencies"

    cd "$PANEL_DIR"
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

    ok "Composer dependencies installed"
}

install_frontend_dependencies() {
    step "Installing frontend dependencies with Node.js 22"

    cd "$PANEL_DIR"

    # Re-load NVM in case the previous shell environment changed.
    export NVM_DIR="/root/.nvm"
    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"
    nvm use "$NODE_MAJOR" >/dev/null

    info "Node: $(node -v)"
    info "Yarn: $(yarn --version)"
    info "Running yarn install. Waiting until it fully finishes..."

    # Important: do not background this command.
    # Blueprint/Pterodactyl steps only continue after Yarn exits successfully.
    yarn install --frozen-lockfile --non-interactive

    ok "Yarn install completed successfully"
}

generate_key_and_migrate() {
    step "Generating application key and migrating database"

    cd "$PANEL_DIR"

    php artisan key:generate --force
    php artisan migrate --seed --force

    ok "Application key and migrations completed"
}

# ----------------------------- NGINX -------------------------------
write_nginx_http() {
    cat > /etc/nginx/sites-available/zyrexptero.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
}

configure_nginx() {
    step "Configuring Nginx"

    write_nginx_http

    ln -sf /etc/nginx/sites-available/zyrexptero.conf \
        /etc/nginx/sites-enabled/zyrexptero.conf

    rm -f /etc/nginx/sites-enabled/default

    nginx -t
    systemctl restart nginx

    ok "Nginx HTTP configuration active"
}

# ------------------------------ SSL --------------------------------
configure_ssl() {
    case "$SSL_TYPE" in
        none)
            warn "SSL disabled. Panel will use HTTP."
            return
            ;;
        selfsigned)
            step "Creating self-signed SSL certificate"

            mkdir -p /etc/certs/zyrexptero

            openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
                -subj "/C=NA/ST=NA/L=NA/O=ZyrexPtero/CN=${DOMAIN}" \
                -keyout /etc/certs/zyrexptero/privkey.pem \
                -out /etc/certs/zyrexptero/fullchain.pem

            ;;
        letsencrypt)
            step "Requesting Let's Encrypt certificate"

            # First make sure HTTP works for the ACME challenge.
            certbot certonly \
                --nginx \
                --non-interactive \
                --agree-tos \
                --email "$EMAIL" \
                -d "$DOMAIN"

            mkdir -p /etc/certs/zyrexptero
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" \
                /etc/certs/zyrexptero/fullchain.pem
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" \
                /etc/certs/zyrexptero/privkey.pem
            ;;
    esac

    if [[ "$SSL_TYPE" != "none" ]]; then
        step "Enabling HTTPS"

        cat > /etc/nginx/sites-available/zyrexptero.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;

    ssl_certificate /etc/certs/zyrexptero/fullchain.pem;
    ssl_certificate_key /etc/certs/zyrexptero/privkey.pem;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

        nginx -t
        systemctl restart nginx
        ok "HTTPS enabled"
    fi
}

# --------------------------- QUEUE WORKER --------------------------
setup_queue_worker() {
    step "Setting up queue worker"

    cat > /etc/systemd/system/pteroq.service <<'EOF'
[Unit]
Description=ZyrexPtero Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5s
WorkingDirectory=/var/www/pterodactyl
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now redis-server
    systemctl enable --now pteroq.service

    ok "Queue worker is online"
}

setup_cron() {
    step "Configuring scheduler"

    systemctl enable --now cron

    CRON_LINE="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -Fv "${PANEL_DIR}/artisan schedule:run" || true; echo "$CRON_LINE") | crontab -

    ok "Pterodactyl scheduler enabled"
}

# --------------------------- PANEL TUNING --------------------------
configure_panel() {
    step "Applying ZyrexPtero panel settings"

    cd "$PANEL_DIR"

    sed -i '/^APP_ENVIRONMENT_ONLY=/d' .env
    echo "APP_ENVIRONMENT_ONLY=false" >> .env

    sed -i '/^RECAPTCHA_ENABLED=/d' .env
    echo "RECAPTCHA_ENABLED=false" >> .env

    sed -i '/^APP_NAME=/d' .env
    echo 'APP_NAME="ZyrexPtero"' >> .env

    php artisan view:clear
    php artisan config:clear
    php artisan cache:clear
    php artisan config:cache

    chown -R www-data:www-data "$PANEL_DIR"
    php artisan queue:restart || true

    ok "Panel optimized"
}

create_admin() {
    step "Creating administrator account"

    cd "$PANEL_DIR"

    php artisan p:user:make \
        --email="$EMAIL" \
        --username="$USERNAME" \
        --password="$PASSWORD" \
        --name-first="Zyrex" \
        --name-last="Admin" \
        --admin=1 \
        --no-interaction

    ok "Administrator account created"
}

# -------------------------- BLUEPRINT ------------------------------
install_blueprint_optional() {
    [[ "${INSTALL_BLUEPRINT,,}" == "y" ]] || {
        info "Blueprint installation skipped."
        return
    }

    step "Checking for Blueprint packages"

    cd "$PANEL_DIR"

    shopt -s nullglob
    local packages=( ./*.blueprint )
    shopt -u nullglob

    if (( ${#packages[@]} == 0 )); then
        warn "No .blueprint package found in ${PANEL_DIR}; skipping Blueprint install."
        return
    fi

    if ! command -v blueprint >/dev/null 2>&1; then
        warn "Blueprint CLI was not found."
        warn "The installer will not guess a Blueprint download URL or replace the framework with an incompatible build."
        warn "Place a compatible Blueprint CLI/package in the panel environment, then rerun the Blueprint step."
        return
    fi

    export NVM_DIR="/root/.nvm"
    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"
    nvm use "$NODE_MAJOR" >/dev/null

    info "Node.js for Blueprint: $(node -v)"
    info "Installing Blueprint packages only after Node.js 22 + Yarn finished."

    local package
    for package in "${packages[@]}"; do
        info "Installing $(basename "$package")..."
        blueprint -install "$package"
    done

    ok "Blueprint package installation finished"
}

# ----------------------------- FINAL -------------------------------
final_checks() {
    step "Running final health checks"

    cd "$PANEL_DIR"

    php artisan --version || true
    echo
    info "Node.js: $(node -v 2>/dev/null || echo unavailable)"
    info "Yarn: $(yarn --version 2>/dev/null || echo unavailable)"
    info "PHP: $(php -v | head -n1)"
    info "Nginx: $(nginx -v 2>&1)"
    info "Redis: $(systemctl is-active redis-server || true)"
    info "Queue: $(systemctl is-active pteroq.service || true)"
    info "Nginx config: $(nginx -t 2>&1 | tail -n1 || true)"

    ok "Health checks completed"
}

show_success() {
    clear 2>/dev/null || true

    local scheme="https"
    [[ "$SSL_TYPE" == "none" ]] && scheme="http"

    echo -e "${CYAN}"
    echo -e "  ${LINE}"
    echo -e "      ${WHITE}ZYREXPTERO DEPLOYMENT COMPLETED${NC}"
    echo -e "  ${LINE}"
    echo -e "${NC}"

    echo -e "  ${GREEN}✔${NC} Panel URL : ${WHITE}${scheme}://${DOMAIN}${NC}"
    echo -e "  ${GREEN}✔${NC} Username  : ${WHITE}${USERNAME}${NC}"
    echo -e "  ${GREEN}✔${NC} Password  : ${WHITE}${PASSWORD}${NC}"
    echo -e "  ${GREEN}✔${NC} Email     : ${WHITE}${EMAIL}${NC}"
    echo -e "  ${GREEN}✔${NC} App Name  : ${WHITE}${APP_NAME}${NC}"
    echo -e "  ${GREEN}✔${NC} Node.js   : ${WHITE}$(node -v 2>/dev/null || echo '22 configured')${NC}"
    echo
    echo -e "  ${GOLD}Important:${NC} Save the administrator password somewhere secure."
    echo -e "  ${GRAY}Panel directory: ${PANEL_DIR}${NC}"
    echo
    echo -e "  ${PURPLE}ZyrexPtero is ready.${NC}"
    echo -e "  ${LINE}"
}

# ------------------------------ MAIN -------------------------------
main() {
    show_banner
    detect_os
    collect_config
    review_config

    install_base_packages
    setup_php_repo
    install_services
    install_composer

    # Node 22 MUST be ready before frontend/Blueprint operations.
    install_nvm

    download_panel
    setup_database
    setup_env
    install_php_dependencies

    # This blocks until yarn install has completely finished.
    install_frontend_dependencies

    generate_key_and_migrate
    configure_nginx
    configure_ssl
    setup_queue_worker
    setup_cron
    configure_panel
    create_admin

    # Optional Blueprint packages run after Node 22 + Yarn are ready.
    install_blueprint_optional

    final_checks
    show_success
}

main "$@"
