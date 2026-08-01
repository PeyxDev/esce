#!/bin/bash
# ==================================================================
#  resource-guard-setup.sh
#  Mencegah RAM/CPU VPS "over" sampai tidak bisa login SSH.
#
#  Yang dilakukan:
#   1. Pasang batas CPU & RAM keras (systemd cgroup) untuk service
#      yang diketahui rakus (limitvmess/vless/trojan, badvpn1-3).
#   2. Pasang watchdog cron yang memantau CPU/RAM tiap menit dan
#      auto-restart service pelaku bila terus tinggi (dengan cooldown
#      supaya tidak restart-loop).
#   3. Amankan sshd & dropbear dari OOM-killer (oom_score_adj) +
#      pastikan swap tersedia supaya server tidak langsung hang saat
#      RAM penuh.
#
#  Jalankan sebagai root: bash resource-guard-setup.sh
# ==================================================================
set -e

echo "==> [1/5] Menentukan service yang akan dibatasi..."

# Daftar service yang diketahui berpotensi rakus CPU/RAM.
# Skrip otomatis skip service yang tidak ada di server ini.
TARGET_SERVICES=(limitvmess limitvless limittrojan badvpn1 badvpn2 badvpn3)

CPU_QUOTA="25%"     # tiap service maksimal 25% dari 1 core
MEM_MAX="256M"       # tiap service maksimal 256MB RAM
TASKS_MAX="200"      # cegah fork-bomb dari loop (batas jumlah proses/thread)

for svc in "${TARGET_SERVICES[@]}"; do
    unit="${svc}.service"
    if systemctl list-unit-files | grep -q "^${unit}"; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/resource-limit.conf" <<EOF
[Service]
CPUQuota=${CPU_QUOTA}
MemoryMax=${MEM_MAX}
MemoryHigh=$(( ${MEM_MAX%M} * 80 / 100 ))M
TasksMax=${TASKS_MAX}
# Jika service melebihi MemoryMax, kernel akan OOM-kill proses ini duluan,
# bukan proses lain / sshd.
OOMPolicy=kill
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300
StartLimitBurst=10
EOF
        echo "    - Dibatasi: ${unit} (CPU ${CPU_QUOTA}, RAM ${MEM_MAX})"
    else
        echo "    - Dilewati (tidak ditemukan): ${unit}"
    fi
done

systemctl daemon-reload
for svc in "${TARGET_SERVICES[@]}"; do
    unit="${svc}.service"
    if systemctl list-unit-files | grep -q "^${unit}"; then
        systemctl restart "${unit}" 2>/dev/null || true
    fi
done

echo "==> [2/5] Melindungi sshd/dropbear dari OOM-killer..."
for svc in ssh sshd dropbear; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
        mkdir -p "/etc/systemd/system/${svc}.service.d"
        cat > "/etc/systemd/system/${svc}.service.d/oom-protect.conf" <<EOF
[Service]
OOMScoreAdjust=-800
EOF
    fi
done
systemctl daemon-reload

echo "==> [3/5] Memastikan swap tersedia (mencegah OOM total saat RAM habis)..."
if [ "$(swapon --show | wc -l)" -eq 0 ]; then
    if [ ! -f /swapfile ]; then
        fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
        chmod 600 /swapfile
        mkswap /swapfile
    fi
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
    echo "    - Swap 1G dipasang di /swapfile"
else
    echo "    - Swap sudah ada, dilewati"
fi

echo "==> [4/5] Tuning sysctl (kurangi kepanikan OOM & swap berlebihan)..."
cat > /etc/sysctl.d/99-resource-guard.conf <<EOF
vm.swappiness=10
vm.overcommit_memory=1
vm.panic_on_oom=0
EOF
sysctl -p /etc/sysctl.d/99-resource-guard.conf >/dev/null

echo "==> [5/5] Memasang watchdog monitor (cron tiap 1 menit)..."
mkdir -p /etc/resource-guard

