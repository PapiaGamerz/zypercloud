#!/usr/bin/env bash

# ============================================================
# Pterodactyl Nginx Manager v3.0
# Modern Nginx + SSL/HTTP configurator for Pterodactyl Panel
# Supports:
#   1) HTTPS with existing Let's Encrypt certificate
#   2) HTTP only
#   3) Automatic HTTPS with Certbot
# ============================================================

set -o pipefail

# -----------------------------#
# Configuration
# -----------------------------#
PTERO_DIR="/var/www/pterodactyl"
NGINX_SITE="/etc/nginx/sites-available/pterodactyl.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/pterodactyl.conf"
PHP_VERSION="${PHP_VERSION:-8.3}"
CERTBOT_EMAIL_DOMAIN="nobita.com"

# -----------------------------#
# Colors
# -----------------------------#
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# -----------------------------#
# Helpers
# -----------------------------#
trap 'echo -e "\n${RED}[!] Script interrupted.${NC}"; exit 130' INT

line() {
    printf '%*s\n' "$(tput cols 2>/dev/null || echo 70)" '' | tr ' ' '='
}

header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              PTERODACTYL NGINX MANAGER v3.0              ║"
    echo "║                  Modern Panel Configurator                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[FAIL]${NC} $*"; }
step()    { echo -e "${BLUE}[....]${NC} $*"; }

pause() {
    echo
    read -r -p "Press Enter to continue..." _
}

die() {
    error "$*"
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Please run this script as root: sudo bash $0"
    fi
}

check_dependencies() {
    local missing=()

    command -v nginx >/dev/null 2>&1 || missing+=("nginx")
    command -v systemctl >/dev/null 2>&1 || missing+=("systemd")

    if (( ${#missing[@]} > 0 )); then
        error "Missing required dependencies: ${missing[*]}"
        read -r -p "Install Nginx now? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            apt-get update -y || die "apt update failed."
            apt-get install -y nginx || die "Nginx installation failed."
        else
            die "Required dependency is missing."
        fi
    fi
}

check_pterodactyl() {
    [[ -d "$PTERO_DIR" ]] || die "Pterodactyl directory not found: $PTERO_DIR"
    [[ -f "$PTERO_DIR/.env" ]] || warn "Pterodactyl .env was not found."
}

validate_domain() {
    local domain="$1"

    [[ -n "$domain" ]] || return 1
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
    [[ "$domain" != *".."* ]] || return 1

    return 0
}

ask_domain() {
    while true; do
        read -r -p "Enter panel domain (e.g. panel.example.com): " DOMAIN
        DOMAIN="${DOMAIN,,}"
        DOMAIN="${DOMAIN#http://}"
        DOMAIN="${DOMAIN#https://}"
        DOMAIN="${DOMAIN%%/*}"

        if validate_domain "$DOMAIN"; then
            break
        fi

        error "Invalid domain format."
    done
}

detect_php_socket() {
    local socket="/run/php/php${PHP_VERSION}-fpm.sock"

    if [[ -S "$socket" ]]; then
        PHP_SOCKET="$socket"
        return 0
    fi

    local detected
    detected="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' 2>/dev/null | sort -V | tail -n1)"

    if [[ -n "$detected" ]]; then
        PHP_SOCKET="$detected"
        warn "PHP ${PHP_VERSION} socket not found. Using detected socket: $PHP_SOCKET"
        return 0
    fi

    error "No PHP-FPM socket was found."
    error "Expected: $socket"
    return 1
}

update_app_url() {
    local url="$1"

    [[ -f "$PTERO_DIR/.env" ]] || {
        warn "Skipping APP_URL update because .env does not exist."
        return 0
    }

    if grep -q '^APP_URL=' "$PTERO_DIR/.env"; then
        sed -i "s|^APP_URL=.*|APP_URL=${url}|" "$PTERO_DIR/.env"
    else
        printf '\nAPP_URL=%s\n' "$url" >> "$PTERO_DIR/.env"
    fi

    success "APP_URL updated to ${url}"
}

prepare_nginx() {
    step "Preparing Nginx configuration..."

    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-available/pterodactyl.conf

    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
}

enable_nginx_site() {
    ln -sfn "$NGINX_SITE" "$NGINX_ENABLED"
}

write_http_config() {
    cat > "$NGINX_SITE" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};

    root ${PTERO_DIR}/public;
    index index.php;
    charset utf-8;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
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

    location ~ /\\.ht {
        deny all;
    }
}
EOF

    enable_nginx_site
}

write_https_config() {
    local cert="$1"
    local key="$2"

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

    root ${PTERO_DIR}/public;
    index index.php;
    charset utf-8;

    ssl_certificate ${cert};
    ssl_certificate_key ${key};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
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

    location ~ /\\.ht {
        deny all;
    }
}
EOF

    enable_nginx_site
}

