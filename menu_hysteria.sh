#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

HYSTERIA_SERVICE="hysteria-server.service"
CONF_PATH="/etc/hysteria/config.yaml"

# --- ПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---
function wait_key {
    echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
    read -r
}

# --- 1. ИНТЕРАКТИВНАЯ УСТАНОВКА ---
function install_hysteria {
    echo -e "${YELLOW}>>> Запуск установки Hysteria 2...${NC}"
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}       ⚙️  НАСТРОЙКА ПАРАМЕТРОВ СЕРВЕРА               ${NC}"
    echo -e "${BLUE}======================================================${NC}"

    # Порт
    read -p "Введите UDP порт [8443]: " HY_PORT
    HY_PORT=${HY_PORT:-8443}

    # Маскировка
    read -p "URL маскировки [https://yahoo.com/]: " HY_MASQ
    HY_MASQ=${HY_MASQ:-https://yahoo.com/}

    # Выбор сертификата
    echo -e "\n${CYAN}Выберите тип сертификата:${NC}"
    echo "1) Свой домен (авто-выпуск через ACME/Let's Encrypt)"
    echo "2) Самоподписанный (без домена, для IP)$"
    read -p "Ваш выбор [1-2]: " CERT_TYPE

    # Первичный пользователь
    read -p "Имя первого пользователя [Admin]: " FIRST_USER
    FIRST_USER=${FIRST_USER:-Admin}
    FIRST_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)

    mkdir -p /etc/hysteria/

    if [ "$CERT_TYPE" == "1" ]; then
        read -p "Введите ваш домен (напр. domain.com): " HY_DOMAIN
        read -p "Введите email для ACME: " HY_EMAIL
        
        cat <<EOF > $CONF_PATH
listen: :$HY_PORT
acme:
  domains:
    - $HY_DOMAIN
  email: $HY_EMAIL
auth:
  type: userpass
  userpass:
    $FIRST_USER: "$FIRST_PASS"
masquerade:
  type: proxy
  proxy:
    url: $HY_MASQ
    rewriteHost: true
EOF
    else
        echo -e "${YELLOW}>>> Генерация самоподписанного сертификата...${NC}"
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=bing.com" -days 3650 2>/dev/null
        cat <<EOF > $CONF_PATH
listen: :$HY_PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: userpass
  userpass:
    $FIRST_USER: "$FIRST_PASS"
masquerade:
  type: proxy
  proxy:
    url: $HY_MASQ
    rewriteHost: true
EOF
    fi

    # Открываем порт в UFW и запускаем
    ufw allow $HY_PORT/udp
    systemctl enable --now $HY_SERVICE
    systemctl restart $HY_SERVICE

    echo -e "${GREEN}✅ Hysteria 2 установлена и настроена!${NC}"
    echo -e "Пользователь: ${CYAN}$FIRST_USER${NC}, Пароль: ${CYAN}$FIRST_PASS${NC}"
    wait_key
}

# --- 2. УПРАВЛЕНИЕ СЕРВИСОМ (С ПАУЗОЙ) ---
function manage_service {
    while true; do
        clear
        echo -e "${CYAN}--- УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA ---${NC}"
        systemctl status $HY_SERVICE --no-pager
        echo -e "------------------------------------"
        echo "1) Запустить"
        echo "2) Остановить"
        echo "3) Перезагрузить"
        echo "X) Назад"
        read -p "Выбор: " s_choice
        case $s_choice in
            1) systemctl start $HY_SERVICE ;;
            2) systemctl stop $HY_SERVICE ;;
            3) systemctl restart $HY_SERVICE ;;
            [Xx]) break ;;
        esac
        echo -e "${GREEN}Готово.${NC}"
        wait_key
    done
}

# --- 3. УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ (Твоя рабочая логика) ---
# Здесь остается твой функционал работы с config.yaml и passwords.json
function manage_hysteria_users {
    # Сохраняем твою функцию полностью, как она была в рабочем скрипте
    # (для краткости здесь вызов, в файле на GitHub оставь свое тело функции)
    echo -e "${YELLOW}Запуск управления пользователями...${NC}"
    # Твоя логика редактирования YAML через sed или python3
    # ...
    wait_key
}

# --- 4. УДАЛЕНИЕ ---
function remove_hysteria {
    echo -e "${RED}!!! ВНИМАНИЕ: УДАЛЕНИЕ HYSTERIA 2 !!!${NC}"
    read -p "Вы уверены? [yes/no]: " confirm
    if [ "$confirm" == "yes" ]; then
        systemctl stop $HY_SERVICE
        systemctl disable $HY_SERVICE
        bash <(curl -fsSL https://get.hy2.sh/) --uninstall
        rm -rf /etc/hysteria
        echo -e "${GREEN}✅ Сервис и файлы конфигурации удалены.${NC}"
    else
        echo "Отмена."
    fi
    wait_key
}

# --- 5. ВЫВОД ДАННЫХ ДЛЯ ПОДКЛЮЧЕНИЯ ---
function show_config_info {
    if [ ! -f $CONF_PATH ]; then echo -e "${RED}Конфиг не найден!${NC}"; wait_key; return; fi

    local PORT=$(grep "listen:" $CONF_PATH | cut -d: -f3)
    local IP=$(curl -s https://ifconfig.me)
    # Ищем первого попавшегося пользователя
    local USER_DATA=$(grep -A 1 "userpass:" $CONF_PATH | tail -n 1)
    local USERNAME=$(echo "$USER_DATA" | awk -F: '{print $1}' | tr -d ' ')
    local PASSWORD=$(echo "$USER_DATA" | awk -F'"' '{print $2}')
    
    # Определяем SNI (из домена или маскировки)
    local SNI=$(grep "domains:" -A 1 $CONF_PATH | tail -n 1 | tr -d ' -' || grep "url:" $CONF_PATH | awk '{print $2}' | sed -e 's|^[^/]*//||' -e 's|/.*$||')

    local LINK="hysteria2://$PASSWORD@$IP:$PORT/?sni=$SNI&insecure=1#Hysteria2_$USERNAME"

    echo -e "${GREEN}--- ДАННЫЕ ПОДКЛЮЧЕНИЯ ---${NC}"
    echo -e "Ссылка: ${YELLOW}$LINK${NC}"
    echo "------------------------------------------------------"
    qrencode -t ansiutf8 "$LINK"
    wait_key
}

# --- ГЛАВНОЕ МЕНЮ (Твой стиль) ---
while true; do
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}        👻 УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA 2 👻            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    STATUS_HYS=$(systemctl is-active $HY_SERVICE 2>/dev/null)
    STATUS_DISPLAY=$(if [ "$STATUS_HYS" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
    
    echo -e "${BLUE}Текущий статус: [${STATUS_DISPLAY}]${NC}"
    echo -e "------------------------------------------------------"
    echo -e "${GREEN}1) Установить Hysteria 2 (Интерактивно)${NC}"
    echo -e "${YELLOW}2) Управление сервисом (Старт/Стоп/Статус)${NC}"
    echo -e "${CYAN}3) Управление пользователями${NC}"
    echo -e "${PURPLE}4) Показать QR-код и ссылку${NC}"
    echo -e "${RED}5) Удалить Hysteria 2 полностью${NC}"
    echo -e "X) Назад в главное меню"
    echo -e "------------------------------------------------------"

    read -p "Ваш выбор: " choice
    case $choice in
        1) install_hysteria ;;
        2) manage_service ;;
        3) manage_hysteria_users ;;
        4) show_config_info ;;
        5) remove_hysteria ;;
        [Xx]) break ;;
    esac
done
