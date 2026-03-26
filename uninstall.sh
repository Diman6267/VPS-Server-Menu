#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}>>> Начинаю удаление VPS-Server-Menu...${NC}"

# 1. Удаление символических ссылок из /usr/local/bin
echo -e "${YELLOW}>>> Удаление системных ссылок...${NC}"
[ -L /usr/local/bin/server-menu ] && rm /usr/local/bin/server-menu && echo -e "${GREEN}✓ Ссылка server-menu удалена${NC}"
[ -L /usr/local/bin/ipv6-menu ] && rm /usr/local/bin/ipv6-menu && echo -e "${GREEN}✓ Ссылка ipv6-menu удалена${NC}"

# 2. Удаление конфигурационных файлов
echo -e "${YELLOW}>>> Удаление вспомогательных файлов...${NC}"
[ -f /usr/local/bin/_config_and_utils.sh ] && rm /usr/local/bin/_config_and_utils.sh && echo -e "${GREEN}✓ _config_and_utils.sh удален${NC}"

# 3. Удаление основной директории репозитория
TARGET_DIR="/root/VPS-Server-Menu"
if [ -d "$TARGET_DIR" ]; then
    read -p "Удалить папку репозитория $TARGET_DIR со всеми скриптами? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        rm -rf "$TARGET_DIR"
        echo -e "${GREEN}✓ Директория $TARGET_DIR полностью удалена${NC}"
    else
        echo -e "${YELLOW}! Директория сохранена${NC}"
    fi
fi

echo -e "${GREEN}======================================================"
echo -e "✅ УДАЛЕНИЕ ЗАВЕРШЕНО"
echo -e "------------------------------------------------------"
echo -e "Система очищена от скриптов меню."
echo -e "======================================================${NC}"
