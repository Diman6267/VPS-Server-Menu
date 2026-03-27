#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}>>> Начало установки VPS-Server-Menu...${NC}"

# 1. Обновление системы и установка зависимостей (Добавлен ufw)
echo -e "${YELLOW}>>> Установка необходимых пакетов (git, bc, jq, ufw, curl)...${NC}"
sudo apt update
apt install -y software-properties-common
apt update && apt install -y curl git bc jq ufw

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
    rm -rf "$TARGET_DIR"
    git clone https://github.com/Diman6267/VPS-Server-Menu.git "$TARGET_DIR"
fi

# 4. Настройка прав доступа
echo -e "${YELLOW}>>> Установка прав на исполнение...${NC}"
chmod +x "$TARGET_DIR/server-menu"
chmod +x "$TARGET_DIR"/*
chmod +x "$TARGET_DIR"/*.sh 2>/dev/null

# 5. Создание системных ссылок (КРИТИЧЕСКИ ВАЖНО)
echo -e "${YELLOW}>>> Создание системных ссылок для модулей...${NC}"
ln -sf "$TARGET_DIR/server-menu" /usr/local/bin/server-menu
ln -sf "$TARGET_DIR/menu_xui.sh" /usr/local/bin/menu_xui.sh
ln -sf "$TARGET_DIR/menu_hysteria.sh" /usr/local/bin/menu_hysteria.sh
ln -sf "$TARGET_DIR/menu_mtproxy.sh" /usr/local/bin/menu_mtproxy.sh
ln -sf "$TARGET_DIR/menu_tests.sh" /usr/local/bin/menu_tests.sh
ln -sf "$TARGET_DIR/menu_setup.sh" /usr/local/bin/menu_setup.sh
ln -sf "$TARGET_DIR/ipv6-menu" /usr/local/bin/ipv6-menu
    chmod +x "$TARGET_DIR/ipv6-menu"
# 6. Настройка конфигурационного файла (Исправлено дублирование)
if [ -f "$TARGET_DIR/_config_and_utils.sh" ]; then
    # Делаем ссылку вместо копирования, чтобы изменения в репозитории сразу работали
    ln -sf "$TARGET_DIR/_config_and_utils.sh" /usr/local/bin/_config_and_utils.sh
fi
# 7. Настройка автозапуска при входе в систему
echo -e "${YELLOW}>>> Настройка автозапуска меню...${NC}"
if ! grep -q "server-menu" ~/.bashrc; then
    echo -e "\n# Автозапуск основного меню\nif [[ -t 0 ]]; then server-menu; fi" >> ~/.bashrc
    echo -e "${GREEN}✓ Автозапуск добавлен в ~/.bashrc${NC}"
else
    echo -e "${YELLOW}! Автозапуск уже настроен${NC}"
fi
echo -e "${GREEN}======================================================"
echo -e "✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!"
echo -e "------------------------------------------------------"
echo -e "Добавлен пакет: ufw (не забудьте настроить правила)"
echo -e "Запуск меню: ${YELLOW}server-menu${NC}"
echo -e "======================================================${NC}"
