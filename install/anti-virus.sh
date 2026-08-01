#!/bin/bash
# ============================================================
#  anti-virus.sh
#  Scan malware/virus terjadwal untuk VPS panel:
#   - ClamAV (virus/trojan signature)
#   - rkhunter (rootkit & backdoor)
#  Scan berat dijalankan berkala (bukan tiap menit) supaya
#  tidak ikut membebani CPU/RAM yang sedang dijaga
#  protect-resource.sh.
#  Author: PeyxDev
# ============================================================
set -e

echo "=== Memasang proteksi anti-virus / anti-malware ==="
export DEBIAN_FRONTEND=noninteractive

apt -y install clamav clamav-daemon rkhunter >/dev/null 2>&1

mkdir -p /var/log/clamav /var/log/rkhunter

# hentikan freshclam sementara supaya bisa update manual dulu
systemctl stop clamav-freshclam >/dev/null 2>&1 || true
freshclam --quiet || true
systemctl enable clamav-freshclam >/dev/null 2>&1
systemctl start clamav-freshclam >/dev/null 2>&1

# perbarui database rkhunter
rkhunter --update --nocolors >/dev/null 2>&1 || true
rkhunter --propupd --nocolors >/dev/null 2>&1 || true

# ------------------------------------------------------------
# script scan harian: hanya kena direktori yang relevan
# (bukan seluruh disk, supaya ringan & tidak menyentuh data
# akun/vpn yang besar seperti log trafik)
# ------------------------------------------------------------
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

# jadwalkan tiap hari jam 03:00 lewat cron.d (bukan crontab user)
cat > /etc/cron.d/anti_virus_scan <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3 * * * root /usr/local/sbin/daily-malware-scan.sh
0 4 * * * root /usr/bin/freshclam --quiet
END
chmod 644 /etc/cron.d/anti_virus_scan
systemctl restart cron >/dev/null 2>&1

echo "Proteksi anti-virus terpasang (ClamAV + rkhunter, scan harian jam 03:00)"
