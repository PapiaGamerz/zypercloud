#!/usr/bin/env bash
# ============================================================
# ZYREXPTERO PTERODACTYL INSTALLER v4.0
# Interactive Ubuntu/Debian VPS installer
#
# Features:
#   - Does NOT install anything before the configuration wizard
#   - Panel domain / URL
#   - Panel version selection
#   - Admin username / password / email
#   - Database name / username / password
#   - HTTP / Let's Encrypt / Self-Signed SSL
#   - Node.js 22 via NVM
#   - Yarn 1.22.22
#   - Waits for yarn install to finish before continuing
#   - Optional Blueprint package installation
#   - Nginx + PHP 8.3 + MariaDB + Redis
#
# IMPORTANT:
# This is for a real Ubuntu/Debian VPS/VM with root + systemd.
# A normal Railway application container is NOT a VPS and does
# not provide the systemd/privileged environment Pterodactyl
# normally needs. The installer detects that case and stops.
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="ZyrexPtero"
PANEL_DIR="/var/www/pterodactyl"
PHP_VERSION="8.3"
NODE_MAJOR="22"
NVM_VERSION="v0.40.3"
YARN_VERSION="1.22.22"
NGINX_SITE="/etc/nginx/sites-available/pterodactyl.conf"
NGINX_LINK="/etc/nginx/sites-enabled/pterodactyl.conf"

# -------------------- Colors --------------------
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

cleanup() {
    :
}
trap cleanup EXIT

banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              ZYREXPTERO PTERODACTYL v4.0                  ║"
    echo "║             Interactive VPS Installation Wizard             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

info()  { echo -e "  ${BLUE}●${NC} $*"; }
ok()    { echo -e "  ${GREEN}✔${NC} $*"; }
warn()  { echo -e "  ${GOLD}⚠${NC} $*"; }
fail()  { echo -e "  ${RED}✖${NC} $*" >&2; }
step()  { echo -e "\n  ${PURPLE}◆${NC} ${WHITE}$*${NC}\n  ${GRAY}────────────────────────────────────────────────────────────${NC}"; }
die()   { fail "$*"; exit 1; }

pause() {
    echo
    read -r -p "  Press Enter to continue..." _ || true
}

ask() {
    local label="$1" default="$2" var="$3" input
    echo -e "  ${PURPLE}›${NC} ${WHITE}${label}${NC} ${GRAY}[${default}]${NC}"
    read -r -p "    > " input || true
    [[ -n "$input" ]] || input="$default"
    printf -v "$var" '%s' "$input"
}

ask_required() {
    local label="$1" var="$2" input
    while true; do
        echo -e "  ${PURPLE}›${NC} ${WHITE}${label}${NC}"
        read -r -p "    > " input || true
        [[ -n "$input" ]] && break
        warn "This field cannot be empty."
    done
    printf -v "$var" '%s' "$input"
}

ask_secret() {
    local label="$1" var="$2" input
    while true; do
        echo -e "  ${PURPLE}›${NC} ${WHITE}${label}${NC} ${GRAY}(hidden)${NC}"
        read -r -s -p "    > " input || true
        echo
        if [[ -n "$input" ]]; then
            printf -v "$var" '%s' "$input"
            return
        fi
        warn "This field cannot be empty."
    done
}

confirm() {
    local prompt="$1" answer
    read -r -p "  ${prompt} [y/N]: " answer || true
    [[ "$answer" =~ ^[Yy]$ ]]
}

random_password() {
    tr -dc 'A-Za-z0-9@#%+=_' </dev/urandom | head -c 24 || true
}

require_root() {
    [[ "$EUID" -eq 0 ]] || die "Run as root: sudo bash $0"
}

