#!/bin/bash

# ==========================================
# 🔧 НАСТРОЙКИ РЕПОЗИТОРИЯ
# ==========================================
GITHUB_USER="Diman6267"
REPO_NAME="VPS-Server-Menu"
INSTALL_DIR="/root/$REPO_NAME"

# Цвета
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}>>> [1/4] Установка системных зависимостей...${NC}"
sudo apt-get update -qq
sudo apt-get install -y -qq git bc curl wget ufw net-tools lscpu iperf3 speedtest-cli qrencode unzip iputils-ping > /dev/null

echo -e "${CYAN}>>> [2/4] Подготовка структуры директорий...${NC}"
mkdir -p /root/scanner
mkdir -p /etc/server-menu

echo -e "${CYAN}>>> [3/4] Клонирование репозитория с GitHub...${NC}"
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${YELLOW}ℹ️  Проект уже установлен. Обновляю файлы...${NC}"
    cd "$INSTALL_DIR" && git pull &>/dev/null
else
    rm -rf "$INSTALL_DIR" 
    git clone https://github.com/$GITHUB_USER/$REPO_NAME.git "$INSTALL_DIR" &>/dev/null
fi

# Даем права на запуск всем файлам
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/server-menu "$INSTALL_DIR"/ipv6-* &>/dev/null

# Создаем символические ссылки в /usr/local/bin
# Это позволит твоим скриптам находить друг друга по старым путям [cite: 1, 21]
for file in "$INSTALL_DIR"/*; do
    filename=$(basename "$file")
    ln -sf "$file" "/usr/local/bin/$filename"
done

echo -e "${CYAN}>>> [4/4] Настройка автозапуска при входе...${NC}"
BASHRC="$HOME/.bashrc"
# Оставляем запуск именно через server-menu, как ты просил [cite: 4]
if ! grep -q "server-menu" "$BASHRC"; then
    cat <<EOF >> "$BASHRC"

# --- SERVER MENU AUTOSTART ---
if [[ \$- == *i* ]]; then
    if [ -z "\$SSH_CLIENT" ] || [ -n "\$SSH_TTY" ]; then
        /usr/local/bin/server-menu
    fi
fi
# -----------------------------
EOF
    echo -e "${GREEN}✅ Автозапуск настроен.${NC}"
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}   УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!         ${NC}"
echo -e "Запуск: ${CYAN}server-menu${NC}"
echo ""

# Сразу запускаем меню по его законному имени
/usr/local/bin/server-menu
