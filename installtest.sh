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
# Добавляем git в список обязательных программ
sudo apt-get install -y -qq git bc curl wget ufw net-tools lscpu iperf3 speedtest-cli qrencode unzip iputils-ping > /dev/null

echo -e "${CYAN}>>> [2/4] Подготовка структуры директорий...${NC}"
mkdir -p /root/scanner
mkdir -p /etc/server-menu

echo -e "${CYAN}>>> [3/4] Клонирование репозитория с GitHub...${NC}"
# Если папка уже есть, заходим в неё и обновляем, если нет — клонируем
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${YELLOW}ℹ️  Проект уже установлен. Обновляю файлы...${NC}"
    cd "$INSTALL_DIR" && git pull &>/dev/null
else
    rm -rf "$INSTALL_DIR" # Удаляем старую папку, если она была без .git
    git clone https://github.com/$GITHUB_USER/$REPO_NAME.git "$INSTALL_DIR" &>/dev/null
fi

# Даем права на запуск всем файлам в папке
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/server-menu "$INSTALL_DIR"/ipv6-* &>/dev/null

# Создаем символические ссылки в /usr/local/bin, чтобы команды работали глобально
# Теперь файлы физически лежат в одной папке, но доступны везде
ln -sf "$INSTALL_DIR/server-menu" /usr/local/bin/server-menu
ln -sf "$INSTALL_DIR/menu_mtproxy.sh" /usr/local/bin/menu_mtproxy.sh
ln -sf "$INSTALL_DIR/_config_and_utils.sh" /usr/local/bin/_config_and_utils.sh
# Добавь сюда ссылки на остальные файлы из своего списка FILES, если они нужны глобально

# Создаем алиас 'menu' для быстрого запуска
echo "#!/bin/bash" | sudo tee /usr/bin/menu > /dev/null
echo "cd $INSTALL_DIR && ./server-menu" | sudo tee -a /usr/bin/menu > /dev/null
sudo chmod +x /usr/bin/menu

echo -e "${CYAN}>>> [4/4] Настройка автозапуска при входе...${NC}"
BASHRC="$HOME/.bashrc"
if ! grep -q "server-menu" "$BASHRC"; then
    cat <<EOF >> "$BASHRC"

# --- SERVER MENU AUTOSTART ---
if [[ \$- == *i* ]]; then
    if [ -z "\$SSH_CLIENT" ] || [ -n "\$SSH_TTY" ]; then
        cd $INSTALL_DIR && ./server-menu
    fi
fi
# -----------------------------
EOF
    echo -e "${GREEN}✅ Автозапуск добавлен.${NC}"
else
    echo -e "${GREEN}ℹ️  Автозапуск уже был настроен.${NC}"
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}   УСТАНОВКА И ОБНОВЛЕНИЕ ЗАВЕРШЕНЫ УСПЕШНО!         ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "Теперь вы можете запустить меню командой: ${CYAN}menu${NC}"
echo ""

# Сразу запускаем меню
cd "$INSTALL_DIR" && ./server-menu