detect_platform() {
    [[ -f /etc/os-release ]] || die "Cannot detect operating system."
    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-unknown}"
    OS_CODENAME="${VERSION_CODENAME:-}"

    case "$OS_ID" in
        ubuntu|debian)
            ok "Supported OS detected: ${PRETTY_NAME:-$OS_ID}"
            ;;
        *)
            die "This installer supports Ubuntu/Debian only. Detected: $OS_ID"
            ;;
    esac

    # Railway application containers commonly expose Railway variables.
    if [[ -n "${RAILWAY_ENVIRONMENT:-}" || -n "${RAILWAY_PROJECT_ID:-}" || -n "${RAILWAY_SERVICE_ID:-}" ]]; then
        warn "Railway environment detected."
        warn "A normal Railway service is a container/PaaS runtime, not a full VPS."
        warn "Pterodactyl's systemd/Nginx/MariaDB/Redis stack cannot safely be installed"
        warn "as a normal Railway application service."
        echo
        echo "If you mean a separate Ubuntu/Debian VPS hosted elsewhere, run this there."
        echo "If you mean a Railway container, use a container-native architecture instead."
        exit 1
    fi

    command -v systemctl >/dev/null 2>&1 || \
        die "systemctl was not found. This does not look like a normal VPS/VM."
}

validate_domain() {
    local d="$1"
    [[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
    [[ "$d" != *".."* ]] || return 1
    return 0
}

normalize_domain() {
    DOMAIN="${DOMAIN,,}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN%%/*}"
}

validate_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]
}

validate_username() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

validate_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

validate_password() {
    local p="$1"
    [[ ${#p} -ge 8 ]]
}

# -------------------- Configuration wizard --------------------

collect_config() {
    banner
    step "1/3 • PANEL CONFIGURATION"

    while true; do
        ask_required "Panel Domain / URL (example: panel.example.com)" DOMAIN
        normalize_domain
        validate_domain "$DOMAIN" && break
        warn "Invalid domain."
    done

    echo
    echo -e "  ${WHITE}Panel version${NC}"
    echo -e "  ${GRAY}1) Latest stable release${NC}"
    echo -e "  ${GRAY}2) Enter a release tag manually (example: v1.12.2)${NC}"
    echo

    local version_choice
    while true; do
        read -r -p "  Select [1-2]: " version_choice || true
        case "$version_choice" in
            1)
                PANEL_VERSION="latest"
                break
                ;;
            2)
                ask_required "Pterodactyl release tag" PANEL_VERSION
                [[ "$PANEL_VERSION" == v* ]] || PANEL_VERSION="v${PANEL_VERSION}"
                break
                ;;
            *)
                warn "Choose 1 or 2."
                ;;
        esac
    done

    step "2/3 • ADMIN + DATABASE"

    while true; do
        ask_required "Admin Email" ADMIN_EMAIL
        validate_email "$ADMIN_EMAIL" && break
        warn "Invalid email address."
    done

    while true; do
        ask "Admin Username" "admin" ADMIN_USERNAME
        validate_username "$ADMIN_USERNAME" && break
        warn "Use only letters, numbers, dot, dash or underscore."
    done

    while true; do
        ask_secret "Admin Password (minimum 8 characters)" ADMIN_PASSWORD
        validate_password "$ADMIN_PASSWORD" && break
        warn "Password must contain at least 8 characters."
    done

    while true; do
        ask "Database Name" "panel" DB_NAME
        validate_identifier "$DB_NAME" && break
        warn "Database name may contain only letters, numbers and underscore."
    done

    while true; do
        ask "Database Username" "pterodactyl" DB_USER
        validate_identifier "$DB_USER" && break
        warn "Database username may contain only letters, numbers and underscore."
    done

    ask_secret "Database Password" DB_PASSWORD

    step "3/3 • SSL CONFIGURATION"

    echo -e "  ${WHITE}Select SSL mode:${NC}"
    echo -e "  ${GREEN}[1]${NC} Let's Encrypt SSL ${GRAY}(public domain required)${NC}"
    echo -e "  ${YELLOW}[2]${NC} Self-Signed SSL ${GRAY}(testing/internal use)${NC}"
    echo -e "  ${BLUE}[3]${NC} HTTP only ${GRAY}(no SSL)${NC}"
    echo

    while true; do
        read -r -p "  Select SSL [1-3]: " SSL_CHOICE || true
        case "$SSL_CHOICE" in
            1)
                SSL_TYPE="letsencrypt"
                SSL_NAME="Let's Encrypt"
                break
                ;;
            2)
                SSL_TYPE="selfsigned"
                SSL_NAME="Self-Signed"
                break
                ;;
            3)
                SSL_TYPE="none"
                SSL_NAME="HTTP Only"
                break
                ;;
            *)
                warn "Choose 1, 2 or 3."
                ;;
        esac
    done

    if [[ "$SSL_TYPE" == "letsencrypt" ]]; then
        while true; do
            ask_required "Let's Encrypt email" SSL_EMAIL
            validate_email "$SSL_EMAIL" && break
            warn "Invalid email address."
        done
    else
        SSL_EMAIL=""
    fi

    echo
    echo -e "  ${WHITE}Blueprint${NC}"
    echo -e "  ${GRAY}Blueprint packages are installed only after Node 22 + Yarn finish.${NC}"
    if confirm "Install local *.blueprint packages if found?"; then
        INSTALL_BLUEPRINT="yes"
    else
        INSTALL_BLUEPRINT="no"
    fi
}

