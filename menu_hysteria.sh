#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

CONF_PATH="/etc/hysteria/config.yaml"

# Функция получения домена для SNI из URL маскировки
get_sni() {
    local masq=$(grep "url:" $CONF_PATH | awk '{print $2}')
    echo "$masq" | sed -e 's|^[^/]*//||' -e 's|/.*$||'
}

# --- УСТАНОВКА ---
function install_hysteria {
    echo -e "${YELLOW}>>> Установка Hysteria 2...${NC}" 
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${BLUE}--- ПЕРВИЧНАЯ НАСТРОЙКА ---${NC}"
    read -p "Введите UDP порт [443]: " HY_PORT
    HY_PORT=${HY_PORT:-443}
    
    read -p "Имя первого пользователя [admin]: " HY_USER
    HY_USER=${HY_USER:-admin}

    read -p "Пароль [Enter для автогенерации]: " HY_PASS
    HY_PASS=${HY_PASS:-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)}

    read -p "Сайт маскировки [https://www.google.com]: " HY_MASQ
    HY_MASQ=${HY_MASQ:-https://www.google.com}

    mkdir -p /etc/hysteria/
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$(echo $HY_MASQ | sed -e 's|^[^/]*//||' -e 's|/.*$||')" -days 3650 2>/dev/null

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

    ufw allow $HY_PORT/udp
    systemctl enable --now hysteria-server.service
    systemctl restart hysteria-server.service
    echo -e "${GREEN}✅ Hysteria 2 установлена и запущена!${NC}"
}

# --- ИЗМЕНЕНИЕ НАСТРОЕК (Порт и Маскировка) ---
function edit_settings {
    if [ ! -f $CONF_PATH ]; then echo -e "${RED}Сначала установите Hysteria!${NC}"; return; fi

    echo -e "${YELLOW}1) Изменить порт${NC}"
    echo -e "${YELLOW}2) Изменить маскировку (Masquerade)${NC}"
    read -p "Выбор: " set_choice

    case $set_choice in
        1)
            old_port=$(grep "listen:" $CONF_PATH | cut -d: -f3)
            read -p "Новый UDP порт: " new_port
            sed -i "s|listen: :$old_port|listen: :$new_port|" $CONF_PATH
            ufw delete allow $old_port/udp
            ufw allow $new_port/udp
            ;;
        2)
            read -p "Новый URL маскировки (с https://): " new_masq
            sed -i "s|url:.*|url: $new_masq|" $CONF_PATH
            ;;
    esac
    systemctl restart hysteria-server.service
    echo -e "${GREEN}✅ Настройки обновлены.${NC}"
}

# --- УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ (Пароль) ---
function manage_users {
    if [ ! -f $CONF_PATH ]; then echo -e "${RED}Сначала установите Hysteria!${NC}"; return; fi
    
    current_pass=$(grep "password:" $CONF_PATH | awk '{print $2}')
    echo -e "${CYAN}Текущий пароль: ${YELLOW}$current_pass${NC}"
    read -p "Введите новый пароль: " new_pass
    if [ -n "$new_pass" ]; then
        sed -i "s|password:.*|password: $new_pass|" $CONF_PATH
        systemctl restart hysteria-server.service
        echo -e "${GREEN}✅ Пароль изменен.${NC}"
    fi
}

# --- ВЫВОД ДАННЫХ ---
function show_connection {
    if [ ! -f $CONF_PATH ]; then echo -e "${RED}Конфиг не найден!${NC}"; return; fi
    
    local PASS=$(grep "password:" $CONF_PATH | awk '{print $2}')
    local PORT=$(grep "listen:" $CONF_PATH | cut -d: -f3)
    local IP=$(curl -s https://ifconfig.me)
    local SNI=$(get_sni)
    
    local LINK="hysteria2://$PASS@$IP:$PORT/?insecure=1&sni=$SNI#Hysteria2"
    
    echo -e "${GREEN}--- ДАННЫЕ ПОДКЛЮЧЕНИЯ ---${NC}"
    echo -e "IP: ${CYAN}$IP${NC}"
    echo -e "Порт: ${CYAN}$PORT${NC}"
    echo -e "Пароль: ${CYAN}$PASS${NC}"
    echo -e "SNI/Host: ${CYAN}$SNI${NC}"
    echo -e "--------------------------"
    echo -e "${YELLOW}$LINK${NC}"
    echo "--------------------------"
    qrencode -t ansiutf8 "$LINK"
}

# --- УДАЛЕНИЕ ---
function remove_hysteria {
    read -p "Вы точно хотите полностью удалить Hysteria 2? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        bash <(curl -fsSL https://get.hy2.sh/) --uninstall
        rm -rf /etc/hysteria
        echo -e "${GREEN}✅ Сервис и файлы удалены.${NC}"
    fi
}

# --- МЕНЮ ---
while true; do
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}        👻 УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA 2 👻            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    STATUS_HYS=$(systemctl is-active hysteria-server.service 2>/dev/null)
    STATUS_DISPLAY=$(if [ "$STATUS_HYS" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
    
    echo -e "Текущий статус: [${STATUS_DISPLAY}]"
    echo -e "------------------------------------------------------"
    echo -e "1) Установить Hysteria 2"
    echo -e "2) Статус / Запуск / Стоп / Рестарт"
    echo -e "3) Настройка сервера (Порт, Маскировка)"
    echo -e "4) Изменить пароль пользователя"
    echo -e "5) Показать ссылку и QR-код"
    echo -e "6) Удалить Hysteria 2"
    echo -e "X) Назад в главное меню"
    echo -e "------------------------------------------------------"

    read -p "Ваш выбор: " choice
    case $choice in
        1) install_hysteria ;;
        2) manage_service_status_restart hysteria-server.service ;;
        3) edit_settings ;;
        4) manage_users ;;
        5) show_connection; read -p "Enter..." ;;
        6) remove_hysteria ;;
        [Xx]) break ;;
    esac
done