# ---- Konfigurasi watchdog (edit sesuai kebutuhan) ----
cat > /etc/resource-guard/config <<'EOF'
# Ambang batas — kalau terlampaui, watchdog bertindak
CPU_THRESHOLD=90        # persen, rata-rata seluruh core
MEM_THRESHOLD=90        # persen RAM terpakai
COOLDOWN_SECONDS=300    # jarak minimum antar restart untuk service yang sama
LOG_FILE=/var/log/resource-guard.log

# Opsional: isi untuk dapat notifikasi Telegram saat watchdog bertindak
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Service yang boleh di-restart otomatis oleh watchdog jika dialah biang CPU/RAM tinggi
MANAGED_SERVICES="limitvmess limitvless limittrojan badvpn1 badvpn2 badvpn3 xray nginx haproxy"
EOF

cat > /usr/local/bin/resource-guard.sh <<'GUARD_EOF'
#!/bin/bash
source /etc/resource-guard/config
mkdir -p /var/lib/resource-guard

notify() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s --max-time 10 \
            -d "chat_id=${TELEGRAM_CHAT_ID}&text=${msg}" \
            "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null 2>&1
    fi
}

# --- Ambil pemakaian CPU total (%) rata-rata 1 detik ---
cpu_idle=$(top -bn2 -d 1 | grep "Cpu(s)" | tail -1 | awk -F',' '{print $4}' | grep -o '[0-9.]*')
cpu_used=$(awk -v idle="$cpu_idle" 'BEGIN{printf "%.0f", 100-idle}')

# --- Ambil pemakaian RAM (%) ---
mem_used=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')

echo "$(date '+%Y-%m-%d %H:%M:%S') CPU=${cpu_used}% MEM=${mem_used}%" >> "$LOG_FILE"

if [[ "$cpu_used" -ge "$CPU_THRESHOLD" || "$mem_used" -ge "$MEM_THRESHOLD" ]]; then
    # Cari proses paling rakus saat ini
    top_proc=$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu | sed -n 2p)
    notify "⚠️ VPS overload: CPU ${cpu_used}% / MEM ${mem_used}%. Proses teratas: ${top_proc}"

    for svc in $MANAGED_SERVICES; do
        pid=$(systemctl show -p MainPID --value "${svc}.service" 2>/dev/null)
        [[ -z "$pid" || "$pid" == "0" ]] && continue

        proc_cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
        proc_cpu=${proc_cpu%.*}
        [[ -z "$proc_cpu" ]] && continue

        # Hanya bertindak kalau service ini memang penyumbang beban signifikan
        if [[ "$proc_cpu" -ge 15 ]]; then
            lock="/var/lib/resource-guard/${svc}.lastrestart"
            now=$(date +%s)
            last=$(cat "$lock" 2>/dev/null || echo 0)

            if (( now - last >= COOLDOWN_SECONDS )); then
                systemctl restart "${svc}.service"
                echo "$now" > "$lock"
                notify "🔄 Restart ${svc}.service (pakai ${proc_cpu}% CPU) untuk turunkan beban."
            fi
        fi
    done
fi
GUARD_EOF

chmod +x /usr/local/bin/resource-guard.sh
touch /var/log/resource-guard.log

# Pasang cron (jalan tiap menit), hindari duplikat kalau di-run ulang
( crontab -l 2>/dev/null | grep -v 'resource-guard.sh' ; echo "* * * * * /usr/local/bin/resource-guard.sh" ) | crontab -

echo ""
echo "=========================================================="
echo " Selesai."
echo " - Batas CPU/RAM per-service : /etc/systemd/system/<service>.service.d/resource-limit.conf"
echo " - Konfigurasi watchdog      : /etc/resource-guard/config"
echo " - Log watchdog              : /var/log/resource-guard.log"
echo " - (Opsional) isi TELEGRAM_BOT_TOKEN & TELEGRAM_CHAT_ID di"
echo "   /etc/resource-guard/config untuk notifikasi otomatis."
echo "=========================================================="
