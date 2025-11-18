# Export flag untuk enable service full
export OPTIONAL_INSTALL=1

# Ulangi genpass (force service)
curl -sSL https://github.com/domcloud/container/raw/refs/heads/master/genpass.sh | bash

# Kalau masih error, manual generate & set service pass
SERVICE_PASS=$(openssl rand -base64 32 | tr -d '\n')
echo "Service password baru: $SERVICE_PASS"

# Simpan ke env file (untuk bridge/rdproxy)
echo "BRIDGE_SERVICE_PASS=$SERVICE_PASS" >> /root/.env
source /root/.env

# Update passwords di file terkait (manual patch)
echo "$SERVICE_PASS" > /root/.service_passwd  # Backup

# Re-run preset untuk sync config (termasuk bridge)
curl -sSL https://github.com/domcloud/container/raw/refs/heads/master/preset.sh | bash

# Restart services kunci
systemctl restart webmin nginx mariadb postfix docker rdproxy bridge 2>/dev/null || true

# Cek status bridge service
systemctl status bridge  # Harus "active (running)"
systemctl status rdproxy  # Harus "active (running)"
