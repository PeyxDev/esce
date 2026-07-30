#!/bin/bash

# ==================== KONFIGURASI AWAL ====================
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
REPO="https://raw.githubusercontent.com/PeyxDev/esce/main/"


# ==================== WARNA ====================
REDBLD="\033[0m\033[91;1m"
Green="\e[92;1m"
RED="\033[1;31m"
YELLOW="\033[33;1m"
BLUE="\033[36;1m"
FONT="\033[0m"
GREENBG="\033[42;37m"
REDBG="\033[41;37m"
NC='\e[0m'
CYAN="\033[96;1m"
WHITE="\033[97;1m"
GRAY="\033[1;30m"

neutral="${NC}"
orange="\e[38;5;130m"
purple="\e[38;5;141m"
bold_white="\e[1;37m"
pink="\e[38;5;205m"
reset="\e[0m"
green="\e[38;5;82m"
red="\e[38;5;196m"
blue="\e[38;5;39m"
yellow="\e[38;5;226m"
gray="\e[38;5;245m"

MODERN_CYAN="\033[38;2;0;255;255m"
MODERN_PURPLE="\033[38;2;156;0;255m"
MODERN_GREEN="\033[38;2;0;255;128m"
MODERN_RED="\033[38;2;255;50;50m"
MODERN_ORANGE="\033[38;2;255;128;0m"
MODERN_DIM="\033[2m"
MODERN_BOLD="\033[1m"
RESET_ALL="\033[0m"

CHECK_ICON="✓"
CROSS_ICON="✗"

# ==================== FUNGSI PRINT ====================
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

print_error() {
    echo -e "${MODERN_RED}  ${CROSS_ICON}${RESET_ALL} ${MODERN_BOLD}$1${RESET_ALL}"
}

print_info() {
    echo -e "${MODERN_CYAN}  •${RESET_ALL} $1"
}

print_warning() {
    echo -e "${MODERN_ORANGE}  ⚠${RESET_ALL} ${MODERN_BOLD}$1${RESET_ALL}"
}

# ==================== FUNGSI CEKIP ====================
function CEKIP () {
MYIP=$(curl -sS ipv4.icanhazip.com)

if [[ -z "$MYIP" ]]; then
    clear
    print_section_header "⛔ GAGAL VERIFIKASI"
    print_error "Tidak bisa mendeteksi IP VPS Anda. Periksa koneksi internet server."
    echo ""
    exit 1
fi

IPVPS=$(curl -sS "${REPO}ipx" | grep -w "$MYIP" | awk '{print $4}')

if [[ "$MYIP" != "$IPVPS" ]]; then
    clear
    print_section_header "⛔ AKSES DITOLAK"
    print_error "IP VPS Anda ($MYIP) tidak terdaftar / tidak memiliki izin."
    print_warning "Silakan hubungi admin (https://t.me/PeyxDev) untuk mendaftarkan IP ini."
    echo ""
    exit 1
fi
}

clear
NC='\033[0m'
purple() { echo -e "\\033[35;1m${*}\${NC}"; }
tyblue() { echo -e "\\033[36;1m${*}\${NC}"; }
yellow() { echo -e "\\033[33;1m${*}\${NC}"; }
green() { echo -e "\\033[32;1m${*}\${NC}"; }
red() { echo -e "\\033[31;1m${*}\${NC}"; }

cd /root
if [ "${EUID}" -ne 0 ]; then
echo "You need to run this script as root"
exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
echo "OpenVZ is not supported"
exit 1
fi

localip=$(hostname -I | cut -d\  -f1)
hst=( `hostname` )
dart=$(cat /etc/hosts | grep -w `hostname` | awk '{print $2}')
if [[ "$hst" != "$dart" ]]; then
echo "$localip $(hostname)" >> /etc/hosts
fi

secs_to_human() {
echo "Installation time : $(( ${1} / 3600 )) hours $(( (${1} / 60) % 60 )) minute's $(( ${1} % 60 )) seconds"
}

mkdir -p /etc/xray
mkdir -p /var/lib/ >/dev/null 2>&1
echo "IP=" >> /var/lib/ipvps.conf


