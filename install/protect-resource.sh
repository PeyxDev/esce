#!/bin/bash
# ============================================================
#  protect-resource.sh
#  Script keamanan & stabilitas VPS panel, satu file untuk:
#   1) Watchdog CPU & RAM         (jalan tiap menit via cron)
#   2) Anti-DDoS                  (sysctl + iptables + fail2ban)
#   3) Anti-Virus/Malware         (ClamAV + rkhunter, scan harian)
#
#  Pemakaian:
#    ./protect-resource.sh          -> setup sekali (kalau belum)
#                                       lalu jalankan watchdog
#    ./protect-resource.sh install  -> paksa jalankan ulang setup
#    ./protect-resource.sh watch    -> hanya jalankan watchdog saja
#
#  Dipasang otomatis oleh ssh-vpn.sh.
#  Author: PeyxDev
# ============================================================
echo "✨ FILE ENC BY PeyxDev"

# ------------------------------------------------------------
# Warna, konsisten dengan script lain (ins-xray.sh, dst)
# ------------------------------------------------------------
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'

info() { echo -e "[ ${GREEN}INFO${NC} ] $1"; }
ok()   { echo -e "[ ${GREEN}OK${NC} ] $1"; }
warn() { echo -e "[ ${RED}WARN${NC} ] $1"; }

LOG="/var/log/protect-resource.log"
MARKER="/etc/.protect-resource-installed"

CPU_LIMIT=90      # persen, ambang batas CPU
RAM_LIMIT=90      # persen, ambang batas RAM
SWAP_LIMIT=85     # persen, ambang batas SWAP

# service inti panel -> tidak pernah di-kill, direstart kalau mati
CORE_SERVICES=(xray haproxy nginx dropbear openvpn squid squid3 badvpn1 badvpn2 badvpn3 runn vnstat fail2ban cron rsyslog netfilter-persistent)

