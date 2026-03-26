#!/bin/bash

# ==========================================
# 🔧 НАСТРОЙКИ РЕПОЗИТОРИЯ
# ==========================================
GITHUB_USER="Diman6267"
REPO_NAME="VPS-Server-Menu"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"

# Список всех твоих файлов
FILES=(
    "_config_and_utils.sh"
    "server-menu"
    "menu_setup.sh"
    "menu_tests.sh"
    "menu_xui.sh"
    "menu_hysteria.sh"
    "ipv6-menu"
    "ipv6-status"
    "apply-ipv6-disable.sh"
    "menu_mtproxy.sh"
)

# Цвета
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}>>> [1/4] Установка системных зависимостей...${NC}"
sudo apt-get update -qq
# bc нужен для расчета RAM в server-menu
# qrencode нужен для QR в menu_hysteria.sh
# ufw нужен для menu_setup.sh
# speedtest-cli/iperf3 нужны для тестов
sudo apt-get install -y -qq bc curl wget ufw net-tools lscpu iperf3 speedtest-cli qrencode unzip iputils-ping > /dev/null

echo -e "${CYAN}>>> [2/4] Подготовка структуры директорий...${NC}"
mkdir -p /root/scanner
mkdir -p /etc/server-menu
echo -e "${CYAN}>>> [3/4] Загрузка файлов с GitHub...${NC}"
for file in "${FILES[@]}"; do
    echo -n "   Скачивание $file... "
    if sudo wget -qO "/usr/local/bin/$file" "$BASE_URL/$file"; then
        sudo chmod +x "/usr/local/bin/$file"
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}ОШИБКА${NC}"
    fi
done

# Создаем алиас 'menu' для быстрого запуска
echo "bash /usr/local/bin/server-menu" | sudo tee /usr/bin/menu > /dev/null
sudo chmod +x /usr/bin/menu

echo -e "${CYAN}>>> [4/4] Настройка автозапуска при входе...${NC}"
BASHRC="$HOME/.bashrc"
if ! grep -q "server-menu" "$BASHRC"; then
    cat <<EOF >> "$BASHRC"

# --- SERVER MENU AUTOSTART ---
if [[ \$- == *i* ]]; then
    if [ -z "\$SSH_CLIENT" ] || [ -n "\$SSH_TTY" ]; then
        bash /usr/local/bin/server-menu
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
bash /usr/local/bin/server-menu
