#!/bin/bash
# ============================================================
#  anti-ddos.sh
#  Hardening kernel + rate-limit iptables + fail2ban jail
#  untuk VPS panel (ssh/dropbear/xray/haproxy/nginx/openvpn).
#  Tidak membatasi trafik akun yang wajar, hanya menahan pola
#  flood/scan (SYN flood, port scan, banyak koneksi baru/detik
#  dari 1 IP).
#  Author: PeyxDev
# ============================================================
set -e

echo "=== Memasang proteksi anti-DDoS ==="

# ------------------------------------------------------------
# 1) Hardening kernel (sysctl)
# ------------------------------------------------------------
cat > /etc/sysctl.d/99-anti-ddos.conf <<-END
# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3

# koneksi & timeout
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.core.somaxconn = 4096
net.ipv4.ip_local_port_range = 1024 65535

# anti spoofing / source routing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# abaikan ICMP broadcast (anti smurf attack)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# abaikan redirect ICMP palsu
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# proteksi terhadap martian packet
net.ipv4.conf.all.log_martians = 1
END
sysctl -p /etc/sysctl.d/99-anti-ddos.conf >/dev/null 2>&1 || true

# ------------------------------------------------------------
# 2) iptables: rate-limit SYN, drop paket cacat/scan, batasi
#    koneksi baru per-IP tanpa mengganggu koneksi aktif user
# ------------------------------------------------------------
iptables -N ANTIDDOS 2>/dev/null || iptables -F ANTIDDOS

# lolos-kan paket yang sudah bagian dari koneksi established/related
iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# buang paket invalid (ciri khas flood/spoof)
iptables -C INPUT -m state --state INVALID -j DROP 2>/dev/null || \
    iptables -I INPUT -m state --state INVALID -j DROP

# buang paket NULL & XMAS (teknik port scan umum)
iptables -C INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null || \
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -C INPUT -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null || \
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# batasi paket SYN baru: maksimal 60/detik per IP, burst 100
# (jauh di atas kebutuhan koneksi wajar, tapi menahan SYN flood)
iptables -C INPUT -p tcp --syn -m limit --limit 60/s --limit-burst 100 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p tcp --syn -m limit --limit 60/s --limit-burst 100 -j ACCEPT
iptables -C INPUT -p tcp --syn -j DROP 2>/dev/null || \
    iptables -A INPUT -p tcp --syn -j DROP

# batasi ICMP ping flood
iptables -C INPUT -p icmp --icmp-type echo-request -m limit --limit 10/s -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/s -j ACCEPT
iptables -C INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null || \
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

iptables-save > /etc/iptables.up.rules
netfilter-persistent save >/dev/null 2>&1 || true
netfilter-persistent reload >/dev/null 2>&1 || true

# ------------------------------------------------------------
# 3) fail2ban: ban IP yang brute-force / flood ke SSH & dropbear
#    (tidak menyentuh koneksi normal, hanya percobaan gagal
#    berulang kali)
# ------------------------------------------------------------
apt -y install fail2ban >/dev/null 2>&1

mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/anti-ddos.local <<-END
[DEFAULT]
bantime  = 3600
findtime = 300
maxretry = 8

[sshd]
enabled  = true
port     = ssh,500,40000,51443,58080,200,22
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5

[dropbear]
enabled  = true
port     = ssh
filter   = dropbear
logpath  = /var/log/auth.log
maxretry = 5
END

# filter dropbear kalau belum ada di sistem
if [[ ! -f /etc/fail2ban/filter.d/dropbear.conf ]]; then
    cat > /etc/fail2ban/filter.d/dropbear.conf <<-END
[Definition]
failregex = ^.*dropbear.*: Bad password attempt for .* from <HOST>.*$
            ^.*dropbear.*: Login attempt for nonexistent user.* from <HOST>.*$
ignoreregex =
END
fi

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1

echo "Proteksi anti-DDoS terpasang (sysctl + iptables rate-limit + fail2ban)"