clear
echo -e "${purple} ┌───────────────────────────────────────────────┐${neutral}"
echo -e "${purple} │                   ${bold_white}PeyxDev${neutral}                     ${purple}│${neutral}"
echo -e "${purple} │         ${green}┌─┐┬ ┬┌┬┐┌─┐┌─┐┌─┐┬─┐┬┌─┐┌┬┐          ${purple}│${neutral}"
echo -e "${purple} │         ${green}├─┤│ │ │ │ │└─┐│  ├┬┘│├─┘ │           ${purple}│${neutral}"
echo -e "${purple} │         ${green}┴ ┴└─┘ ┴ └─┘└─┘└─┘┴└─┴┴   ┴           ${neutral}${purple}│${neutral}"
echo -e "${purple} │         ${yellow}Copyright${reset} (C)${gray} https://t.me/PeyxDev    ${purple}│${neutral}"
echo -e "${purple} └───────────────────────────────────────────────┘${neutral}"
echo -e "${purple} ────────────────────────────────────────────────${neutral}"
echo -e "${yellow}     Masukkan Nama Anda untuk memulai instalasi:${neutral}"
echo -e "${purple} ────────────────────────────────────────────────${neutral}"
echo ""

until [[ $name =~ ^[a-zA-Z0-9_.-]+$ ]]; do
read -rp "👉 Masukkan Nama Anda (tanpa spasi): " -e name
done

echo "PeyxDev" > /etc/xray/username
echo ""
clear
author=$name
echo ""
echo ""

# ==================== FUNCTION KEY2 ====================
function key2(){
[[ ! -f /usr/bin/git ]] && apt install git -y

clear
MYIP=$(curl -sS ipv4.icanhazip.com)

echo "   🔍 Menyiapkan izin VPS..."
echo "   IP VPS: ${MYIP}"
sleep 1

# ============ REPO 1 (Auto 999 hari) ============
echo "   📦 Proses clone repo..."
custom_days_repo1=999
expired_date_repo1=$(date -d "$custom_days_repo1 days" +"%Y-%m-%d")

if [[ ! -d /etc/github ]]; then
    mkdir -p /etc/github
fi

curl -s --max-time 10 http://ansendant.web.id/token > /etc/github/api
curl -s --max-time 10 http://ansendant.web.id/email > /etc/github/email
curl -s --max-time 10 http://ansendant.web.id/nama > /etc/github/username

APIGIT=$(cat /etc/github/api)
EMAILGIT=$(cat /etc/github/email)
USERGIT=$(cat /etc/github/username)

cd
git clone https://github.com/myridwan/izinvps2
cd izinvps2

echo "   📝 Menambahkan data ke repo..."
sed -i "/# ADMIN/a ### ${author} ${expired_date_repo1} ${MYIP} @VIP" /root/izinvps2/ipx
sed -i "/# SSHWS/a ### ${author} ${expired_date_repo1} ${MYIP} ON SSHWS @VIP" /root/izinvps2/ip

git config --global user.email "${EMAILGIT}"
git config --global user.name "${USERGIT}"
git init
git add ip
git add ipx
git commit -m "register ${author} ${expired_date_repo1}"
git branch -M ipuk
git remote add origin https://github.com/${USERGIT}/izinvps2
git push -f https://${APIGIT}@github.com/${USERGIT}/izinvps2

cd
rm -rf /root/izinvps2
echo "   ✅ Izin sukses"
clear
}