nginx_test_restart() {
    step "Testing Nginx configuration..."

    if ! nginx -t; then
        error "Nginx configuration test failed."
        return 1
    fi

    success "Nginx configuration test passed."

    step "Reloading Nginx..."
    if systemctl reload nginx 2>/dev/null; then
        success "Nginx reloaded successfully."
    else
        systemctl restart nginx || {
            error "Unable to restart Nginx."
            return 1
        }
        success "Nginx restarted successfully."
    fi
}

random_email() {
    echo "ssl$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)@${CERTBOT_EMAIL_DOMAIN}"
}

install_certbot() {
    if command -v certbot >/dev/null 2>&1; then
        success "Certbot is already installed."
        return 0
    fi

    step "Updating package repositories..."
    apt-get update -y || return 1

    step "Installing Certbot and Nginx plugin..."
    apt-get install -y certbot python3-certbot-nginx || return 1

    success "Certbot installed."
}

setup_http() {
    header
    echo -e "${BOLD}HTTP / No SSL Configuration${NC}\n"

    ask_domain
    check_pterodactyl
    detect_php_socket || return 1

    prepare_nginx
    update_app_url "http://${DOMAIN}"
    write_http_config
    nginx_test_restart || return 1

    echo
    line
    success "HTTP setup completed!"
    echo -e "Panel URL: ${BOLD}http://${DOMAIN}${NC}"
    echo -e "PHP-FPM:   ${PHP_SOCKET}"
    line
}

setup_existing_ssl() {
    header
    echo -e "${BOLD}HTTPS / Existing Certificate${NC}\n"

    ask_domain
    check_pterodactyl
    detect_php_socket || return 1

    echo
    echo -e "${YELLOW}Certificate source:${NC}"
    echo "  [1] Let's Encrypt"
    echo "  [2] Custom /etc/certs/panel"
    echo

    local source
    read -r -p "Select [1-2]: " source

    local cert key

    case "$source" in
        1)
            cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
            key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
            ;;
        2)
            cert="/etc/certs/panel/fullchain.pem"
            key="/etc/certs/panel/privkey.pem"
            ;;
        *)
            error "Invalid certificate source."
            return 1
            ;;
    esac

    if [[ ! -f "$cert" || ! -f "$key" ]]; then
        error "Certificate files were not found."
        echo -e "Certificate: ${cert}"
        echo -e "Private key: ${key}"
        echo
        warn "Use Automatic Certbot HTTPS if you need a new certificate."
        return 1
    fi

    prepare_nginx
    update_app_url "https://${DOMAIN}"
    write_https_config "$cert" "$key"
    nginx_test_restart || return 1

    echo
    line
    success "HTTPS setup completed!"
    echo -e "Panel URL: ${BOLD}https://${DOMAIN}${NC}"
    echo -e "Certificate: ${cert}"
    line
}