review_config() {
    banner
    step "DEPLOYMENT REVIEW"

    echo -e "  ${WHITE}Panel URL:${NC}       ${DOMAIN}"
    echo -e "  ${WHITE}Panel version:${NC}   ${PANEL_VERSION}"
    echo -e "  ${WHITE}Admin username:${NC}  ${ADMIN_USERNAME}"
    echo -e "  ${WHITE}Admin email:${NC}     ${ADMIN_EMAIL}"
    echo -e "  ${WHITE}Database:${NC}         ${DB_NAME}"
    echo -e "  ${WHITE}DB username:${NC}     ${DB_USER}"
    echo -e "  ${WHITE}SSL:${NC}              ${SSL_NAME}"
    echo -e "  ${WHITE}Node.js:${NC}          ${NODE_MAJOR}"
    echo -e "  ${WHITE}PHP:${NC}              ${PHP_VERSION}"
    echo -e "  ${WHITE}Blueprint:${NC}        ${INSTALL_BLUEPRINT}"
    echo

    warn "Nothing has been installed yet."
    if ! confirm "Start the installation now?"; then
        echo
        info "Installation cancelled before any changes were made."
        exit 0
    fi
}

# -------------------- System packages --------------------

install_base() {
    step "Installing base packages"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y \
        curl ca-certificates gnupg lsb-release \
        software-properties-common apt-transport-https \
        git unzip tar openssl sudo cron build-essential

    ok "Base packages installed."
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
    step "Installing PHP, Nginx, MariaDB and Redis"

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
        mariadb-server nginx redis-server

    systemctl enable --now mariadb
    systemctl enable --now redis-server
    systemctl enable --now "php${PHP_VERSION}-fpm"
    systemctl enable --now nginx

    ok "Core services installed and started."
}

install_composer() {
    step "Installing Composer 2"

    if command -v composer >/dev/null 2>&1; then
        composer self-update --2 >/dev/null 2>&1 || true
        ok "Composer already available."
        return
    fi

    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer-setup.php

    composer --version >/dev/null
    ok "Composer installed."
}

# -------------------- Node 22 / Yarn --------------------

load_nvm() {
    export NVM_DIR="/root/.nvm"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1090
        source "$NVM_DIR/nvm.sh"
        return 0
    fi
    return 1
}

install_node22() {
    step "Preparing Node.js ${NODE_MAJOR} + Yarn ${YARN_VERSION}"

    export NVM_DIR="/root/.nvm"

    if ! load_nvm; then
        info "NVM not found. Installing ${NVM_VERSION}..."
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
        load_nvm || die "NVM installation failed."
    fi

    local current_major=""
    if command -v node >/dev/null 2>&1; then
        current_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)"
    fi

    if [[ "$current_major" != "$NODE_MAJOR" ]]; then
        info "Node.js ${NODE_MAJOR} is not active. Installing..."
        nvm install "$NODE_MAJOR"
    fi

    nvm install "$NODE_MAJOR" >/dev/null
    nvm use "$NODE_MAJOR"
    nvm alias default "$NODE_MAJOR"
    hash -r

    [[ "$(node -v)" == v22.* ]] || die "Node.js 22 activation failed."

    npm install --global "yarn@${YARN_VERSION}"

    cat > /etc/profile.d/zyrexptero-node.sh <<'EOF'