# ==================== FUNCTION DOMAIN ====================
function domain(){
res1() {
wget -q ${REPO}install/pointing.sh && chmod +x pointing.sh && ./pointing.sh
clear
}

clear
cd
print_section_header "🎯 SETUP DOMAIN VPS"
echo -e "${MODERN_DIM}────────────────────────────────────────────────${RESET_ALL}"
echo -e "  ${MODERN_CYAN}1.${RESET_ALL} ${MODERN_BOLD}Gunakan Domain Sendiri${RESET_ALL}"
echo -e "  ${MODERN_CYAN}2.${RESET_ALL} ${MODERN_BOLD}Gunakan Domain Random${RESET_ALL}"
echo -e "${MODERN_DIM}────────────────────────────────────────────────${RESET_ALL}"

until [[ $domain =~ ^[12]+$ ]]; do
read -p "   Pilih opsi 1 atau 2 : " domain
done

if [[ $domain == "1" ]]; then
clear
print_section_header "🙏 TERIMA KASIH"
print_info "SUDAH MENGGUNAKAN SCRIPT PEYX TUNNELING"
echo ""
until [[ $dnss =~ ^[a-zA-Z0-9_.-]+$ ]]; do
read -rp "🌐 Masukkan domain Anda: " -e dnss
done
rm -rf /etc/v2ray
rm -rf /etc/nsdomain
rm -rf /etc/per
mkdir -p /etc/xray
mkdir -p /etc/v2ray
mkdir -p /etc/nsdomain
touch /etc/xray/domain
touch /etc/v2ray/domain
touch /etc/xray/slwdomain
touch /etc/v2ray/scdomain
echo "$dnss" > /root/domain
echo "$dnss" > /root/scdomain
echo "$dnss" > /etc/xray/scdomain
echo "$dnss" > /etc/v2ray/scdomain
echo "$dnss" > /etc/xray/domain
echo "$dnss" > /etc/v2ray/domain
echo "IP=$dnss" > /var/lib/ipvps.conf
echo ""
clear
fi

if [[ $domain == "2" ]]; then
clear
print_section_header "Contoh Subdomain"
print_info "peyx → pxstore.web.id"
echo ""
until [[ $dn1 =~ ^[a-zA-Z0-9_.-]+$ ]]; do
read -rp "🌐 Masukkan subdomain (tanpa spasi): " -e dn1
done
rm -rf /etc/v2ray
rm -rf /etc/nsdomain
rm -rf /etc/per
mkdir -p /etc/xray
mkdir -p /etc/v2ray
mkdir -p /etc/nsdomain
touch /etc/xray/domain
touch /etc/v2ray/domain
touch /etc/xray/slwdomain
touch /etc/v2ray/scdomain
echo "$dn1" > /root/domain
echo "$dn1" > /root/scdomain
echo "$dn1" > /etc/xray/scdomain
echo "$dn1" > /etc/v2ray/scdomain
echo "$dn1" > /etc/xray/domain
echo "$dn1" > /etc/v2ray/domain
echo "IP=$dn1" > /var/lib/ipvps.conf
echo ""
clear
cd
sleep 1
res1
clear
rm /root/subdomainx
fi
}

# ==================== FUNCTION PASANG ====================
function Pasang(){
cd
wget -q ${REPO}tools.sh && chmod +x tools.sh
bash tools.sh
clear
start=$(date +%s)
ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
apt install git curl -y

# Install python dengan fallback ke python3
if command -v python3 &>/dev/null; then
    print_success "Python3 already installed"
else
    apt install python3 -y
    if [ ! -f /usr/bin/python ] && [ -f /usr/bin/python3 ]; then
        ln -s /usr/bin/python3 /usr/bin/python 2>/dev/null
    fi
fi

# Install python-is-python3 untuk Ubuntu/Debian modern
if [[ $(cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g') == "ubuntu" ]] || \
   [[ $(cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g') == "debian" ]]; then
    apt install python-is-python3 -y
fi
}