setup_auto_ssl() {
    header
    echo -e "${BOLD}Automatic HTTPS / Certbot${NC}\n"

    ask_domain
    check_pterodactyl

    step "Installing Certbot..."
    install_certbot || {
        error "Certbot installation failed."
        return 1
    }

    # Certbot's Nginx plugin needs a valid HTTP server block first.
    detect_php_socket || return 1
    prepare_nginx
    update_app_url "http://${DOMAIN}"
    write_http_config

    nginx_test_restart || return 1

    local email
    email="$(random_email)"

    echo
    warn "Before continuing, make sure:"
    echo "  • ${DOMAIN} points to this server"
    echo "  • Port 80 is reachable"
    echo "  • Port 443 is reachable"
    echo

    read -r -p "Continue with automatic SSL? [Y/n]: " confirm
    [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]] || {
        warn "SSL setup cancelled."
        return 0
    }

    step "Requesting Let's Encrypt certificate..."
    if certbot --nginx \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        -m "$email" \
        --redirect \
        --keep-until-expiring; then

        update_app_url "https://${DOMAIN}"

        echo
        line
        success "Automatic SSL setup completed!"
        echo -e "Panel URL: ${BOLD}https://${DOMAIN}${NC}"
        echo -e "Certbot email: ${email}"
        echo -e "Renewal test:  ${BOLD}certbot renew --dry-run${NC}"
        line
    else
        error "Certbot could not issue the certificate."
        echo -e "${YELLOW}Common causes:${NC}"
        echo "  1. DNS record is not pointing to this server."
        echo "  2. Port 80/443 is blocked."
        echo "  3. Another service is using the required ports."
        echo "  4. Let's Encrypt validation failed."
        return 1
    fi
}

show_status() {
    header
    echo -e "${BOLD}Current Pterodactyl / Nginx Status${NC}\n"

    if [[ -d "$PTERO_DIR" ]]; then
        success "Pterodactyl: ${PTERO_DIR}"
    else
        error "Pterodactyl: not found"
    fi

    if systemctl is-active --quiet nginx; then
        success "Nginx: running"
    else
        error "Nginx: stopped"
    fi

    if command -v php >/dev/null 2>&1; then
        echo -e "${CYAN}[INFO]${NC} PHP: $(php -r 'echo PHP_VERSION;' 2>/dev/null)"
    else
        warn "PHP CLI not found"
    fi

    if [[ -S "/run/php/php${PHP_VERSION}-fpm.sock" ]]; then
        success "PHP-FPM ${PHP_VERSION}: socket available"
    else
        warn "PHP-FPM ${PHP_VERSION}: socket not found"
    fi

    if [[ -L "$NGINX_ENABLED" ]]; then
        success "Nginx site: enabled"
    elif [[ -f "$NGINX_SITE" ]]; then
        warn "Nginx site: configured but not enabled"
    else
        warn "Nginx site: not configured"
    fi

    if [[ -f "$PTERO_DIR/.env" ]]; then
        local app_url
        app_url="$(grep -E '^APP_URL=' "$PTERO_DIR/.env" | tail -n1 | cut -d= -f2-)"
        [[ -n "$app_url" ]] && echo -e "${CYAN}[INFO]${NC} APP_URL: ${app_url}"
    fi

    echo
    echo -e "${DIM}Nginx config: ${NGINX_SITE}${NC}"
}

main_menu() {
    require_root
    check_dependencies

    while true; do
        header

        echo -e "${BOLD}Select Configuration Mode${NC}\n"
        echo -e "  ${GREEN}[1]${NC} HTTPS / Existing SSL"
        echo -e "  ${BLUE}[2]${NC} HTTP / No SSL"
        echo -e "  ${MAGENTA}[3]${NC} Automatic HTTPS / Certbot"
        echo -e "  ${CYAN}[4]${NC} View Status"
        echo -e "  ${RED}[0]${NC} Exit"
        echo

        read -r -p "Select option [0-4]: " option
        echo

        case "$option" in
            1)
                setup_existing_ssl
                pause
                ;;
            2)
                setup_http
                pause
                ;;
            3)
                setup_auto_ssl
                pause
                ;;
            4)
                show_status
                pause
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                error "Invalid option."
                sleep 1
                ;;
        esac
    done
}

main_menu
