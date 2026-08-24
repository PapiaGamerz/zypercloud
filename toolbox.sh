#!/bin/bash

# =========================================================
#  NEON SYSTEM TOOLBOX MANAGER
# =========================================================

# --- COLOR PALETTE ---
CYAN='\033[38;5;51m'
PURPLE='\033[38;5;141m'
GRAY='\033[38;5;242m'
WHITE='\033[38;5;255m'
GREEN='\033[38;5;82m'
RED='\033[38;5;196m'
GOLD='\033[38;5;214m'
YELLOW='\033[38;5;228m'
BLUE='\033[38;5;39m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

HEADER_LINE="${GRAY}────────────────────────────────────────────────────────────${NC}"

# Root Check
if [ "$EUID" -ne 0 ]; then
  echo -e "  ${RED}[!] Please run this script as root.${NC}"
  exit 1
fi

# Helper Pause Function
pause_tool() {
    echo ""
    echo -ne "  ${GRAY}Press any key to return to Toolbox...${NC}"
    read -n 1 -s -r
}

# Dynamic System Metrics Data
get_system_info() {
    UPTIME_SYS=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
    LOAD_SYS=$(uptime | awk -F'load average:' '{ print $2 }' | xargs)
    CPU_CORES=$(nproc 2>/dev/null || echo "1")
    
    # RAM Usage
    MEM_FREE=$(free -h 2>/dev/null | awk '/Mem:/ {print $4}')
    MEM_TOTAL=$(free -h 2>/dev/null | awk '/Mem:/ {print $2}')
    MEM_USED=$(free -h 2>/dev/null | awk '/Mem:/ {print $3}')
    
    # Disk Usage
    DISK_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
    
    # OS Info
    if [ -f /etc/os-release ]; then
        OS_NAME=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release)
    else
        OS_NAME=$(uname -s)
    fi
}

# Toolbox Dashboard Header
show_header() {
    clear
    get_system_info
    echo -e "${PURPLE}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}  ║${WHITE}${BOLD}              ⚡ ULTIMATE SYSTEM TOOLBOX ⚡              ${PURPLE}║${NC}"
    echo -e "${PURPLE}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}${BOLD}📊 SYSTEM METRICS & STATUS${NC}"
    echo -e "  ${GRAY}├─${NC} ${DIM}OS System${NC}     : ${WHITE}$OS_NAME${NC}"
    echo -e "  ${GRAY}├─${NC} ${DIM}System Uptime${NC} : ${GREEN}${BOLD}$UPTIME_SYS${NC}"
    echo -e "  ${GRAY}├─${NC} ${DIM}Cpu Cores / Load${NC}: ${WHITE}$CPU_CORES Cores${NC} ${GRAY}[Load: $LOAD_SYS]${NC}"
    echo -e "  ${GRAY}├─${NC} ${DIM}Memory (RAM)${NC}  : ${WHITE}$MEM_USED / $MEM_TOTAL${NC} ${GRAY}(Free: $MEM_FREE)${NC}"
    echo -e "  ${GRAY}└─${NC} ${DIM}Disk Storage${NC}  : ${WHITE}$DISK_USAGE${NC}"
    echo -e "${HEADER_LINE}"
}

# --- INSTALL / UNINSTALL WORKFLOW FOR TAILSCALE ---
install_tailscale_workflow() {
    echo -e "\n  ${YELLOW}Installing Tailscale via Official Script...${NC}\n"
    curl -fsSL https://tailscale.com/install.sh | sh

    if command -v tailscale &>/dev/null; then
        echo -e "\n  ${GREEN}[✔] Tailscale installed successfully!${NC}\n"
        echo -e "${HEADER_LINE}"
        echo -e "  ${GOLD}${BOLD}Starting Tailscale Login Process...${NC}"
        echo -e "  ${GRAY}Follow the URL below to authenticate this machine:${NC}\n"
        tailscale up
    else
        echo -e "\n  ${RED}[!] Tailscale installation failed. Check network/dependencies.${NC}"
    fi
}

uninstall_tailscale_workflow() {
    echo -e "\n  ${YELLOW}Disconnecting and Uninstalling Tailscale...${NC}"
    tailscale down 2>/dev/null || true
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true
    apt-get remove --purge tailscale -y 2>/dev/null || rm -f $(which tailscale)
    rm -rf /var/lib/tailscale /etc/tailscale
    echo -e "  ${GREEN}[✔] Tailscale completely uninstalled.${NC}"
}

# --- TOOL 1: TAILSCALE MANAGER ---
manage_tailscale() {
    while true; do
        clear
        show_header
        echo -e "\n  ${GOLD}${BOLD}🔒 TAILSCALE VPN MANAGER${NC}\n"

        if command -v tailscale &>/dev/null; then
            echo -e "  ${GREEN}[✔] Status: INSTALLED${NC}"
            echo -e "  ${GRAY}Checking IP / Connection...${NC}"
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "Not Connected")
            echo -e "  ${GRAY}Tailscale IP:${NC} ${WHITE}$TS_IP${NC}"
        else
            echo -e "  ${RED}[!] Status: NOT INSTALLED${NC}"
        fi

        echo ""
        echo -e "  ${PURPLE}[1]${NC} ${WHITE}📥 Install Tailscale${NC}"
        echo -e "  ${PURPLE}[2]${NC} ${WHITE}🗑️  Uninstall Tailscale${NC}"
        echo -e "  ${RED}[0]${NC} ${WHITE}⬅️  Exit to Main Menu${NC}"
        echo ""
        echo -e "  ${GRAY}────────────────────────────────────────────────────────────${NC}"
        echo -ne "  ${CYAN}λ Select Action [0-2]: ${NC}"
        read ts_menu_choice

        case $ts_menu_choice in
            1)
                install_tailscale_workflow
                pause_tool
                ;;
            2)
                uninstall_tailscale_workflow
                pause_tool
                ;;
            0|exit|back|q)
                return
                ;;
            *)
                echo -e "\n  ${RED}[!] Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# --- INSTALL / UNINSTALL WORKFLOW FOR CLOUDFLARE ---
