#!/bin/bash

# install-domcloud.sh - Script Otomatis Install Domcloud Self-Host
# Versi: 1.0 | Dibuat oleh onnoyukihiro untuk Ubuntu 24.04 LTS (Dell R730)
# Sumber: https://github.com/domcloud/container
# Log: /var/log/domcloud-install.log
# Jalankan: chmod +x install-domcloud.sh && ./install-domcloud.sh (sebagai root)

set -e  # Berhenti kalau error
LOGFILE="/var/log/domcloud-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== INSTALL DOMCLOUD SELF-HOST ===${NC}"
echo "Tanggal: $(date)"
echo "User: $(whoami)"
echo "OS: $(lsb_release -ds 2>/dev/null || echo 'Unknown')"

# 1. Validasi Root & OS
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Jalankan sebagai root (sudo ./install-domcloud.sh)${NC}"
    exit 1
fi

if ! command -v lsb_release &> /dev/null; then
    apt update && apt install lsb-release -y
fi

if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 24.04"; then
    echo -e "${YELLOW}Warning: Direkomendasikan Ubuntu 24.04 LTS. Lanjut? (y/n)${NC}"
    read -r confirm
    if [[ $confirm != "y" ]]; then exit 1; fi
fi

# 2. Update Sistem
echo -e "${GREEN}Update sistem...${NC}"
apt update && apt upgrade -y && apt autoremove -y

# Install prasyarat (curl, git, dll.)
apt install curl git wget unzip -y

# 3. Install Domcloud Core
OS="ubuntu"
echo -e "${GREEN}Install core Domcloud...${NC}"
curl -sSL "https://github.com/domcloud/container/raw/refs/heads/master/install-$OS.sh" | bash
curl -sSL "https://github.com/domcloud/container/raw/refs/heads/master/install-extra.sh" | bash
curl -sSL "https://github.com/domcloud/container/raw/refs/heads/master/preset.sh" | bash

# 4. Generate Passwords
echo -e "${GREEN}Generate passwords...${NC}"
curl -sSL "https://github.com/domcloud/container/raw/refs/heads/master/genpass.sh" | bash

# Tampilkan passwords
if [[ -f /root/.webmin_passwd ]]; then
    WEBMIN_PASS=$(cat /root/.webmin_passwd)
    echo -e "${YELLOW}=== PASSWORD TERBUAT (CATAT SEKARANG!) ===${NC}"
    echo -e "Webmin/Virtualmin root password: ${GREEN}$WEBMIN_PASS${NC}"
    echo -e "SSH password (jika diubah): $(cat /root/.ssh_passwd 2>/dev/null || echo 'Default root') ${NC}"
    echo -e "========================================${NC}"
else
    echo -e "${RED}Error: Gagal generate password. Cek log: $LOGFILE${NC}"
    exit 1
fi

# 5. Input User (Interaktif)
echo -e "${GREEN}Konfigurasi server...${NC}"
read -p "Domain bridge (misal: bridge.hostingku.com) [wajib]: " BRIDGE_DOMAIN
read -p "IP server publik (misal: 103.123.456.789) [wajib]: " SERVER_IP
read -p "Hostname (misal: server.hostingku.com) [wajib]: " HOSTNAME

if [[ -z "$BRIDGE_DOMAIN" || -z "$SERVER_IP" || -z "$HOSTNAME" ]]; then
    echo -e "${RED}Error: Semua field wajib diisi!${NC}"
    exit 1
fi

# Validasi IP sederhana
if ! [[ $SERVER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo -e "${RED}Error: IP tidak valid!${NC}"
    exit 1
fi

# 6. Setup Hostname & Hosts
echo -e "${GREEN}Setup hostname & hosts...${NC}"
hostnamectl set-hostname "$HOSTNAME"
echo "$HOSTNAME" > /etc/hostname
sed -i "/127.0.1.1/d" /etc/hosts  # Hapus baris lama
echo "127.0.1.1    $HOSTNAME" >> /etc/hosts

# 7. Backup & Setup Virtualmin (jika ada)
echo -e "${GREEN}Backup config Virtualmin...${NC}"
if [[ -d /etc/webmin ]]; then
    cp -r /etc/webmin /etc/webmin.backup.$(date +%Y%m%d)
    echo -e "${YELLOW}Backup disimpan di /etc/webmin.backup.$(date +%Y%m%d)${NC}"
fi

# Install Virtualmin jika belum (dari preset.sh seharusnya sudah ada)
if ! command -v virtualmin &> /dev/null; then
    echo -e "${GREEN}Install Virtualmin...${NC}"
    apt install virtualmin-config -y
fi

# 8. Konfigurasi Virtualmin Dasar
echo -e "${GREEN}Konfigurasi Virtualmin...${NC}"
# Buat virtual server bridge jika belum ada
virtualmin create-virtual-server --domain $BRIDGE_DOMAIN --pass random --ip-address $SERVER_IP --type website --features email
# Update DNS IP
virtualmin set-dns-ip --ip-address $SERVER_IP
# Enable SSL (Let's Encrypt - butuh email, skip jika belum)
echo -e "${YELLOW}Setup SSL: Jalankan manual di Virtualmin setelah login.${NC}"

# 9. Firewall & Service
echo -e "${GREEN}Setup firewall...${NC}"
ufw allow OpenSSH
ufw allow 80,443,2443/tcp
ufw --force enable

# Restart services
systemctl restart webmin nginx postfix

# 10. Checklist Akhir
echo -e "${GREEN}=== CHECKLIST INSTALL ===${NC}"
echo "- OS: $(lsb_release -ds) ✅"
echo "- Hostname: $HOSTNAME ✅"
echo "- IP: $SERVER_IP ✅"
echo "- Domain Bridge: $BRIDGE_DOMAIN ✅"
echo "- Webmin Active: $(systemctl is-active webmin && echo '✅' || echo '❌')${NC}"
echo "- Akses Virtualmin: https://$SERVER_IP:2443 (root / $WEBMIN_PASS)"
echo "- Portal Domcloud: https://my.domcloud.co/user/server/ (add self-hosted)"
echo "- Log: $LOGFILE"
echo -e "${YELLOW}Next: Re-check config di Virtualmin → System Settings → Re-Check Configuration${NC}"
echo "================================"

# 11. Reboot Konfirmasi
echo -e "${GREEN}Install selesai! Reboot untuk apply semua? (y/n): ${NC}"
read -r reboot_confirm
if [[ $reboot_confirm == "y" ]]; then
    echo -e "${GREEN}Reboot dalam 10 detik... Selamat hosting! 🚀${NC}"
    sleep 10
    reboot
else
    echo -e "${YELLOW}Reboot manual: reboot${NC}"
fi
