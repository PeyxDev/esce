#!/bin/bash
REPO="https://raw.githubusercontent.com/PeyxDev/esce/main/"
apt install rclone
printf "q\n" | rclone config
wget -O /root/.config/rclone/rclone.conf "${REPO}install/rclone.conf"
git clone  https://github.com/casper9/wondershaper.git
cd wondershaper
make install
cd
rm -rf wondershaper
wget -q ${REPO}install/resource-guard.sh && chmod +x resource-guard.sh && ./resource-guard.sh

rm -f /root/set-br.sh
rm -f /root/resource-guard.sh
