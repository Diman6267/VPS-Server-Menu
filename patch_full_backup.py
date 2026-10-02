import os

sched_file = '/opt/remnawave/backup-scheduler.sh'
if not os.path.exists(sched_file):
    exit(0)

with open(sched_file, 'r') as f:
    content = f.read()

if 'FULL STACK BACKUP' in content:
    exit(0)

custom_block = r'''# === FULL STACK BACKUP: Case211 Bot, Systemd Caddy, Remnanode ===
if [ -d "/opt/remnawave-admin" ]; then
    log_message "Step 2.5b: Backing up Case211 Admin Bot (/opt/remnawave-admin)..."
    mkdir -p "$temp_backup_dir/remnawave-admin"
    cp /opt/remnawave-admin/.env "$temp_backup_dir/remnawave-admin/" 2>/dev/null || true
    cp /opt/remnawave-admin/docker-compose.yml "$temp_backup_dir/remnawave-admin/" 2>/dev/null || true
    [ -d "/opt/remnawave-admin/plugins" ] && cp -r /opt/remnawave-admin/plugins "$temp_backup_dir/remnawave-admin/" 2>/dev/null || true

    if docker ps --format '{{.Names}}' | grep -q "^remnawave-admin-db$"; then
        BOT_PG_USER=$(grep -E '^POSTGRES_USER=' /opt/remnawave-admin/.env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        BOT_PG_DB=$(grep -E '^POSTGRES_DB=' /opt/remnawave-admin/.env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        BOT_PG_USER=${BOT_PG_USER:-postgres}
        BOT_PG_DB=${BOT_PG_DB:-remnawave_bot}
        if docker exec -t remnawave-admin-db pg_dump -c -U "$BOT_PG_USER" "$BOT_PG_DB" 2>/dev/null | gzip -6 > "$temp_backup_dir/remnawave-admin/admin-bot-db.sql.gz"; then
            log_message "  ✓ Case211 Admin Bot database & configs backed up successfully"
        else
            log_message "  WARNING: Failed to dump Case211 database"
        fi
    fi
    bot_found=true
fi

if [ -f "/etc/caddy/Caddyfile" ]; then
    log_message "Step 2.6b: Backing up Systemd Caddy & Selfsteal site..."
    mkdir -p "$temp_backup_dir/systemd-caddy"
    cp /etc/caddy/Caddyfile "$temp_backup_dir/systemd-caddy/Caddyfile"
    [ -d "/etc/caddy/certs" ] && cp -r /etc/caddy/certs "$temp_backup_dir/systemd-caddy/" 2>/dev/null || true
    [ -d "/var/www/html" ] && tar czf "$temp_backup_dir/systemd-caddy/var-www-html.tar.gz" -C /var/www/html . 2>/dev/null || true
    log_message "  ✓ Systemd Caddy (Caddyfile, certs, /var/www/html) backed up"
fi

if [ -d "/opt/remnanode" ]; then
    log_message "Step 2.8: Backing up local Remnanode & Hysteria2 certs..."
    mkdir -p "$temp_backup_dir/remnanode"
    cp /opt/remnanode/.env "$temp_backup_dir/remnanode/" 2>/dev/null || true
    cp /opt/remnanode/docker-compose.yml "$temp_backup_dir/remnanode/" 2>/dev/null || true
    [ -d "/root/cert" ] && tar czf "$temp_backup_dir/remnanode/root-cert.tar.gz" -C /root/cert . 2>/dev/null || true
    log_message "  ✓ Remnanode & /root/cert backed up"
fi

cat > "$temp_backup_dir/restore-full-stack.sh" << 'FULL_RESTORE_EOF'
#!/bin/bash
set -e
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=== Восстановление стека (Systemd Caddy, Case211 Bot, Remnanode, Планировщик) ==="

docker network inspect remnawave-network >/dev/null 2>&1 || docker network create remnawave-network

if [ -d "$BACKUP_DIR/systemd-caddy" ]; then
    echo "-> 1/4: Восстановление Systemd Caddy и сайта Selfsteal..."
    if ! command -v caddy >/dev/null 2>&1; then
        apt update && apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt update && apt install -y caddy
    fi
    mkdir -p /etc/caddy /var/www/html
    cp "$BACKUP_DIR/systemd-caddy/Caddyfile" /etc/caddy/Caddyfile
    if [ -d "$BACKUP_DIR/systemd-caddy/certs" ]; then
        cp -r "$BACKUP_DIR/systemd-caddy/certs" /etc/caddy/
        id caddy >/dev/null 2>&1 && chown -R caddy:caddy /etc/caddy/certs
    fi
    [ -f "$BACKUP_DIR/systemd-caddy/var-www-html.tar.gz" ] && tar xzf "$BACKUP_DIR/systemd-caddy/var-www-html.tar.gz" -C /var/www/html
    systemctl enable caddy && systemctl restart caddy
    echo "   ✓ Caddy и Selfsteal восстановлены"
fi

if [ -d "$BACKUP_DIR/remnanode" ]; then
    echo "-> 2/4: Восстановление локальной ноды Remnanode..."
    mkdir -p /opt/remnanode /root/cert
    cp "$BACKUP_DIR/remnanode/.env" /opt/remnanode/ 2>/dev/null || true
    cp "$BACKUP_DIR/remnanode/docker-compose.yml" /opt/remnanode/ 2>/dev/null || true
    [ -f "$BACKUP_DIR/remnanode/root-cert.tar.gz" ] && tar xzf "$BACKUP_DIR/remnanode/root-cert.tar.gz" -C /root/cert
    chmod -R 755 /root/cert
    cd /opt/remnanode && docker compose up -d
    echo "   ✓ Remnanode восстановлена"
fi

if [ -d "$BACKUP_DIR/remnawave-admin" ]; then
    echo "-> 3/4: Восстановление Админ-бота Case211..."
    if [ ! -d "/opt/remnawave-admin/.git" ]; then
        git clone https://github.com/Case211/remnawave-admin.git /opt/remnawave-admin
    fi
    mkdir -p /opt/remnawave-admin/logs && chown -R 70:70 /opt/remnawave-admin/logs
    cp "$BACKUP_DIR/remnawave-admin/.env" /opt/remnawave-admin/.env
    cp "$BACKUP_DIR/remnawave-admin/docker-compose.yml" /opt/remnawave-admin/docker-compose.yml
    [ -d "$BACKUP_DIR/remnawave-admin/plugins" ] && cp -r "$BACKUP_DIR/remnawave-admin/plugins" /opt/remnawave-admin/
    cd /opt/remnawave-admin
    docker compose up -d remnawave-admin-db
    for i in {1..15}; do
        docker exec remnawave-admin-db pg_isready >/dev/null 2>&1 && break
        sleep 2
    done
    if [ -f "$BACKUP_DIR/remnawave-admin/admin-bot-db.sql.gz" ]; then
        BOT_PG_USER=$(grep -E '^POSTGRES_USER=' /opt/remnawave-admin/.env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        BOT_PG_DB=$(grep -E '^POSTGRES_DB=' /opt/remnawave-admin/.env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        gunzip -c "$BACKUP_DIR/remnawave-admin/admin-bot-db.sql.gz" | docker exec -i remnawave-admin-db psql -U "${BOT_PG_USER:-postgres}" -d "${BOT_PG_DB:-remnawave_bot}" >/dev/null 2>&1 || true
    fi
    docker compose up -d
    echo "   ✓ Админ-бот Case211 и его БД полностью восстановлены"
fi

if [ -d "/opt/remnawave" ]; then
    echo "-> 4/4: Восстановление модифицированного планировщика бэкапов и Cron..."
    mkdir -p /opt/remnawave/logs /opt/remnawave/backups
    [ -f "$BACKUP_DIR/backup-config.json" ] && cp "$BACKUP_DIR/backup-config.json" /opt/remnawave/backup-config.json
    [ -f "$BACKUP_DIR/backup-scheduler.sh" ] && cp "$BACKUP_DIR/backup-scheduler.sh" /opt/remnawave/backup-scheduler.sh
    chmod +x /opt/remnawave/backup-scheduler.sh 2>/dev/null || true
    CRON_SCHEDULE=$(jq -r '.schedule // "0 3 * * *"' /opt/remnawave/backup-config.json 2>/dev/null || echo "0 3 * * *")
    (crontab -l 2>/dev/null | grep -v "/opt/remnawave/backup-scheduler.sh"; echo "$CRON_SCHEDULE /opt/remnawave/backup-scheduler.sh >> /opt/remnawave/logs/backup.log 2>&1") | crontab -
    echo "   ✓ Автобэкап Полного Стека (Панель+Бот+Caddy+Нода) активирован в Cron ($CRON_SCHEDULE)"
fi
FULL_RESTORE_EOF
chmod +x "$temp_backup_dir/restore-full-stack.sh"
# === END FULL STACK BACKUP ===
'''

target = '# Шаг 3: Добавляем скрипт управления'
if target in content:
    content = content.replace(target, custom_block + '\n' + target)
    with open(sched_file, 'w') as f:
        f.write(content)
    print("🔧 Модификация Полного Бэкапа (Панель+Бот+Caddy+Нода) автоматически применена!")
