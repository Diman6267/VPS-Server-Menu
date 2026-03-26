#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}>>> Начало установки VPS-Server-Menu...${NC}"

# 1. Обновление системы и установка зависимостей
echo -e "${YELLOW}>>> Установка необходимых пакетов (git, bc, jq)...${NC}"
apt update && apt install -y git bc jq curl

# 2. Определяем рабочую директорию
TARGET_DIR="/root/VPS-Server-Menu"

# 3. Клонирование или обновление репозитория
if [ -d "$TARGET_DIR/.git" ]; then
    echo -e "${YELLOW}>>> Репозиторий уже существует. Обновляем...${NC}"
    cd "$TARGET_DIR" || exit
    git fetch origin main
    git reset --hard origin/main
else
    echo -e "${YELLOW}>>> Клонирование репозитория...${NC}"
    rm -rf "$TARGET_DIR" # Удаляем папку, если она была создана не через git
    git clone https://github.com/Diman6267/VPS-Server-Menu.git "$TARGET_DIR"
fi

# 4. Настройка прав доступа
echo -e "${YELLOW}>>> Установка прав на исполнение...${NC}"
chmod +x "$TARGET_DIR/server-menu"
chmod +x "$TARGET_DIR"/*.sh 2>/dev/null

# 5. Создание символической ссылки (КРИТИЧЕСКИ ВАЖНО)
# Теперь /usr/local/bin/server-menu всегда будет указывать на файл в репозитории
echo -e "${YELLOW}>>> Создание системной ссылки /usr/local/bin/server-menu...${NC}"
ln -sf "$TARGET_DIR/server-menu" /usr/local/bin/server-menu

# Дополнительно прописываем ссылки для модулей, если они вызываются напрямую
# Например, для IPv6 меню
if [ -f "$TARGET_DIR/ipv6-menu" ]; then
    ln -sf "$TARGET_DIR/ipv6-menu" /usr/local/bin/ipv6-menu
    chmod +x /usr/local/bin/ipv6-menu
fi

# 6. Копирование конфигов (если есть файл _config_and_utils.sh)
if [ -f "$TARGET_DIR/_config_and_utils.sh" ]; then
    cp "$TARGET_DIR/_config_and_utils.sh" /usr/local/bin/_config_and_utils.sh
    chmod +x /usr/local/bin/_config_and_utils.sh
fi

echo -e "${GREEN}======================================================"
echo -e "✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!"
echo -e "------------------------------------------------------"
echo -e "Теперь вы можете запустить меню командой: ${YELLOW}server-menu${NC}"
echo -e "======================================================${NC}"