install_cloudflared_workflow() {
    echo -e "\n  ${YELLOW}Adding Cloudflare GPG Key...${NC}"
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

    echo -e "  ${YELLOW}Adding Cloudflare Repository...${NC}"
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list >/dev/null

    echo -e "  ${YELLOW}Updating package list and installing cloudflared...${NC}"
    apt-get update -y && apt-get install -y cloudflared

    if command -v cloudflared &>/dev/null; then
        echo -e "\n  ${GREEN}[✔] Cloudflare Tunnel installed successfully!${NC}\n"
        echo -e "${HEADER_LINE}"
        echo -ne "  ${GOLD}${BOLD}Enter your Cloudflare Tunnel Token (or full command): ${NC}"
        read raw_token

        # Extract token if full command was pasted
        CLEAN_TOKEN=$(echo "$raw_token" | sed -E 's/.*service install //g' | xargs)

        if [ -n "$CLEAN_TOKEN" ]; then
            echo -e "\n  ${YELLOW}Configuring & Installing Cloudflare Tunnel Service...${NC}"
            cloudflared service install "$CLEAN_TOKEN"
            systemctl start cloudflared 2>/dev/null || true
            systemctl enable cloudflared 2>/dev/null || true
            echo -e "  ${GREEN}[✔] Cloudflare Tunnel Service is now active and running!${NC}"
        else
            echo -e "  ${RED}[!] No Token provided. You can run 'cloudflared service install <TOKEN>' manually later.${NC}"
        fi
    else
        echo -e "  ${RED}[!] Installation failed. Please check network/dependencies.${NC}"
    fi
}

uninstall_cloudflared_workflow() {
    echo -e "\n  ${YELLOW}Uninstalling Cloudflare Tunnel (cloudflared)...${NC}"
    cloudflared service uninstall 2>/dev/null || true
    systemctl stop cloudflared 2>/dev/null || true
    systemctl disable cloudflared 2>/dev/null || true
    apt-get remove --purge cloudflared -y 2>/dev/null || rm -f $(which cloudflared)
    rm -f /etc/apt/sources.list.d/cloudflared.list /usr/share/keyrings/cloudflare-public-v2.gpg
    echo -e "  ${GREEN}[✔] Cloudflare Tunnel completely uninstalled.${NC}"
}

# --- TOOL 2: CLOUDFLARE TUNNEL MANAGER ---
manage_cloudflare() {
    while true; do
        clear
        show_header
        echo -e "\n  ${GOLD}${BOLD}☁️ CLOUDFLARE TUNNEL (cloudflared) MANAGER${NC}\n"

        if command -v cloudflared &>/dev/null; then
            echo -e "  ${GREEN}[✔] Status: INSTALLED${NC}"
            echo -e "  ${GRAY}Version :${NC} $(cloudflared --version 2>/dev/null | head -n 1)"
        else
            echo -e "  ${RED}[!] Status: NOT INSTALLED${NC}"
        fi

        echo ""
        echo -e "  ${PURPLE}[1]${NC} ${WHITE}📥 Install Cloudflare Tunnel${NC}"
        echo -e "  ${PURPLE}[2]${NC} ${WHITE}🗑️  Uninstall Cloudflare Tunnel${NC}"
        echo -e "  ${RED}[0]${NC} ${WHITE}⬅️  Exit to Main Menu${NC}"
        echo ""
        echo -e "  ${GRAY}────────────────────────────────────────────────────────────${NC}"
        echo -ne "  ${CYAN}λ Select Action [0-2]: ${NC}"
        read cf_menu_choice

        case $cf_menu_choice in
            1)
                install_cloudflared_workflow
                pause_tool
                ;;
            2)
                uninstall_cloudflared_workflow
                pause_tool
                ;;
            0|exit|back|q)
                return
                ;;
            *)
                echo -e "\n  ${RED}[!] Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# --- MAIN TOOLBOX MENU LOOP ---
main_toolbox() {
    while true; do
        show_header

        echo -e "\n  ${GOLD}${BOLD}🧰 AVAILABLE UTILITIES${NC}\n"
        echo -e "  ${PURPLE}[1]${NC} ${WHITE}🔒 Tailscale VPN${NC}          ${GRAY}(Mesh VPN & Remote Access)${NC}"
        echo -e "  ${PURPLE}[2]${NC} ${WHITE}☁️  Cloudflare Tunnel Manager${NC} ${GRAY}(Manage Tunnel & Service)${NC}"
        echo -e "  ${PURPLE}[3]${NC} ${WHITE}🔄 Refresh Metrics${NC}        ${GRAY}(Update System Live Status)${NC}"
        echo -e "  ${RED}[0]${NC} ${WHITE}⬅️  Exit / Back to Menu${NC}   ${GRAY}(Return to Main Script)${NC}"
        echo ""
        echo -e "  ${GRAY}────────────────────────────────────────────────────────────${NC}"
        echo -ne "  ${CYAN}λ Select Tool [0-3]: ${NC}"
        read choice

        case $choice in
            1)
                manage_tailscale
                ;;
            2)
                manage_cloudflare
                ;;
            3)
                echo -e "  ${GREEN}Refreshing...${NC}"
                sleep 0.5
                ;;
            0|exit|back|q)
                echo -e "\n  ${YELLOW}Returning to main menu...${NC}\n"
                exit 0
                ;;
            *)
                echo -e "\n  ${RED}[!] Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run Toolbox
main_toolbox
