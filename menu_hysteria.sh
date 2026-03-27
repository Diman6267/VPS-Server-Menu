#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

HYSTERIA_SERVICE="hysteria-server.service"
CONF_PATH="/etc/hysteria/config.yaml"

# Функция для вырезания SNI из URL маскировки
get_sni() {
    local masq=$(grep "url:" $CONF_PATH | awk '{print $2}')
    echo "$masq" | sed -e 's|^[^/]*//||' -e 's|/.*$||'
}

# --- 1. УСТАНОВКА С НАСТРОЙКОЙ ---
function install_hysteria {
    echo -e "${YELLOW}>>> Запуск установки Hysteria 2...${NC}" 
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${BLUE}--- ПЕРВОНАЧАЛЬНАЯ НАСТРОЙКА ---${NC}"
    read -p "Введите UDP порт [443]: " HY_PORT
    HY_PORT=${HY_PORT:-443}
    
    read -p "Введите пароль [или Enter для автогенерации]: " HY_PASS
    HY_PASS=${HY_PASS:-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)}

    read -p "Сайт маскировки [https://www.google.com]: " HY_MASQ
    HY_MASQ=${HY_MASQ:-https://www.google.com}

    # Подготовка папок и сертификатов
    mkdir -p /etc/hysteria/
    local SNI_AUTO=$(echo "$HY_MASQ" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$SNI_AUTO" -days 3650 2>/dev/null

    # Создание конфига
    cat <<EOF > $CONF_PATH
listen: :$HY_PORT
auth:
  type: password
  password: $HY_PASS
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
masquerade:
  type: proxy
  proxy:
    url: $HY_MASQ
    rewriteHost: true
EOF

    # UFW и запуск
    ufw allow $HY_PORT/udp
    systemctl enable --now $HY_SERVICE
    systemctl restart $HY_SERVICE

    echo -e "${GREEN}✅ Установка и настройка завершена!${NC}"
    echo -e "${YELLOW}Порт: $HY_PORT, Пароль: $HY_PASS${NC}"
    read -p "Нажмите Enter для продолжения..."
}

# --- 2. ИЗМЕНЕНИЕ НАСТРОЕК СЕРВЕРА ---
function edit_server_settings {
    if [ ! -f $CONF_PATH ]; then echo -e "${RED}Ошибка: Сервис не установлен.${NC}"; read; return; fi

    echo -e "${CYAN}Что изменить?${NC}"
    echo "1) Порт"
    echo "2) Маскировку (Masquerade)"
    read -p "Ваш выбор: " edit_choice

    case $edit_choice in
        1)
            old_port=$(grep "listen:" $CONF_PATH | cut -d: -f3)
            read -p "Новый UDP порт: " new_port
            sed -i "s|listen: :$old_port|listen: :$new_port|" $CONF_PATH
            ufw delete allow $old_port/udp
            ufw allow $new_port/udp
            echo -e "${GREEN}Порт изменен.${NC}"
            ;;
        2)
            read -p "Новый URL маскировки (напр. https://www.microsoft.com): " new_masq
            sed -i "s|url:.*|url: $new_masq|" $CONF_PATH
            echo -e "${GREEN}Маскировка изменена.${NC}"
            ;;
    esac
    systemctl restart $HY_SERVICE
    read -p "Настройки применены. Нажмите Enter..."
}

# --- 3. ВЫВОД ДАННЫХ И QR ---
function show_connection_info {
    if [ ! -f $CONF_PATH ]; then echo -e "${RED}Конфиг не найден.${NC}"; read; return; fi
    
    local PASS=$(grep "password:" $CONF_PATH | awk '{print $2}')
    local PORT=$(grep "listen:" $CONF_PATH | cut -d: -f3)
    local IP=$(curl -s https://ifconfig.me)
    local SNI=$(get_sni)
    
    local LINK="hysteria2://$PASS@$IP:$PORT/?insecure=1&sni=$SNI#Hysteria2"
    
    echo -e "${GREEN}--- ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ ---${NC}"
    echo -e "Ссылка: ${YELLOW}$LINK${NC}"
    echo "------------------------------------------------------"
    qrencode -t ansiutf8 "$LINK"
    echo "------------------------------------------------------"
    read -p "Нажмите Enter..."
}

# --- 4. УДАЛЕНИЕ ---
function remove_hysteria {
    read -p "Вы точно хотите удалить Hysteria 2? [yes/no]: " confirm
    if [[ "$confirm" == "yes" ]]; then
        bash <(curl -fsSL https://get.hy2.sh/) --uninstall
        rm -rf /etc/hysteria
        echo -e "${GREEN}✅ Сервис и все конфиги удалены.${NC}"
    else
        echo "Отмена удаления."
    fi
    read -p "Нажмите Enter..."
}

# --- ГЛАВНОЕ МЕНЮ ---
while true; do
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}        👻 УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA 2 👻            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    STATUS_HYS=$(systemctl is-active $HYSTERIA_SERVICE 2>/dev/null)
    STATUS_DISPLAY=$(if [ "$STATUS_HYS" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
    
    echo -e "${BLUE}Текущий статус: [${STATUS_DISPLAY}]${NC}"
    echo -e "------------------------------------------------------"
    echo -e "1) Установить Hysteria 2 (с настройкой)"
    echo -e "2) Статус / Запуск / Стоп / Рестарт"
    echo -e "3) Управление пользователями (пароли)"
    echo -e "4) Настройки сервера (Порт, Маскировка)"
    echo -e "5) Показать ссылку и QR-код"
    echo -e "6) Удалить Hysteria 2"
    echo -e "X) Назад в главное меню"
    echo -e "------------------------------------------------------"

    read -p "Ваш выбор [1-6, X]: " choice
    case $choice in
        1) install_hysteria ;;
        2) manage_service_status_restart $HYSTERIA_SERVICE ;;
        3) # Используем твою логику управления пользователями (пункт 3)
           # Если хочешь оставить именно ту функцию, убедись что она есть в файле
           manage_hysteria_users ;; 
        4) edit_server_settings ;;
        5) show_connection_info ;;
        6) remove_hysteria ;;
        [Xx]) break ;;
    esac
done
