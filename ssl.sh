#!/bin/bash

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color
PHP_VERSION="8.3"

# --- Header ---
clear
echo -e "${CYAN}${BOLD}=========================================${NC}"
echo -e "${CYAN}     PTERODACTYL NGINX CONFIGURATOR      ${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# --- Get Domain First ---
echo -e "${CYAN}--- Configuration Details ---${NC}"
read -p "Enter your Domain (e.g., panel.example.com): " DOMAIN
echo ""

# --- Check & Prepare ---
echo -e "${YELLOW}[*] Checking environment...${NC}"
if [ ! -d "/var/www/pterodactyl" ]; then
    echo -e "${RED}[!] Pterodactyl directory not found! Exiting.${NC}"
    exit 1
fi

cd /var/www/pterodactyl || exit

# --- Remove old configs ---
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/nginx/sites-enabled/pterodactyl.conf

# ================= MENUS =================
echo -e "${BOLD}Select Configuration Mode:${NC}"
echo -e "  ${GREEN}[1]${NC} SSL Configuration"
echo -e "  ${RED}[2]${NC} No SSL Configuration"
read -p "Select option [1-2]: " MAIN_MENU

echo ""

if [ "$MAIN_MENU" == "1" ]; then
    # --- SSL MENU ---
    echo -e "${BOLD}--- Menu 1: SSL ---${NC}"
    echo -e "  ${GREEN}[1]${NC} Local SSL (Use Existing Certificates)"
    echo -e "  ${GREEN}[2]${NC} Certbot SSL (Auto Install & Generate)"
    read -p "Select option [1-2]: " SUB_MENU

    if [ "$SUB_MENU" == "1" ]; then
        # ---------------------------------------------------------
        # OPTION 1.1: LOCAL SSL (EXISTING CERTS)
        # ---------------------------------------------------------
        echo -e "\n${YELLOW}[?] SSL Certificate Path Selection:${NC}"
        echo -e "    ${BOLD}y${NC} = Let's Encrypt Default (/etc/letsencrypt/live/${DOMAIN})"
        echo -e "    ${BOLD}n${NC} = Custom/Default Path (/etc/certs/panel)"
        read -p "Use Let's Encrypt default path? (y/n): " SSLTYPE

        if [ "$SSLTYPE" == "y" ]; then
            FULLCHAIN="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
            PRIVKEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        else
            FULLCHAIN="/etc/certs/panel/fullchain.pem"
            PRIVKEY="/etc/certs/panel/privkey.pem"
        fi

        echo -e "${GREEN}[+] Setting APP_URL to HTTPS...${NC}"
        sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env

        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    ssl_certificate ${FULLCHAIN};
    ssl_certificate_key ${PRIVKEY};

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
        
        ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        echo -e "${YELLOW}[*] Testing and Restarting Nginx...${NC}"
        nginx -t && systemctl restart nginx
        
        echo -e "\n${GREEN}✔ Local SSL Setup Completed!${NC}"
        echo -e "Panel URL: ${BOLD}https://${DOMAIN}${NC}\n"

    elif [ "$SUB_MENU" == "2" ]; then
        # ---------------------------------------------------------
        # OPTION 1.2: CERTBOT SSL (AUTO GENERATE)
        # ---------------------------------------------------------
        # To use Certbot with Nginx effectively, we first need a basic port 80 block
        echo -e "\n${YELLOW}[*] Setting up base HTTP config for Certbot...${NC}"
        
        sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env

        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    
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
}
EOF
        ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        systemctl restart nginx

        echo -e "${YELLOW}[*] Installing Certbot and generating SSL...${NC}"
        apt update -y
        apt install certbot python3-certbot-nginx -y
        
        EMAIL="ssl$(tr -dc a-z0-9 </dev/urandom | head -c6)@nobita.com"
        certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m ${EMAIL} --redirect

        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✔ Certbot SSL Installed Successfully!${NC}"
            echo -e "Your Panel is live at: ${BOLD}https://${DOMAIN}${NC}\n"
        else
            echo -e "\n${RED}[!] SSL Generation Failed. Check if your domain points to this server's IP.${NC}\n"
        fi
    else
        echo -e "${RED}[!] Invalid option.${NC}"
        exit 1
    fi

elif [ "$MAIN_MENU" == "2" ]; then
    # --- NO SSL MENU ---
    echo -e "${BOLD}--- Menu 2: No SSL ---${NC}"
    echo -e "  ${RED}[1]${NC} HTTP Only (Standard, Insecure)"
    echo -e "  ${GREEN}[2]${NC} HTTP + Certbot Gen (Creates HTTP then installs SSL)"
    read -p "Select option [1-2]: " SUB_MENU

    if [ "$SUB_MENU" == "1" ]; then
        # ---------------------------------------------------------
        # OPTION 2.1: STANDARD HTTP
        # ---------------------------------------------------------
        echo -e "\n${GREEN}[+] Setting APP_URL to HTTP...${NC}"
        sed -i "s|APP_URL=.*|APP_URL=http://${DOMAIN}|g" .env

        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;
    charset utf-8;

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
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize=100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
        ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        echo -e "${YELLOW}[*] Testing and Restarting Nginx...${NC}"
        nginx -t && systemctl restart nginx

        echo -e "\n${GREEN}✔ HTTP Setup Completed!${NC}"
        echo -e "Panel URL: ${BOLD}http://${DOMAIN}${NC}\n"

    elif [ "$SUB_MENU" == "2" ]; then
        # ---------------------------------------------------------
        # OPTION 2.2: HTTP + CERTBOT GEN
        # ---------------------------------------------------------
        echo -e "\n${GREEN}[+] Generating HTTP configuration first...${NC}"
        sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env

        cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.php;
    charset utf-8;
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
}
EOF
        ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        systemctl restart nginx

        echo -e "${YELLOW}[*] Installing Certbot and configuring SSL...${NC}"
        apt update -y
        apt install certbot python3-certbot-nginx -y
        
        EMAIL="ssl$(tr -dc a-z0-9 </dev/urandom | head -c6)@nobita.com"
        certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos -m ${EMAIL} --redirect

        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✔ HTTP + Certbot Setup Completed Successfully!${NC}"
            echo -e "Your Panel is live at: ${BOLD}https://${DOMAIN}${NC}\n"
        else
            echo -e "\n${RED}[!] Certbot Generation Failed. Check if your domain points to this IP.${NC}\n"
        fi
    else
        echo -e "${RED}[!] Invalid option.${NC}"
        exit 1
    fi

else
    echo -e "${RED}[!] Invalid Option selected. Exiting.${NC}"
    exit 1
fi