export NVM_DIR="/root/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm use 22 >/dev/null 2>&1 || true
fi
EOF

    ok "Node.js: $(node -v)"
    ok "Yarn: $(yarn --version)"
}

# -------------------- Panel download --------------------

download_panel() {
    step "Downloading Pterodactyl ${PANEL_VERSION}"

    mkdir -p "$PANEL_DIR"
    cd "$PANEL_DIR"

    if [[ "$PANEL_VERSION" == "latest" ]]; then
        curl -fLso panel.tar.gz \
            https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    else
        curl -fLso panel.tar.gz \
            "https://github.com/pterodactyl/panel/releases/download/${PANEL_VERSION}/panel.tar.gz"
    fi

    tar -xzf panel.tar.gz
    rm -f panel.tar.gz

    mkdir -p storage bootstrap/cache
    chmod -R 755 storage bootstrap/cache

    ok "Panel files installed in ${PANEL_DIR}."
}

# -------------------- Database --------------------

sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

setup_database() {
    step "Creating MariaDB database"

    local db_pass_sql
    db_pass_sql="$(sql_escape "$DB_PASSWORD")"

    mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${db_pass_sql}';
ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${db_pass_sql}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

    ok "Database ${DB_NAME} and user ${DB_USER} configured."
}

# -------------------- .env --------------------

setup_env() {
    step "Configuring Pterodactyl environment"

    cd "$PANEL_DIR"

    [[ -f .env.example ]] || \
        curl -fLo .env.example \
        "https://raw.githubusercontent.com/pterodactyl/panel/develop/.env.example"

    cp -f .env.example .env

    local app_url
    if [[ "$SSL_TYPE" == "none" ]]; then
        app_url="http://${DOMAIN}"
    else
        app_url="https://${DOMAIN}"
    fi

    sed -i "s|^APP_URL=.*|APP_URL=${app_url}|" .env
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|" .env
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|" .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" .env

    if grep -q '^APP_TIMEZONE=' .env; then
        sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=UTC|" .env
    else
        echo "APP_TIMEZONE=UTC" >> .env
    fi

    sed -i '/^APP_ENVIRONMENT_ONLY=/d' .env
    echo "APP_ENVIRONMENT_ONLY=false" >> .env

    sed -i '/^APP_NAME=/d' .env
    echo 'APP_NAME="ZyrexPtero"' >> .env

    ok ".env configured."
}

# -------------------- PHP / Yarn --------------------

install_php_dependencies() {
    step "Installing PHP dependencies"

    cd "$PANEL_DIR"
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

    ok "Composer dependencies installed."
}

install_frontend_dependencies() {
    step "Installing frontend dependencies"

    cd "$PANEL_DIR"

    export NVM_DIR="/root/.nvm"
    # shellcheck disable=SC1090
    source "$NVM_DIR/nvm.sh"
    nvm use "$NODE_MAJOR" >/dev/null

    info "Node.js: $(node -v)"
    info "Yarn: $(yarn --version)"
    info "Running yarn install in the foreground..."
    info "The installer WILL NOT continue until Yarn exits."

    # Intentionally NOT backgrounded.
    yarn install --frozen-lockfile --non-interactive

    ok "Yarn install finished successfully."
}

generate_key_and_migrate() {
    step "Generating application key + database migrations"

    cd "$PANEL_DIR"

    php artisan key:generate --force
    php artisan migrate --seed --force

    ok "Database migration completed."
}

# -------------------- Nginx --------------------

detect_php_socket() {
    PHP_SOCKET="/run/php/php${PHP_VERSION}-fpm.sock"

    if [[ -S "$PHP_SOCKET" ]]; then
        return 0
    fi

    local detected
    detected="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' 2>/dev/null | sort -V | tail -n1 || true)"

    if [[ -n "$detected" ]]; then
        PHP_SOCKET="$detected"
        warn "Using detected PHP-FPM socket: ${PHP_SOCKET}"
        return 0
    fi

    return 1
}

write_nginx_http() {
    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;

    access_log /var/log/nginx/pterodactyl-access.log;
    error_log  /var/log/nginx/pterodactyl-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass ${PHP_SOCKET};
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;

        fastcgi_param PHP_VALUE "upload_max_filesize=100M
post_max_size=100M";

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";

        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
}

