#!/bin/bash

green="\e[38;5;82m"
red="\e[38;5;196m"
neutral="\e[0m"
orange="\e[38;5;130m"
blue="\e[38;5;39m"
yellow="\e[38;5;226m"
purple="\e[38;5;141m"
bold_white="\e[1;37m"
reset="\e[0m"
pink="\e[38;5;205m"

print_rainbow() {
local text="$1"
local length=${#text}
local start_color=(0 5 0)
local mid_color=(0 200 0)
local end_color=(0 5 0)
for ((i = 0; i < length; i++)); do
local progress=$(echo "scale=2; $i / ($length - 1)" | bc)
if (($(echo "$progress < 0.5" | bc -l))); then
local factor=$(echo "scale=2; $progress * 2" | bc)
r=$(echo "scale=0; (${start_color[0]} * (1-$factor) + ${mid_color[0]} * $factor)/1" | bc)
g=$(echo "scale=0; (${start_color[1]} * (1-$factor) + ${mid_color[1]} * $factor)/1" | bc)
b=$(echo "scale=0; (${start_color[2]} * (1-$factor) + ${mid_color[2]} * $factor)/1" | bc)
else
local factor=$(echo "scale=2; ($progress - 0.5) * 2" | bc)
r=$(echo "scale=0; (${mid_color[0]} * (1-$factor) + ${end_color[0]} * $factor)/1" | bc)
g=$(echo "scale=0; (${mid_color[1]} * (1-$factor) + ${end_color[1]} * $factor)/1" | bc)
b=$(echo "scale=0; (${mid_color[2]} * (1-$factor) + ${end_color[2]} * $factor)/1" | bc)
fi
printf "\e[38;2;%d;%d;%dm%s" "$r" "$g" "$b" "${text:$i:1}"
done
echo -e "$reset"
}

cek_status() {
status=$(systemctl is-active --quiet $1 && echo "aktif" || echo "nonaktif")
if [ "$status" = "aktif" ]; then
echo -e "${green}GOOD${neutral}"
else
echo -e "${red}BAD${neutral}"
fi
}

# Main execution
clear
print_rainbow "════════════════════════════════════════════════════════════"
print_rainbow "                   API INSTALL SCRIPT                       "
print_rainbow "                    Created by PeyxDev                       "
print_rainbow "════════════════════════════════════════════════════════════"
echo ""

# Install Node.js
echo -e "${yellow}[1/7] Installing Node.js...${neutral}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
apt-get install -y nodejs >/dev/null 2>&1
echo -e "${green}✅ Node.js installed${neutral}"

# Install npm
echo -e "${yellow}[2/7] Installing npm...${neutral}"
apt-get install -y npm >/dev/null 2>&1
echo -e "${green}✅ npm installed${neutral}"

# Setup directories
echo -e "${yellow}[3/7] Creating directories...${neutral}"
mkdir -p /etc/peyx-api
mkdir -p /etc/peyx
mkdir -p /etc/peyx/limit/trojan/ip
mkdir -p /etc/peyx/limit/vless/ip
mkdir -p /etc/peyx/limit/vmess/ip
mkdir -p /etc/peyx/limit/ssh/ip
echo -e "${green}✅ Directories created${neutral}"

# Download server.js from repo
echo -e "${yellow}[4/7] Downloading server.js from repo...${neutral}"
curl -sL "https://raw.githubusercontent.com/PeyxDev/esce/main/api/server.js" -o /etc/peyx-api/server.js

if [ -f /etc/peyx-api/server.js ]; then
    echo -e "${green}✅ server.js downloaded successfully${neutral}"
else
    echo -e "${red}❌ Failed to download server.js${neutral}"
    exit 1
fi

# Install npm packages (express & axios)
echo -e "${yellow}[5/7] Installing npm packages (express, axios)...${neutral}"
cd /etc/peyx-api
npm install express --save >/dev/null 2>&1
npm install axios --save >/dev/null 2>&1
echo -e "${green}✅ npm packages installed${neutral}"

# Generate AUTH_KEY
RANDOM_CHARS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c10)
AUTH_KEY="PX-${RANDOM_CHARS}"
echo "$AUTH_KEY" > /etc/peyx-api/px-auth
echo -e "${green}✅ AUTH_KEY generated: $AUTH_KEY${neutral}"

# Create service
echo -e "${yellow}[6/7] Creating systemd service...${neutral}"
cat > /etc/systemd/system/api.service << EOF
[Unit]
Description=API Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node /etc/peyx-api/server.js
Restart=always
RestartSec=3
User=root
WorkingDirectory=/etc/peyx-api

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable api.service >/dev/null 2>&1
systemctl restart api.service
echo -e "${green}✅ Service created and started${neutral}"

# Get server IP
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null)

clear
print_rainbow "════════════════════════════════════════════════════════════"
print_rainbow "                  INSTALLATION COMPLETE                    "
print_rainbow "════════════════════════════════════════════════════════════"
echo ""
echo -e "${bold_white}📡 API SERVER (Port 8585)${neutral}"
echo -e "${blue}  🔑 AUTH_KEY: ${green}$AUTH_KEY${neutral}"
echo -e "${blue}  🌐 API URL: ${green}http://$SERVER_IP:8585${neutral}"
echo -e "${blue}  📁 Folder: ${green}/etc/peyx-api${neutral}"
echo -e "${blue}  📊 Status: $(cek_status api.service)${neutral}"
echo ""
echo -e "${purple}════════════════════════════════════════════════════════════${neutral}"
echo -e "${yellow}📝 Useful Commands:${neutral}"
echo -e "  systemctl status api           - Check service status"
echo -e "  systemctl restart api          - Restart service"
echo -e "  systemctl stop api             - Stop service"
echo -e "  journalctl -u api -f           - View logs"
echo -e "  cat /etc/peyx-api/px-auth      - View AUTH_KEY"
echo ""
echo -e "${yellow}🧪 Test API:${neutral}"
echo -e "  curl -H 'x-api-key: $AUTH_KEY' http://localhost:8585/api/health"
echo -e "${purple}════════════════════════════════════════════════════════════${neutral}"