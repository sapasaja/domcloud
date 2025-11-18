#!/bin/bash

set -e
LOGFILE="/var/log/domcloud-fix.log"
exec > >(tee -a "$LOGFILE") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== CEK & FIX DOMCLOUD SERVICE PASSWORD (V1.2) ===${NC}"
echo "Tanggal: $(date)"
echo "User: $(whoami)"
echo "OS: $(lsb_release -ds 2>/dev/null || echo 'Unknown')"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Jalankan sebagai root (sudo ./cek.sh)${NC}"
    exit 1
fi

apt update && apt install openssl -y

echo -e "${GREEN}Backup file env & passwords...${NC}"
cp /root/.env /root/.env.backup.$(date +%Y%m%d) 2>/dev/null || true
cp /root/.service_passwd /root/.service_passwd.backup.$(date +%Y%m%d) 2>/dev/null || true
echo -e "${YELLOW}Backup disimpan di /root/.env.backup.* & /root/.service_passwd.backup.*${NC}"

echo -e "${GREEN}Export flag & ulangi genpass...${NC}"
export OPTIONAL_INSTALL=1
curl -sSL https://github.com/domcloud/container/raw/refs/heads/master/genpass.sh | bash

if grep -q "Failed to generate service password" "$LOGFILE" 2>/dev/null || ! [[ -f /root/.service_passwd ]]; then
    echo -e "${YELLOW}Genpass gagal - manual generate service pass...${NC}"
    SERVICE_PASS=$(openssl rand -base64 32 | tr -d '\n')
    echo -e "${GREEN}Service password baru: $SERVICE_PASS${NC} (CATAT SEKARANG!)"
else
    SERVICE_PASS=$(cat /root/.service_passwd)
    echo -e "${GREEN}Service password dari genpass: $SERVICE_PASS${NC}"
fi

echo -e "${GREEN}Simpan ke .env...${NC}"
echo "BRIDGE_SERVICE_PASS=$SERVICE_PASS" >> /root/.env
source /root/.env
echo -e "${GREEN}Env loaded: $BRIDGE_SERVICE_PASS${NC}"

echo "$SERVICE_PASS" > /root/.service_passwd
echo -e "${GREEN}Service password disimpan di /root/.service_passwd${NC}"

echo -e "${GREEN}Re-run preset.sh...${NC}"
curl -sSL https://github.com/domcloud/container/raw/refs/heads/master/preset.sh | bash

echo -e "${GREEN}Restart services...${NC}"
systemctl restart webmin nginx mariadb postfix docker rdproxy bridge 2>/dev/null || true

echo -e "${GREEN}=== CHECKLIST FIX ===${NC}"
BRIDGE_STATUS=$(systemctl is-active bridge && echo '✅' || echo '❌')
RDP_STATUS=$(systemctl is-active rdproxy && echo '✅' || echo '❌')
WEBMIN_STATUS=$(systemctl is-active webmin && echo '✅' || echo '❌')
echo "- Bridge Service: $BRIDGE_STATUS"
echo "- Rdproxy Service: $RDP_STATUS"
echo "- Webmin Active: $WEBMIN_STATUS"
echo "- Service Pass Set: $([[ -f /root/.service_passwd ]] && echo '✅' || echo '❌')"
echo "- Env Loaded: $(env | grep BRIDGE_SERVICE_PASS && echo '✅' || echo '❌')"
echo -e "${YELLOW}Next: Reboot & akses https://IP_MU:2443${NC}"
echo "================================"

echo -e "${GREEN}Fix selesai! Reboot untuk apply? (y/n): ${NC}"
read -r reboot_confirm
if [[ $reboot_confirm == "y" ]]; then
    echo -e "${GREEN}Reboot dalam 10 detik... Selamat hosting! 🚀${NC}"
    sleep 10
    reboot
else
    echo -e "${YELLOW}Reboot manual: reboot${NC}"
fi

echo "Log lengkap: $LOGFILE"
