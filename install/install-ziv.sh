#!/bin/bash

# ==================== INSTALL ZIVPN CORE ONLY ====================
# Colors
MODERN_CYAN="\033[38;2;0;255;255m"
MODERN_PURPLE="\033[38;2;156;0;255m"
MODERN_GREEN="\033[38;2;0;255;128m"
MODERN_RED="\033[38;2;255;50;50m"
MODERN_ORANGE="\033[38;2;255;128;0m"
MODERN_DIM="\033[2m"
MODERN_BOLD="\033[1m"
WHITE="\033[97;1m"
RESET_ALL="\033[0m"

SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
CHECK_ICON="✓"
CROSS_ICON="✗"

ZIVPN_UDP_PORT="5667"

# Path file yang sudah ada dari instalasi sebelumnya
DOMAIN_FILE="/etc/xray/domain"
API_KEY_FILE="/etc/peyx-api/px-auth"

show_loading_animation() {
    local pid=$1
    local message=$2
    local i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r${MODERN_CYAN}${SPINNER[$i]}${RESET_ALL} ${MODERN_DIM}${message}...${RESET_ALL}"
        i=$(( (i+1) % 10 ))
        sleep 0.1
    done
    printf "\r\033[K"
}

run_task() {
    local message="$1"
    local command="$2"
    printf "${MODERN_CYAN}◐${RESET_ALL} ${MODERN_DIM}${message}...${RESET_ALL}"
    bash -c "$command" &>/tmp/zivpn_core.log &
    local task_pid=$!
    show_loading_animation $task_pid "$message"
    wait $task_pid
    if [ $? -eq 0 ]; then
        printf "\r${MODERN_GREEN}${CHECK_ICON}${RESET_ALL} ${MODERN_BOLD}${message}${RESET_ALL} ${MODERN_GREEN}${CHECK_ICON}${RESET_ALL}\n"
        return 0
    else
        printf "\r${MODERN_RED}${CROSS_ICON}${RESET_ALL} ${MODERN_BOLD}${message}${RESET_ALL} ${MODERN_RED}${CROSS_ICON}${RESET_ALL}\n"
        return 1
    fi
}

print_section_header() {
    local title="$1"
    echo ""
    echo -e "${MODERN_PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_ALL}"
    echo -e "${MODERN_BOLD}${WHITE}  ${title}${RESET_ALL}"
    echo -e "${MODERN_PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_ALL}"
}

print_success() {
    echo -e "${MODERN_GREEN}  ${CHECK_ICON}${RESET_ALL} ${MODERN_BOLD}$1${RESET_ALL}"
}

print_info() {
    echo -e "${MODERN_CYAN}  •${RESET_ALL} $1"
}

print_value() {
    local label="$1"
    local value="$2"
    printf "  ${MODERN_CYAN}${label}:${RESET_ALL} ${MODERN_BOLD}${WHITE}${value}${RESET_ALL}\n"
}

print_warning() {
    echo -e "${MODERN_ORANGE}  ⚠${RESET_ALL} ${MODERN_BOLD}$1${RESET_ALL}"
}

print_error() {
    echo -e "${MODERN_RED}  ${CROSS_ICON}${RESET_ALL} ${MODERN_BOLD}$1${RESET_ALL}"
}

# ==================== AMBIL DOMAIN DARI FILE YANG SUDAH ADA ====================
if [ -f "$DOMAIN_FILE" ]; then
    domain=$(cat "$DOMAIN_FILE" | tr -d '\n\r')
    print_success "Domain loaded from $DOMAIN_FILE: $domain"
else
    if [ -f "/root/domain" ]; then
        domain=$(cat /root/domain | tr -d '\n\r')
        print_warning "Domain loaded from /root/domain: $domain"
    else
        print_error "Domain file not found!"
        exit 1
    fi
fi

# ==================== AMBIL API KEY DARI FILE YANG SUDAH ADA ====================
if [ -f "$API_KEY_FILE" ]; then
    API_KEY=$(cat "$API_KEY_FILE" | tr -d '\n\r')
    print_success "API Key loaded from $API_KEY_FILE"
else
    print_error "API Key file not found!"
    exit 1
fi

# ==================== CEK APAKAH UDP-CUSTOM TERINSTALL ====================
UDP_CUSTOM_EXISTS=false
if systemctl list-units --full -all | grep -q "udp-custom.service"; then
    UDP_CUSTOM_EXISTS=true
    print_warning "UDP-Custom service detected! Will configure priority rules."
fi

# ==================== MULAI INSTALL ZIVPN CORE ====================
print_section_header "🚀 Installing ZiVPN Core"

# Stop existing service
systemctl stop zivpn.service &>/dev/null

