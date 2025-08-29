#!/bin/bash
rm /var/lib/dpkg/stato*
rm /var/lib/dpkg/lock*
cd /etc/systemd/system/
rm -rf kyt.service
cd
grenbo="\e[92;1m"
NC='\e[0m'
#install
cd /usr/bin
rm -rf kyt
rm kyt.*
rm -rf bot
rm bot.*
apt update && apt upgrade
apt install neofetch -y
apt install python3 python3-pip git
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
node -v
npm -v
sudo apt install -y build-essential
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
source ~/.bashrc
nvm install 18
nvm use 18
nvm alias default 18
npm install telegraf
npm install node-ssh
npm install -g pm2
sudo apt install pipx

cd /usr/bin
wget http://myrid.my.id/os/Bot/botsc.js
chmod +x /usr/bin/*
pipx install telethon paramiko

#isi data
echo ""
figlet  Xwan Vpn  | lolcat
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " \e[1;97;101m          ADD BOT INSTALL          \e[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "${grenbo}[*] Bot Ini Berfungsi Untuk Install Script SSH Ridwan${NC}"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
clear
pm2 start botsc.js
pm2 save
cd /root
rm -rf installsc.sh
echo "Done"
echo "Setting done"
clear

echo " Installations complete, type /start on your bot"
