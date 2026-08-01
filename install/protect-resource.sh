#!/bin/bash
# ============================================================
#  protect-resource.sh
#  Watchdog CPU & RAM untuk VPS panel (xray/haproxy/nginx/
#  dropbear/openvpn/squid/badvpn/ws/kyt/dst).
#  PRINSIP: tidak pernah menghentikan service/koneksi akun yang
#  sah. Hanya menindak proses yang benar-benar mencurigakan.
#  Dipasang oleh ssh-vpn.sh.
#  Author: PeyxDev
# ============================================================

LOG="/var/log/protect-resource.log"
CPU_LIMIT=90      # persen, ambang batas CPU
RAM_LIMIT=90      # persen, ambang batas RAM
SWAP_LIMIT=85     # persen, ambang batas SWAP

# ------------------------------------------------------------
# Semua service & proses panel yang WAJIB tetap hidup.
# Termasuk proses koneksi akun (sshd session, dropbear, openvpn
# client, xray inbound, dsb) -> TIDAK PERNAH di-kill oleh script ini.
# ------------------------------------------------------------
CORE_SERVICES=(xray haproxy nginx dropbear openvpn squid squid3 badvpn1 badvpn2 badvpn3 runn vnstat fail2ban cron rsyslog netfilter-persistent)

# pola nama proses yang aman / bagian dari sistem & panel,
# termasuk sesi login akun (jangan pernah disentuh)
SAFE_PATTERNS=(
    "xray" "haproxy" "nginx" "dropbear" "openvpn" "squid"
    "badvpn" "ws" "kyt" "sshd" "ssh" "php-fpm" "screen"
    "systemd" "init" "cron" "rsyslog" "vnstat" "fail2ban"
    "netfilter" "bash" "sh" "dash" "login" "getty" "agetty"
    "dbus" "networkd" "resolved" "journald" "udevd" "lolcat"
    "ruby" "gem"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk -F',' '{print $4}' | awk '{print 100-$1}' | cut -d'.' -f1
}

get_ram_usage() {
    free | awk '/Mem:/ {printf "%d", ($3/$2)*100}'
}

get_swap_usage() {
    free | awk '/Swap:/ {if ($2==0) print 0; else printf "%d", ($3/$2)*100}'
}

# turunkan prioritas OOM-kill untuk service inti supaya tidak dimatikan duluan
# oleh kernel saat RAM kritis
protect_core_services() {
    for svc in "${CORE_SERVICES[@]}"; do
        pid=$(systemctl show -p MainPID --value "$svc" 2>/dev/null)
        if [[ -n "$pid" && "$pid" != "0" && -e "/proc/$pid/oom_score_adj" ]]; then
            echo -1000 > "/proc/$pid/oom_score_adj" 2>/dev/null
        fi
    done
}

# bersihkan cache halaman (aman, tidak menyentuh proses sama sekali)
clear_cache() {
    sync
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null
    log "RAM tinggi -> cache dibersihkan (sync + drop_caches)"
}

# proses dianggap AMAN (tidak boleh disentuh) jika namanya cocok
# salah satu SAFE_PATTERNS, atau merupakan sesi login akun
# (mis. "sshd: user@pts/0", "dropbear: user")
is_safe_process() {
    local comm="$1" cmdline="$2"
    for pat in "${SAFE_PATTERNS[@]}"; do
        [[ "$comm" == *"$pat"* || "$cmdline" == *"$pat"* ]] && return 0
    done
    return 1
}

# proses dianggap MENCURIGAKAN jika:
#  - binary dijalankan dari lokasi yang tidak lazim (/tmp, /var/tmp,
#    /dev/shm, /run) yang biasa dipakai malware/cryptominer, ATAU
#  - binary sudah dihapus dari disk tapi masih berjalan (ciri khas
#    proses malware yang menyembunyikan diri), ATAU
#  - nama proses menyerupai miner/backdoor yang umum dikenal
is_suspicious_process() {
    local pid="$1" comm="$2"
    local exe_path
    exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null)

    # binary sudah dihapus dari disk tapi proses masih jalan
    if [[ "$exe_path" == *"(deleted)"* ]]; then
        return 0
    fi

    # dijalankan dari direktori yang tidak lazim untuk service resmi
    case "$exe_path" in
        /tmp/*|/var/tmp/*|/dev/shm/*|/run/*) return 0 ;;
    esac

    # nama proses menyerupai malware/miner yang umum dikenal
    case "$comm" in
        *xmrig*|*kdevtmpfsi*|*kinsing*|*minerd*|*cryptonight*|*.sh4*|*.mips*|*ddg.*) return 0 ;;
    esac

    return 1
}

# hanya hentikan proses yang lolos pengecekan is_suspicious_process.
# Proses berat tapi TIDAK mencurigakan (mis. koneksi user yang sah
# sedang transfer besar) TIDAK akan dihentikan, hanya dicatat di log.
handle_high_usage() {
    local reason="$1"

    ps -eo pid,comm,%cpu,%mem --sort=-%mem | awk 'NR>1' | while read -r pid comm cpu mem; do
        [[ -z "$pid" || "$pid" == "$$" ]] && continue

        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)

        if is_safe_process "$comm" "$cmdline"; then
            continue
        fi

        if is_suspicious_process "$pid" "$comm"; then
            kill -15 "$pid" 2>/dev/null
            sleep 2
            kill -9 "$pid" 2>/dev/null
            log "$reason -> PROSES MENCURIGAKAN dihentikan: PID=$pid CMD=$comm CPU=${cpu}% MEM=${mem}%"
        else
            # bukan service panel, bukan pola berbahaya yang dikenal
            # -> jangan di-kill, cukup dicatat sebagai peringatan
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

main() {
    protect_core_services

    cpu=$(get_cpu_usage)
    ram=$(get_ram_usage)
    swap=$(get_swap_usage)

    if [[ "$ram" -ge "$RAM_LIMIT" ]]; then
        clear_cache
        ram=$(get_ram_usage)
        if [[ "$ram" -ge "$RAM_LIMIT" ]]; then
            handle_high_usage "RAM masih tinggi (${ram}%)"
        fi
    fi

    if [[ "$cpu" -ge "$CPU_LIMIT" ]]; then
        handle_high_usage "CPU tinggi (${cpu}%)"
    fi

    if [[ "$swap" -ge "$SWAP_LIMIT" ]]; then
        log "SWAP tinggi (${swap}%)"
    fi

    restart_if_dead
}

main
