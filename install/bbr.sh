#!/bin/bash

# =============================================================
# Optimasi Speed VPS By PX STORE (PeyxDev)
# Fix: BBR detection bug + duplicate fs.file-max + disable IPv6
# =============================================================

# Wajib root
if [ "$(id -u)" != "0" ]; then
	echo "Script ini harus dijalankan sebagai root."
	exit 1
fi

SYSCTL_CONF="/etc/sysctl.conf"

Add_To_New_Line(){
	if [ "$(tail -n1 "$1" | wc -l)" == "0" ]; then
		echo "" >> "$1"
	fi
	echo "$2" >> "$1"
}

Check_And_Add_Line(){
	if [ -z "$(grep -F "$2" "$1" 2>/dev/null)" ]; then
		Add_To_New_Line "$1" "$2"
	fi
}

Install_BBR(){
echo "#############################################"
echo "Install TCP_BBR BY PEYX OFFICIALL..."

# Cek berdasarkan congestion control yang AKTIF, bukan cuma modul yang ter-load
if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]; then
	echo "TCP_BBR sudah aktif."
	echo "#############################################"
	return 1
fi

echo "Mulai menginstall TCP_BBR..."
modprobe tcp_bbr
Add_To_New_Line "/etc/modules-load.d/modules.conf" "tcp_bbr"

Check_And_Add_Line "$SYSCTL_CONF" "net.core.default_qdisc = fq"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_congestion_control = bbr"

sysctl -p >/dev/null 2>&1

if [ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ] && [ -n "$(lsmod | grep tcp_bbr)" ]; then
	echo "TCP_BBR Install Success."
else
	echo "Gagal menginstall TCP_BBR. Cek manual dengan: sysctl net.ipv4.tcp_congestion_control"
fi
echo "#############################################"
}

Optimize_Parameters(){
echo "#############################################"
echo "Optimasi Parameters..."

# --- Limits ---
Check_And_Add_Line "/etc/security/limits.conf" "* soft nofile 51200"
Check_And_Add_Line "/etc/security/limits.conf" "* hard nofile 51200"
Check_And_Add_Line "/etc/security/limits.conf" "root soft nofile 51200"
Check_And_Add_Line "/etc/security/limits.conf" "root hard nofile 51200"

# --- Bersihkan dulu baris fs.file-max lama biar tidak dobel/konflik ---
sed -i '/^fs.file-max/d' "$SYSCTL_CONF"
Add_To_New_Line "$SYSCTL_CONF" "fs.file-max = 65535"

# --- Disable IPv6 (hindari tunnel salah pilih jalur IPv6 yang kadang tidak stabil) ---
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv6.conf.all.disable_ipv6 = 1"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv6.conf.default.disable_ipv6 = 1"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv6.conf.lo.disable_ipv6 = 1"

# --- Core network buffer & queue ---
Check_And_Add_Line "$SYSCTL_CONF" "net.core.rmem_max = 67108864"
Check_And_Add_Line "$SYSCTL_CONF" "net.core.wmem_max = 67108864"
Check_And_Add_Line "$SYSCTL_CONF" "net.core.netdev_max_backlog = 250000"
Check_And_Add_Line "$SYSCTL_CONF" "net.core.somaxconn = 4096"

# --- TCP tuning umum ---
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_syncookies = 1"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_tw_reuse = 1"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_fin_timeout = 30"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_keepalive_time = 1200"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.ip_local_port_range = 10000 65000"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_max_syn_backlog = 8192"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_max_tw_buckets = 5000"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_fastopen = 3"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_mem = 25600 51200 102400"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_rmem = 4096 87380 67108864"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_wmem = 4096 65536 67108864"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_mtu_probing = 1"

# --- Tambahan khusus untuk koneksi tunneling (idle-resume, VPN-style traffic) ---
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_slow_start_after_idle = 0"
Check_And_Add_Line "$SYSCTL_CONF" "net.ipv4.tcp_notsent_lowat = 16384"

# --- Conntrack (biar tidak drop paket saat banyak user tunneling bersamaan) ---
Check_And_Add_Line "$SYSCTL_CONF" "net.netfilter.nf_conntrack_max = 262144"
Check_And_Add_Line "$SYSCTL_CONF" "net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30"

sysctl -p >/dev/null 2>&1

echo "Optimasi Parameters Selesai."
echo "#############################################"
}

# =============================================================
# Eksekusi
# =============================================================
Install_BBR
Optimize_Parameters

echo ""
echo "=== Verifikasi Hasil ==="
echo "Congestion Control : $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "Default Qdisc       : $(sysctl -n net.core.default_qdisc)"
echo "IPv6 Disabled       : $(sysctl -n net.ipv6.conf.all.disable_ipv6)"
echo "File Max            : $(sysctl -n fs.file-max)"
echo ""
echo "Selesai. Semua perubahan sysctl sudah langsung diterapkan (tanpa reboot)."
echo "Jika pakai service tunneling (xray/nginx/haproxy dll), restart service-nya agar koneksi baru memakai setting terbaru, contoh:"
echo "  systemctl restart xray"
echo "  systemctl restart nginx"