write_nginx_https() {
    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;
    charset utf-8;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass ${PHP_SOCKET};
        fastcgi_index index.php;
        include /etc/nginx/fastcgi_params;

        fastcgi_param PHP_VALUE "upload_max_filesize=100M
post_max_size=100M";

        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";

        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
}

write_nginx_selfsigned() {
    mkdir -p /etc/certs/zyrexptero

    if [[ ! -f /etc/certs/zyrexptero/fullchain.pem || ! -f /etc/certs/zyrexptero/privkey.pem ]]; then
        openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
            -subj "/C=BD/ST=Dhaka/L=Dhaka/O=ZyrexPtero/CN=${DOMAIN}" \
            -keyout /etc/certs/zyrexptero/privkey.pem \
            -out /etc/certs/zyrexptero/fullchain.pem
    fi

    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    root ${PANEL_DIR}/public;
    index index.php;

    ssl_certificate /etc/certs/zyrexptero/fullchain.pem;
    ssl_certificate_key /etc/certs/zyrexptero/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass ${PHP_SOCKET};
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

enable_nginx() {
    ln -sfn "$NGINX_SITE" "$NGINX_LINK"
    rm -f /etc/nginx/sites-enabled/default

    nginx -t
    systemctl reload nginx

    ok "Nginx configuration is active."
}

configure_http_first() {
    step "Configuring HTTP"

    detect_php_socket || die "PHP-FPM socket not found."

    write_nginx_http
    enable_nginx
}

configure_ssl() {
    case "$SSL_TYPE" in
        none)
            warn "SSL disabled. Panel remains HTTP."
            ;;
        selfsigned)
            step "Generating Self-Signed SSL"
            write_nginx_selfsigned
            enable_nginx
            ;;
        letsencrypt)
            step "Requesting Let's Encrypt SSL"

            apt-get install -y certbot python3-certbot-nginx

            info "Testing HTTP before ACME validation..."
            nginx -t
            systemctl reload nginx

            certbot certonly \
                --nginx \
                --non-interactive \
                --agree-tos \
                --email "$SSL_EMAIL" \
                -d "$DOMAIN"

            [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]] || \
                die "Let's Encrypt certificate was not created."

            write_nginx_https
            enable_nginx

            # Renewal hook.
            mkdir -p /etc/letsencrypt/renewal-hooks/deploy
            cat > /etc/letsencrypt/renewal-hooks/deploy/pterodactyl-nginx.sh <<'EOF'
#!/usr/bin/env bash
systemctl reload nginx
EOF
            chmod +x /etc/letsencrypt/renewal-hooks/deploy/pterodactyl-nginx.sh

            ok "Let's Encrypt SSL enabled."
            ;;
    esac
}

# -------------------- Queue + cron --------------------

setup_queue() {
    step "Setting up Pterodactyl queue worker"

    cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service
StartLimitInterval=180
StartLimitBurst=30

[Service]
User=www-data
Group=www-data
Restart=always
RestartSec=5s
WorkingDirectory=${PANEL_DIR}
ExecStart=/usr/bin/php ${PANEL_DIR}/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pteroq.service

    ok "Queue worker enabled."
}

setup_cron() {
    step "Configuring Pterodactyl scheduler"

    systemctl enable --now cron

    local cron_line
    cron_line="* * * * * php ${PANEL_DIR}/artisan schedule:run >> /dev/null 2>&1"

    (
        crontab -l 2>/dev/null | grep -Fv "${PANEL_DIR}/artisan schedule:run" || true
        echo "$cron_line"
    ) | crontab -

    ok "Scheduler enabled."
}

finalize_panel() {
    step "Applying permissions and clearing caches"

    cd "$PANEL_DIR"

    chown -R www-data:www-data "$PANEL_DIR"

    php artisan view:clear
    php artisan config:clear
    php artisan cache:clear
    php artisan config:cache
    php artisan queue:restart || true

    ok "Panel finalized."
}