# pola proses/sesi yang aman (termasuk koneksi akun pelanggan) -> tidak boleh disentuh
SAFE_PATTERNS=(
    "xray" "haproxy" "nginx" "dropbear" "openvpn" "squid"
    "badvpn" "ws" "kyt" "sshd" "ssh" "php-fpm" "screen"
    "systemd" "init" "cron" "rsyslog" "vnstat" "fail2ban"
    "netfilter" "bash" "sh" "dash" "login" "getty" "agetty"
    "dbus" "networkd" "resolved" "journald" "udevd" "lolcat"
    "ruby" "gem" "clamd" "freshclam" "rkhunter"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

# jalankan apt install dengan batas waktu supaya script TIDAK PERNAH
# menggantung tanpa batas (mis. saat postinst clamav mengunduh
# database virus di jaringan lambat)
apt_install_timeout() {
    local seconds="$1"; shift
    timeout "$seconds" apt-get -y install "$@" 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    if [[ $rc -ne 0 ]]; then
        warn "Instalasi paket ($*) gagal atau melebihi batas waktu (${seconds}s), dilewati -> lihat $LOG"
        dpkg --configure -a 2>&1 | tee -a "$LOG" >/dev/null || true
        return 1
    fi
    return 0
}

# ============================================================
#  BAGIAN 1: WATCHDOG CPU & RAM
# ============================================================

get_cpu_usage() {
    # top -bn1 (1 snapshot) sering salah baca idle-nya, terutama di
    # VPS virtualized -> bisa nunjuk 100% padahal sebenarnya idle.
    # Pakai /proc/stat dengan 2 sampel berjeda supaya deltanya akurat.
    local c u1 n1 s1 i1 io1 irq1 si1 st1
    local u2 n2 s2 i2 io2 irq2 si2 st2
    read -r c u1 n1 s1 i1 io1 irq1 si1 st1 _ < /proc/stat
    sleep 1
    read -r c u2 n2 s2 i2 io2 irq2 si2 st2 _ < /proc/stat

    local idle1=$((i1 + io1))
    local idle2=$((i2 + io2))
    local total1=$((u1 + n1 + s1 + i1 + io1 + irq1 + si1 + st1))
    local total2=$((u2 + n2 + s2 + i2 + io2 + irq2 + si2 + st2))

    local dtotal=$((total2 - total1))
    local didle=$((idle2 - idle1))

    if [[ "$dtotal" -le 0 ]]; then
        echo 0
    else
        echo $(( (100 * (dtotal - didle)) / dtotal ))
    fi
}

get_ram_usage() {
    free | awk '/Mem:/ {printf "%d", ($3/$2)*100}'
}

get_swap_usage() {
    free | awk '/Swap:/ {if ($2==0) print 0; else printf "%d", ($3/$2)*100}'
}

# turunkan prioritas OOM-kill service inti agar tidak dimatikan kernel duluan
protect_core_services() {
    for svc in "${CORE_SERVICES[@]}"; do
        pid=$(systemctl show -p MainPID --value "$svc" 2>/dev/null)
        if [[ -n "$pid" && "$pid" != "0" && -e "/proc/$pid/oom_score_adj" ]]; then
            echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null
        fi
    done
}

clear_cache() {
    sync
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null
    log "RAM tinggi -> cache dibersihkan (sync + drop_caches)"
}

is_safe_process() {
    local comm="$1" cmdline="$2"
    for pat in "${SAFE_PATTERNS[@]}"; do
        [[ "$comm" == *"$pat"* || "$cmdline" == *"$pat"* ]] && return 0
    done
    return 1
}

# proses dianggap mencurigakan (boleh dihentikan) hanya jika:
# jalan dari lokasi tak lazim, binary sudah dihapus dari disk,
# atau namanya menyerupai malware/miner yang dikenal
is_suspicious_process() {
    local pid="$1" comm="$2"
    local exe_path
    exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null)

    [[ "$exe_path" == *"(deleted)"* ]] && return 0

    case "$exe_path" in
        /tmp/*|/var/tmp/*|/dev/shm/*|/run/*) return 0 ;;
    esac

    case "$comm" in
        *xmrig*|*kdevtmpfsi*|*kinsing*|*minerd*|*cryptonight*|*.sh4*|*.mips*|*ddg.*) return 0 ;;
    esac

    return 1
}

handle_high_usage() {
    local reason="$1"

    ps -eo pid,comm,%cpu,%mem --sort=-%mem | awk 'NR>1' | while read -r pid comm cpu mem; do
        [[ -z "$pid" || "$pid" == "$$" ]] && continue
        [[ -d "/proc/$pid" ]] || continue
        cmdline=$(tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline")

        is_safe_process "$comm" "$cmdline" && continue

        if is_suspicious_process "$pid" "$comm"; then
            kill -15 "$pid" 2>/dev/null
            sleep 2
            kill -9 "$pid" 2>/dev/null
            log "$reason -> PROSES MENCURIGAKAN dihentikan: PID=$pid CMD=$comm CPU=${cpu}% MEM=${mem}%"
        else
            log "$reason -> proses non-inti pemakaian tinggi (TIDAK dihentikan, bukan proses mencurigakan): PID=$pid CMD=$comm CPU=${cpu}% MEM=${mem}%"
        fi
    done
}

restart_if_dead() {
    for svc in "${CORE_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}.service"; then
            state=$(systemctl is-active "$svc" 2>/dev/null)
            if [[ "$state" != "active" ]]; then
                systemctl restart "$svc" >/dev/null 2>&1
                log "Service $svc tidak aktif -> direstart"
            fi
        fi
    done
}

run_watchdog() {
    protect_core_services

    cpu=$(get_cpu_usage)
    ram=$(get_ram_usage)
    swap=$(get_swap_usage)

    if [[ "$ram" -ge "$RAM_LIMIT" ]]; then
        clear_cache
        ram=$(get_ram_usage)
        [[ "$ram" -ge "$RAM_LIMIT" ]] && handle_high_usage "RAM masih tinggi (${ram}%)"
    fi

    [[ "$cpu" -ge "$CPU_LIMIT" ]] && handle_high_usage "CPU tinggi (${cpu}%)"
    [[ "$swap" -ge "$SWAP_LIMIT" ]] && log "SWAP tinggi (${swap}%)"

    restart_if_dead

    # ringkasan singkat -> supaya kalau dijalankan manual terlihat
    # jelas prosesnya, bukan diam total. Saat dipanggil dari cron
    # tiap menit, ini hanya masuk ke $LOG (lihat mode "watch" di bawah).
    log "Cek watchdog: CPU=${cpu}% RAM=${ram}% SWAP=${swap}% (batas ${CPU_LIMIT}%/${RAM_LIMIT}%/${SWAP_LIMIT}%)"
}

# ============================================================
#  BAGIAN 2: ANTI-DDOS (sysctl + iptables + fail2ban)
# ============================================================

setup_anti_ddos() {
    info "Memasang proteksi anti-DDoS (sysctl + iptables)"

    cat > /etc/sysctl.d/99-anti-ddos.conf <<-END
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.core.somaxconn = 4096
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
END
    sysctl -p /etc/sysctl.d/99-anti-ddos.conf 2>&1 | tee -a "$LOG"
    ok "Kernel hardening (sysctl) selesai"

    iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -C INPUT -m state --state INVALID -j DROP 2>/dev/null || \
        iptables -I INPUT -m state --state INVALID -j DROP
    iptables -C INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null || \
        iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    iptables -C INPUT -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null || \
        iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    iptables -C INPUT -p tcp --syn -m limit --limit 60/s --limit-burst 100 -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --syn -m limit --limit 60/s --limit-burst 100 -j ACCEPT
    iptables -C INPUT -p tcp --syn -j DROP 2>/dev/null || \
        iptables -A INPUT -p tcp --syn -j DROP
    iptables -C INPUT -p icmp --icmp-type echo-request -m limit --limit 10/s -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/s -j ACCEPT
    iptables -C INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null || \
        iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

    iptables-save > /etc/iptables.up.rules
    netfilter-persistent save 2>&1 | tee -a "$LOG"
    netfilter-persistent reload 2>&1 | tee -a "$LOG"
    ok "Rate-limit iptables (anti SYN/ICMP flood, anti port-scan) selesai"

    info "Memasang fail2ban (bisa beberapa detik)"
    if apt_install_timeout 120 fail2ban; then
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
        if [[ ! -f /etc/fail2ban/filter.d/dropbear.conf ]]; then
            cat > /etc/fail2ban/filter.d/dropbear.conf <<-END
[Definition]
failregex = ^.*dropbear.*: Bad password attempt for .* from <HOST>.*$
            ^.*dropbear.*: Login attempt for nonexistent user.* from <HOST>.*$
ignoreregex =
END
        fi
        systemctl enable fail2ban 2>&1 | tee -a "$LOG"
        systemctl restart fail2ban 2>&1 | tee -a "$LOG"
        ok "fail2ban aktif (jail sshd & dropbear)"
    fi

    log "Setup anti-DDoS selesai"
    ok "Proteksi anti-DDoS terpasang"
}

# ============================================================
#  BAGIAN 3: ANTI-VIRUS / ANTI-MALWARE (ClamAV + rkhunter)
# ============================================================

setup_anti_virus() {
    info "Memasang proteksi anti-virus / anti-malware"
    export DEBIAN_FRONTEND=noninteractive

    info "Instalasi ClamAV & rkhunter (bisa memakan waktu 2-5 menit, mohon tunggu)"
    if ! apt_install_timeout 600 clamav clamav-daemon rkhunter; then
        warn "Anti-virus dilewati karena instalasi paket gagal/timeout"
        return 1
    fi
    ok "Paket ClamAV & rkhunter terpasang"

    mkdir -p /var/log/clamav /var/log/rkhunter

    # jangan tunggu update database di sini (bisa lama & bikin
    # script terlihat "hang") -> jalankan sebagai service di
    # latar belakang, database akan lengkap dalam beberapa menit
    systemctl enable clamav-freshclam 2>&1 | tee -a "$LOG"
    systemctl restart clamav-freshclam 2>&1 | tee -a "$LOG"
    info "Update database ClamAV berjalan di latar belakang (service clamav-freshclam)"

    info "Update database rkhunter (timeout 2 menit)"
    if timeout 120 rkhunter --update --nocolors 2>&1 | tee -a "$LOG"; then
        ok "Database rkhunter terbaru"
    else
        warn "Update rkhunter timeout, akan otomatis dicoba lagi lewat cron"
    fi
    timeout 60 rkhunter --propupd --nocolors 2>&1 | tee -a "$LOG" || true

    cat > /usr/local/sbin/daily-malware-scan.sh <<-'END'
#!/bin/bash
LOG="/var/log/clamav/daily-scan.log"
echo "===== Scan $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$LOG"
clamscan -ri --exclude-dir="^/proc" --exclude-dir="^/sys" \
    --exclude-dir="^/var/lib/vnstat" --exclude-dir="^/var/log" \
    /root /home /etc /usr/local/bin /usr/local/sbin /tmp /var/tmp /dev/shm \
    >> "$LOG" 2>&1
rkhunter --check --skip-keypress --report-warnings-only --nocolors >> /var/log/rkhunter/daily-check.log 2>&1
END
    chmod +x /usr/local/sbin/daily-malware-scan.sh

    cat > /etc/cron.d/anti_virus_scan <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3 * * * root /usr/local/sbin/daily-malware-scan.sh
0 4 * * * root /usr/bin/freshclam --quiet
END
    chmod 644 /etc/cron.d/anti_virus_scan

    log "Setup anti-virus selesai"
    ok "Proteksi anti-virus terpasang (scan harian jam 03:00)"
}

# ============================================================
#  SETUP TERPASANG SEKALI: watchdog cron, limit systemd,
#  anti-ddos, anti-virus. Ditandai lewat file MARKER supaya
#  tidak diulang tiap menit.
# ============================================================

run_install() {
    info "Instalasi protect-resource.sh dimulai"
    mkdir -p /var/log
    touch "$LOG"

    # pasang diri sendiri di lokasi tetap + jadwalkan tiap menit
    SELF="$(readlink -f "$0")"
    if [[ "$SELF" != "/usr/local/sbin/protect-resource.sh" ]]; then
        cp -f "$SELF" /usr/local/sbin/protect-resource.sh
        chmod +x /usr/local/sbin/protect-resource.sh
    fi

    cat > /etc/cron.d/protect_resource <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * root /usr/local/sbin/protect-resource.sh watch
END
    chmod 644 /etc/cron.d/protect_resource
    systemctl restart cron 2>&1 | tee -a "$LOG"
    ok "Watchdog CPU/RAM dijadwalkan tiap menit lewat cron"

    # batasi resource per-service via systemd drop-in
    for svc in xray haproxy nginx dropbear openvpn squid; do
        if systemctl list-unit-files | grep -q "^${svc}.service"; then
            mkdir -p /etc/systemd/system/${svc}.service.d
            cat > /etc/systemd/system/${svc}.service.d/limit-resource.conf <<-END
[Service]
CPUQuota=70%
MemoryMax=70%
MemoryHigh=60%
OOMScoreAdjust=-500
END
        fi
    done
    systemctl daemon-reload
    ok "Batas CPU/RAM per-service terpasang"

    setup_anti_ddos
    setup_anti_virus

    touch "$MARKER"
    ok "Instalasi selesai: watchdog CPU/RAM, anti-DDoS, dan anti-virus aktif"

    # hapus file installer yang diunduh (BUKAN salinan di
    # /usr/local/sbin, itu tetap dibutuhkan cron tiap menit)
    if [[ "$SELF" != "/usr/local/sbin/protect-resource.sh" && -f "$SELF" ]]; then
        rm -f "$SELF"
    fi

    echo "done"
}

# ============================================================
#  MAIN
# ============================================================

case "$1" in
    install)
        run_install
        run_watchdog
        ;;
    watch)
        # dipanggil dari cron tiap menit -> diam, cukup catat ke log
        run_watchdog
        ;;
    *)
        if [[ ! -f "$MARKER" ]]; then
            run_install
        else
            info "Setup sudah pernah dijalankan sebelumnya (marker: $MARKER)"
            info "Menjalankan cek CPU/RAM sekali secara manual..."
        fi
        run_watchdog
        cpu=$(get_cpu_usage); ram=$(get_ram_usage); swap=$(get_swap_usage)
        info "Status saat ini -> CPU: ${cpu}% | RAM: ${ram}% | SWAP: ${swap}%"
        ok "Watchdog tetap berjalan otomatis tiap menit lewat cron (/etc/cron.d/protect_resource)"
        echo "Gunakan './protect-resource.sh install' untuk memasang ulang paksa (sysctl/iptables/fail2ban/clamav/rkhunter)."
        ;;
esac