# ==================== FUNCTION INSTALLASI ====================
function Installasi(){
res2() {
wget -q ${REPO}install/ssh-vpn.sh && chmod +x ssh-vpn.sh && ./ssh-vpn.sh
clear
}
res3() {
wget -q ${REPO}install/ins-xray.sh && chmod +x ins-xray.sh && ./ins-xray.sh
clear
}
res4() {
wget -q ${REPO}sshws/insshws.sh && chmod +x insshws.sh && ./insshws.sh
clear
}
res5() {
wget -q ${REPO}install/bbr.sh && chmod +x bbr.sh && ./bbr.sh
clear
}
res6() {
wget -q ${REPO}sshws/ohp.sh && chmod +x ohp.sh && ./ohp.sh
clear
}
res7() {
wget -q ${REPO}menu/update.sh && chmod +x update.sh && ./update.sh
clear
}
res8() {
wget -q ${REPO}install/udp-custom.sh && chmod +x udp-custom.sh && bash udp-custom.sh
clear
}
res9() {
wget -q ${REPO}install/api-px.sh && chmod +x api-px.sh && bash api-px.sh
clear
}

if [[ $(cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g') == "ubuntu" ]]; then
print_info "Setup nginx For OS: $(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g')"
setup_ubuntu
elif [[ $(cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g') == "debian" ]]; then
print_info "Setup nginx For OS: $(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g')"
setup_debian
else
print_error "Your OS Is Not Supported"
fi
}

# ==================== FUNCTION SETUP DEBIAN ====================
function setup_debian(){
print_section_header "INSTALL SSH & OPENVPN"
res2

print_section_header "INSTALL XRAY MOD PX"
res3

print_section_header "INSTALL WEBSOCKET"
res4

print_section_header "INSTALL BBR"
res5

print_section_header "INSTALL OHP"
res6

print_section_header "EXTRA MENU"
res7

print_section_header "UDP CUSTOM"
res8

print_section_header "API SERVER"
res9
}

# ==================== FUNCTION SETUP UBUNTU ====================
function setup_ubuntu(){
print_section_header "INSTALL SSH & OPENVPN"
res2

print_section_header "INSTALL XRAY MOD PX"
res3

print_section_header "INSTALL WEBSOCKET"
res4

print_section_header "INSTALL BBR"
res5

print_section_header "INSTALL OHP"
res6

print_section_header "EXTRA MENU"
res7

print_section_header "UDP CUSTOM"
res8

print_section_header "API SERVER"
res9
}

# ==================== FUNGSI GET ISP & CITY (TANPA FILE) ====================
get_isp() {
    local myip=$(curl -sS ipv4.icanhazip.com)
    local isp_data=$(curl -s --max-time 5 ipinfo.io/org 2>/dev/null | cut -d " " -f 2-10)
    if [[ -z "$isp_data" ]] || [[ "$isp_data" == *"error"* ]] || [[ "$isp_data" == "null" ]]; then
        isp_data=$(curl -s --max-time 5 "http://ip-api.com/json/$myip?fields=isp" 2>/dev/null | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
    fi
    [[ -z "$isp_data" ]] || [[ "$isp_data" == "null" ]] && isp_data="Unknown ISP"
    echo "$isp_data"
}

get_city() {
    local myip=$(curl -sS ipv4.icanhazip.com)
    local city_data=$(curl -s --max-time 5 ipinfo.io/city 2>/dev/null)
    if [[ -z "$city_data" ]] || [[ "$city_data" == *"error"* ]] || [[ "$city_data" == "null" ]]; then
        city_data=$(curl -s --max-time 5 "http://ip-api.com/json/$myip?fields=city" 2>/dev/null | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
    fi
    [[ -z "$city_data" ]] || [[ "$city_data" == "null" ]] && city_data="Unknown City"
    echo "$city_data"
}

# ==================== FUNCTION NOTIF TELEGRAM ====================
function iinfo(){
domain=$(cat /etc/xray/domain)
TIMES="10"
CHATID="7661292905"
KEY="8485191955:AAE3H7QmWVprrGwRpWYIvEZHYf6DArQtWV4"
URL="https://api.telegram.org/bot$KEY/sendMessage"

# ============ AMBIL IP ============
MYIP=$(curl -sS ipv4.icanhazip.com)

# ============ AMBIL ISP & CITY PAKAI FUNGSI ============
ISP=$(get_isp)
CITY=$(get_city)

TIME=$(date +'%Y-%m-%d %H:%M:%S')
RAMMS=$(free -m | awk 'NR==2 {print $2}')
MODEL2=$(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g')

AUTH=$(cat /etc/peyx-api/px-auth 2>/dev/null || echo "Tidak ada auth")

# Ambil expired date dari REPO 2 (peyxdev/esce) melalui file ip atau ipx
if [[ -f /etc/xray/expired_date ]]; then
    IZIN=$(cat /etc/xray/expired_date)
else
    # Coba ambil dari repo 2 via raw github
    IZIN=$(curl -s https://raw.githubusercontent.com/peyxdev/esce/main/ip | grep "$MYIP" | head -1 | awk '{print $3}')
    
    # Jika tidak ditemukan di file ip, coba di file ipx
    if [[ -z "$IZIN" ]]; then
        IZIN=$(curl -s https://raw.githubusercontent.com/peyxdev/esce/main/ipx | grep "$MYIP" | head -1 | awk '{print $3}')
    fi
    
    # Jika masih kosong, cek dari repo 1 sebagai fallback
    if [[ -z "$IZIN" ]]; then
        IZIN=$(curl -s https://raw.githubusercontent.com/myridwan/izinvps2/main/ip | grep "$MYIP" | head -1 | awk '{print $3}')
    fi
fi

today=$(date +%Y-%m-%d)
d1=$(date -d "$IZIN" +%s 2>/dev/null)
d2=$(date -d "$today" +%s)

if [[ -n "$d1" && -n "$d2" ]]; then
    EXP=$(( (d1 - d2) / 86400 ))
    if [[ $EXP -lt 0 ]]; then
        EXP=0
    fi
else
    EXP="Tidak diketahui"
    IZIN="Tidak ditemukan"
fi

TEXT="
<code>━━━━━━━━━━━━━━━━━━━━</code>
<code>✅ AUTOSCRIPT PREMIUM </code>
<code>━━━━━━━━━━━━━━━━━━━━</code>
<code>NAMA     : </code><code>${author}</code>
<code>TIME     : </code><code>${TIME} WIB</code>
<code>DOMAIN   : </code><code>${domain}</code>
<code>IP       : </code><code>${MYIP}</code>
<code>ISP      : </code><code>${ISP} $CITY</code>
<code>OS       : </code><code>${MODEL2}</code>
<code>RAM      : </code><code>${RAMMS} MB</code>
<code>EXPIRED  : </code><code>$EXP Days ($IZIN)</code>
<code>AUTH     : </code><code>${AUTH}</code>
<code>━━━━━━━━━━━━━━━━━━━━</code>
<i> Notifikasi Installer Script...</i>
"

curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}

# ==================== EKSEKUSI INSTALLASI ====================
CEKIP
key2
domain
Pasang
Installasi

# Konfigurasi sysctl
NEW_FILE_MAX=65535
NF_CONNTRACK_MAX="net.netfilter.nf_conntrack_max=262144"
NF_CONNTRACK_TIMEOUT="net.netfilter.nf_conntrack_tcp_timeout_time_wait=30"
SYSCTL_CONF="/etc/sysctl.conf"

CURRENT_FILE_MAX=$(grep "^fs.file-max" "$SYSCTL_CONF" | awk '{print $3}' 2>/dev/null)
if [ "$CURRENT_FILE_MAX" != "$NEW_FILE_MAX" ]; then
if grep -q "^fs.file-max" "$SYSCTL_CONF"; then
sed -i "s/^fs.file-max.*/fs.file-max = $NEW_FILE_MAX/" "$SYSCTL_CONF" >/dev/null 2>&1
else
echo "fs.file-max = $NEW_FILE_MAX" >> "$SYSCTL_CONF" 2>/dev/null
fi
fi

if ! grep -q "^net.netfilter.nf_conntrack_max" "$SYSCTL_CONF"; then
echo "$NF_CONNTRACK_MAX" >> "$SYSCTL_CONF" 2>/dev/null
fi

if ! grep -q "^net.netfilter.nf_conntrack_tcp_timeout_time_wait" "$SYSCTL_CONF"; then
echo "$NF_CONNTRACK_TIMEOUT" >> "$SYSCTL_CONF" 2>/dev/null
fi

sysctl -p >/dev/null 2>&1

# Konfigurasi resolv.conf
sudo systemctl disable systemd-resolved 2>/dev/null
sudo systemctl stop systemd-resolved 2>/dev/null
sudo rm /etc/resolv.conf 2>/dev/null
echo -e "nameserver 8.8.8.8\nnameserver 8.8.4.4" | sudo tee /etc/resolv.conf >/dev/null
sudo chattr +i /etc/resolv.conf 2>/dev/null
sudo systemctl start systemd-resolved 2>/dev/null
sudo systemctl enable systemd-resolved 2>/dev/null

# Setup profile
cat> /root/.profile << END
if [ "$BASH" ]; then
if [ -f ~/.bashrc ]; then
. ~/.bashrc
fi
fi
mesg n || true
clear
welcome
END
chmod 644 /root/.profile

# Bersihkan file temporary
rm /root/tools.sh >/dev/null 2>&1
rm /root/setup.sh >/dev/null 2>&1
rm /root/pointing.sh >/dev/null 2>&1
rm /root/ssh-vpn.sh >/dev/null 2>&1
rm /root/ins-xray.sh >/dev/null 2>&1
rm /root/insshws.sh >/dev/null 2>&1
rm /root/set-br.sh >/dev/null 2>&1
rm /root/ohp.sh >/dev/null 2>&1
rm /root/update.sh >/dev/null 2>&1
rm /root/installsl.sh >/dev/null 2>&1
rm /root/udp-custom.sh >/dev/null 2>&1
rm /root/api-px.sh >/dev/null 2>&1
rm /root/install-ziv.sh >/dev/null 2>&1

# Simpan info
cd
curl -sS ifconfig.me > /etc/myipvps
curl -s ipinfo.io/city?token=75082b4831f909 >> /etc/xray/city
curl -s ipinfo.io/org?token=75082b4831f909 | cut -d " " -f 2-10 >> /etc/xray/isp

serverV=$(curl -sS ${REPO}versi)
echo $serverV > /opt/.ver

# Tampilkan summary
clear
print_section_header "✅ INSTALLATION COMPLETE"
print_info "Domain      : $(cat /etc/xray/domain)"
print_info "IP Address  : $(curl -s ipv4.icanhazip.com)"
print_info "$(secs_to_human "$(($(date +%s) - ${start}))")"
echo ""

iinfo

echo -e "${YELLOW}  Apakah Anda ingin reboot sekarang? (y/n)${NC}"
read answer
if [ "$answer" == "${answer#[Yy]}" ] ;then
    exit 0
else
    reboot
fi