create_admin() {
    step "Creating Pterodactyl administrator"

    cd "$PANEL_DIR"

    php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USERNAME" \
        --password="$ADMIN_PASSWORD" \
        --name-first="Zyrex" \
        --name-last="Admin" \
        --admin=1 \
        --no-interaction

    ok "Administrator account created."
}

# -------------------- Blueprint --------------------

install_blueprint() {
    [[ "$INSTALL_BLUEPRINT" == "yes" ]] || {
        info "Blueprint installation skipped."
        return 0
    }

    step "Optional Blueprint installation"

    cd "$PANEL_DIR"

    shopt -s nullglob
    local packages=( ./*.blueprint )
    shopt -u nullglob

    if (( ${#packages[@]} == 0 )); then
        warn "No .blueprint files found in ${PANEL_DIR}."
        return 0
    fi

    if ! command -v blueprint >/dev/null 2>&1; then
        warn "Blueprint CLI is not installed."
        warn "Skipping rather than downloading an unknown/incompatible framework."
        return 0
    fi

    export NVM_DIR="/root/.nvm"
    # shellcheck disable=SC1090
    source "$NVM_DIR/nvm.sh"
    nvm use "$NODE_MAJOR" >/dev/null

    info "Node.js: $(node -v)"
    info "Yarn: $(yarn --version)"
    info "Yarn has already finished before this step."

    local package
    for package in "${packages[@]}"; do
        info "Installing $(basename "$package")..."
        blueprint -install "$package"
    done

    ok "Blueprint package step completed."
}

health_check() {
    step "Final health check"

    cd "$PANEL_DIR"

    php artisan --version || true
    echo
    info "Panel URL : $([[ "$SSL_TYPE" == "none" ]] && echo "http" || echo "https")://${DOMAIN}"
    info "PHP      : $(php -v | head -n1)"
    info "Node     : $(node -v)"
    info "Yarn     : $(yarn --version)"
    info "Nginx    : $(systemctl is-active nginx || true)"
    info "MariaDB  : $(systemctl is-active mariadb || true)"
    info "Redis    : $(systemctl is-active redis-server || true)"
    info "Queue    : $(systemctl is-active pteroq.service || true)"
    info "Cron     : $(systemctl is-active cron || true)"

    nginx -t

    ok "Health check completed."
}

show_success() {
    clear 2>/dev/null || true

    local scheme="https"
    [[ "$SSL_TYPE" == "none" ]] && scheme="http"

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║             ZYREXPTERO INSTALLATION COMPLETE              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "  ${GREEN}✔${NC} Panel URL : ${WHITE}${scheme}://${DOMAIN}${NC}"
    echo -e "  ${GREEN}✔${NC} Username  : ${WHITE}${ADMIN_USERNAME}${NC}"
    echo -e "  ${GREEN}✔${NC} Password  : ${WHITE}${ADMIN_PASSWORD}${NC}"
    echo -e "  ${GREEN}✔${NC} Email     : ${WHITE}${ADMIN_EMAIL}${NC}"
    echo -e "  ${GREEN}✔${NC} Database  : ${WHITE}${DB_NAME}${NC}"
    echo -e "  ${GREEN}✔${NC} DB User   : ${WHITE}${DB_USER}${NC}"
    echo -e "  ${GREEN}✔${NC} SSL       : ${WHITE}${SSL_NAME}${NC}"
    echo -e "  ${GREEN}✔${NC} Node.js   : ${WHITE}$(node -v)${NC}"
    echo
    echo -e "  ${GOLD}IMPORTANT:${NC} Save your APP_KEY and administrator credentials securely."
    echo -e "  ${GRAY}Panel directory: ${PANEL_DIR}${NC}"
}

main() {
    require_root
    detect_platform

    # IMPORTANT: all questions happen before installation.
    collect_config
    review_config

    install_base
    setup_php_repo
    install_services
    install_composer
    install_node22

    download_panel
    setup_database
    setup_env
    install_php_dependencies

    # MUST finish before any Blueprint step.
    install_frontend_dependencies

    generate_key_and_migrate

    # HTTP first is required for Let's Encrypt validation.
    configure_http_first
    configure_ssl

    setup_queue
    setup_cron
    finalize_panel
    create_admin
    install_blueprint

    health_check
    show_success
}

main "$@"