# Download Core
run_task "Downloading ZiVPN Core" "wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn && chmod +x /usr/local/bin/zivpn"

# Create directories
mkdir -p /etc/zivpn
echo "[]" > /etc/zivpn/users.json

# Download config.json dari repo (BAWAAN, TIDAK DIUBAH)
run_task "Downloading configuration" "wget -q https://raw.githubusercontent.com/PeyxDev/ZiVPN/main/config.json -O /etc/zivpn/config.json"

# Ganti port di config.json
sed -i "s/:5667/:${ZIVPN_UDP_PORT}/" /etc/zivpn/config.json

# Generate SSL certificate
run_task "Generating SSL certificate" "openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj '/C=ID/ST=Jawa Barat/L=Sukabumi/O=PX STORE/OU=IT Department/CN=$domain' -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt 2>/dev/null"

# Create systemd service
cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
LimitNOFILE=65535
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Start service
run_task "Starting ZiVPN Core" "systemctl daemon-reload && systemctl enable zivpn.service && systemctl start zivpn.service"

# ==================== KONFIGURASI IPTABLES DENGAN PRIORITAS ====================
print_section_header "🔧 Configuring iptables with priority"

iface=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

# Backup existing rules
iptables-save > /root/iptables-backup-$(date +%Y%m%d-%H%M%S).txt 2>/dev/null

# Hapus rule DNAT ZiVPN lama jika ada
iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :${ZIVPN_UDP_PORT} 2>/dev/null

# Hapus rule UDP-Custom catch-all jika ada (akan ditambahkan kembali)
if [ "$UDP_CUSTOM_EXISTS" = true ]; then
    iptables -t nat -D PREROUTING -i "$iface" -p udp --dport 1:65535 -j DNAT --to-destination :36712 2>/dev/null
fi

# Buat rules dengan urutan prioritas yang benar
# Rule 1: DNS (port 53)
iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 53 -j REDIRECT --to-port 5300 2>/dev/null

# Rule 2: ZiVPN untuk range port 6000-19999 (PRIORITAS UTAMA)
iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 6000:19999 -j DNAT --to-destination :${ZIVPN_UDP_PORT}

# Rule 3: UDP-Custom untuk semua port lainnya (catch-all) - jika ada
if [ "$UDP_CUSTOM_EXISTS" = true ]; then
    iptables -t nat -A PREROUTING -i "$iface" -p udp --dport 1:65535 -j DNAT --to-destination :36712
fi

# Allow INPUT untuk port ZiVPN
iptables -I INPUT -p udp --dport ${ZIVPN_UDP_PORT} -j ACCEPT 2>/dev/null
iptables -I INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null

print_success "iptables rules configured with priority:"
print_info "  Priority 1: DNS (port 53) → 5300"
print_info "  Priority 2: ZiVPN (6000-19999) → ${ZIVPN_UDP_PORT}"
if [ "$UDP_CUSTOM_EXISTS" = true ]; then
    print_info "  Priority 3: UDP-Custom (1-65535) → 36712 (catch-all)"
fi

# Firewall rules (ufw)
if command -v ufw &>/dev/null; then
    ufw allow ${ZIVPN_UDP_PORT}/udp &>/dev/null
    ufw allow 6000:19999/udp &>/dev/null
    print_success "UFW rules added"
fi

# Save iptables
apt-get install -y iptables-persistent &>/dev/null
netfilter-persistent save &>/dev/null 2>&1 || true
iptables-save > /etc/iptables/rules.v4 2>/dev/null

# ==================== VERIFIKASI RULES ====================
print_section_header "📋 Verification"
echo ""
print_info "iptables NAT rules (priority order):"
iptables -t nat -L PREROUTING -n -v --line-numbers 2>/dev/null | head -10
echo ""

# Cek status service
if systemctl is-active --quiet zivpn; then
    print_success "ZiVPN Service: RUNNING"
else
    print_error "ZiVPN Service: NOT RUNNING"
fi

if [ "$UDP_CUSTOM_EXISTS" = true ]; then
    if systemctl is-active --quiet udp-custom; then
        print_success "UDP-Custom Service: RUNNING"
    else
        print_warning "UDP-Custom Service: NOT RUNNING"
    fi
fi

# ==================== FINISH ====================
print_section_header "✅ ZiVPN Core Installed Successfully"

echo ""
print_info "🔧 Commands:"
print_info "  systemctl start zivpn   - Start ZiVPN"
print_info "  systemctl stop zivpn    - Stop ZiVPN"
print_info "  systemctl status zivpn  - Check status"
print_info "  journalctl -u zivpn -f  - View logs"
print_info "  cat /etc/zivpn/config.json - Lihat config"
echo ""

print_success "Installation complete! Client can now connect."