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
    echo -e "${PURPLE}  ║${WHITE}${BOLD}               ⚡ ULTIMATE SYSTEM TOOLBOX ⚡             ${PURPLE}║${NC}"
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

# --- TOOL 1: TAILSCALE MANAGER ---
manage_tailscale() {
    clear
    show_header
    echo -e "\n  ${GOLD}${BOLD}🔒 TAILSCALE VPN MANAGER${NC}\n"

    if command -v tailscale &>/dev/null; then
        echo -e "  ${GREEN}[✔] Tailscale is currently INSTALLED.${NC}"
        echo -e "  ${GRAY}Checking connection status...${NC}\n"
        tailscale status || true
        echo ""
        echo -e "  ${WHITE}[1] Connect / Login (tailscale up)${NC}"
        echo -e "  ${WHITE}[2] Disconnect (tailscale down)${NC}"
        echo -e "  ${WHITE}[3] Reinstall Tailscale${NC}"
        echo -e "  ${RED}[0] Back to Toolbox${NC}"
        echo ""
        echo -ne "  ${CYAN}λ Select Action [0-3]: ${NC}"
        read ts_choice

        case $ts_choice in
            1)
                echo -e "\n  ${YELLOW}Starting Tailscale... Follow the login URL if prompted:${NC}\n"
                tailscale up
                ;;
            2)
                tailscale down
                echo -e "\n  ${GREEN}[✔] Tailscale disconnected.${NC}"
                ;;
            3)
                echo -e "\n  ${YELLOW}Reinstalling Tailscale...${NC}"
                curl -fsSL https://tailscale.com/install.sh | sh
                ;;
            *) return ;;
        esac
    else
        echo -e "  ${RED}[!] Tailscale is NOT installed on this machine.${NC}"
        echo -ne "\n  ${CYAN}Would you like to install Tailscale now? (y/n): ${NC}"
        read inst_ts
        if [[ "$inst_ts" =~ ^[Yy]$ ]]; then
            echo -e "\n  ${YELLOW}Installing Tailscale via Official Script...${NC}\n"
            curl -fsSL https://tailscale.com/install.sh | sh
            echo -e "\n  ${GREEN}[✔] Tailscale installation finished!${NC}"
            echo -e "  ${WHITE}Run 'tailscale up' to authenticate.${NC}"
        fi
    fi
    pause_tool
}

# --- TOOL 2: CLOUDFLARE TUNNEL MANAGER ---
manage_cloudflare() {
    clear
    show_header
    echo -e "\n  ${GOLD}${BOLD}☁️ CLOUDFLARE TUNNEL (cloudflared) MANAGER${NC}\n"

    if command -v cloudflared &>/dev/null; then
        echo -e "  ${GREEN}[✔] cloudflared is INSTALLED.${NC}"
        echo -e "  ${GRAY}Version:${NC} $(cloudflared --version)"
        echo ""
        echo -e "  ${WHITE}[1] Run Quick Tunnel (HTTP Port Forward)${NC}"
        echo -e "  ${WHITE}[2] Authenticate Cloudflare (cloudflared tunnel login)${NC}"
        echo -e "  ${WHITE}[3] Reinstall / Update cloudflared${NC}"
        echo -e "  ${RED}[0] Back to Toolbox${NC}"
        echo ""
        echo -ne "  ${CYAN}λ Select Action [0-3]: ${NC}"
        read cf_choice

        case $cf_choice in
            1)
                echo -ne "\n  ${PURPLE}•${NC} ${WHITE}Enter Local Port to Forward (e.g., 80 or 8080): ${NC}"
                read cf_port
                if [ -n "$cf_port" ]; then
                    echo -e "\n  ${GREEN}Starting temporary Cloudflare Tunnel on port $cf_port...${NC}"
                    echo -e "  ${GRAY}(Press Ctrl+C to stop the tunnel)${NC}\n"
                    cloudflared tunnel --url "http://localhost:$cf_port"
                fi
                ;;
            2)
                cloudflared tunnel login
                ;;
            3)
                echo -e "\n  ${YELLOW}Updating cloudflared...${NC}"
                curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
                dpkg -i cloudflared.deb && rm -f cloudflared.deb
                ;;
            *) return ;;
        esac
    else
        echo -e "  ${RED}[!] cloudflared is NOT installed.${NC}"
        echo -ne "\n  ${CYAN}Would you like to install Cloudflare Tunnel now? (y/n): ${NC}"
        read inst_cf
        if [[ "$inst_cf" =~ ^[Yy]$ ]]; then
            echo -e "\n  ${YELLOW}Downloading and Installing Cloudflare Agent...${NC}"
            curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb 2>/dev/null
            dpkg -i cloudflared.deb 2>/dev/null || apt-get install -f -y
            rm -f cloudflared.deb
            echo -e "\n  ${GREEN}[✔] Cloudflare Tunnel installed successfully!${NC}"
        fi
    fi
    pause_tool
}

# --- MAIN TOOLBOX MENU LOOP ---
main_toolbox() {
    while true; do
        show_header

        echo -e "\n  ${GOLD}${BOLD}🧰 AVAILABLE UTILITIES${NC}\n"
        echo -e "  ${PURPLE}[1]${NC} ${WHITE}🔒 Tailscale VPN${NC}          ${GRAY}(Mesh VPN & Remote Access)${NC}"
        echo -e "  ${PURPLE}[2]${NC} ${WHITE}☁️  Cloudflare Tunnel${NC}     ${GRAY}(Expose Local Ports to Web)${NC}"
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
