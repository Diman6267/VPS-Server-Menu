#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

# --- ФУНКЦИЯ УСТАНОВКИ ---
function install_hysteria {
    echo -e "${YELLOW}>>> Установка бинарного файла Hysteria 2...${NC}" 
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${BLUE}--- НАСТРОЙКА КОНФИГУРАЦИИ ---${NC}"
    read -p "Введите UDP порт [443]: " HY_PORT
    HY_PORT=${HY_PORT:-443}
    
    read -p "Введите пароль [или Enter для автогенерации]: " HY_PASS
    HY_PASS=${HY_PASS:-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)}

    read -p "Сайт для маскировки (masquerade) [https://www.bing.com]: " HY_MASQ
    HY_MASQ=${HY_MASQ:-https://www.bing.com}

    # Генерация сертификатов
    mkdir -p /etc/hysteria/
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=bing.com" -days 3650 2>/dev/null

    # Создание конфига
    cat <<EOF > /etc/hysteria/config.yaml
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
    systemctl enable --now hysteria-server.service
    systemctl restart hysteria-server.service
    
    echo -e "${GREEN}✅ Hysteria 2 настроена! Пароль: $HY_PASS, Порт: $HY_PORT, Маскировка: $HY_MASQ${NC}"
}

# --- ФУНКЦИЯ РЕДАКТИРОВАНИЯ MASQUERADE ---
function edit_masquerade {
    if [ ! -f /etc/hysteria/config.yaml ]; then
        echo -e "${RED}❌ Конфиг не найден. Сначала установите Hysteria.${NC}"
        return
    fi

    current_masq=$(grep "url:" /etc/hysteria/config.yaml | awk '{print $2}')
    echo -e "${CYAN}Текущая маскировка: ${YELLOW}$current_masq${NC}"
    read -p "Введите новый URL для маскировки (с https://): " NEW_MASQ
    
    if [ -z "$NEW_MASQ" ]; then
        echo "Отмена."
    else
        sed -i "s|url:.*|url: $NEW_MASQ|" /etc/hysteria/config.yaml
        systemctl restart hysteria-server.service
        echo -e "${GREEN}✅ Маскировка изменена на $NEW_MASQ и сервис перезапущен.${NC}"
    fi
}

# --- ФУНКЦИЯ УДАЛЕНИЯ ---
function remove_hysteria {
    echo -e "${RED}⚠️ Удаление Hysteria 2...${NC}"
    # Официальный деинсталлятор
    bash <(curl -fsSL https://get.hy2.sh/) --uninstall
    # Чистим хвосты
    rm -rf /etc/hysteria
    echo -e "${GREEN}✅ Бинарник, конфиги и сертификаты удалены.${NC}"
}

# --- ОСНОВНОЕ МЕНЮ МОДУЛЯ ---
while true; do
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}        👻 УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA 2 👻            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    STATUS_HYS=$(systemctl is-active hysteria-server.service 2>/dev/null)
    STATUS_DISPLAY=$(if [ "$STATUS_HYS" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
    
    echo -e "${BLUE}Текущий статус: [${STATUS_DISPLAY}]${NC}"
    echo -e "------------------------------------------------------"
    echo -e "1) Установить Hysteria 2 (с нуля)"
    echo -e "2) Статус / Запуск / Стоп / Рестарт"
    echo -e "3) Изменить Masquerade (маскировку)"
    echo -e "4) Показать данные для подключения / QR-код"
    echo -e "5) Удалить Hysteria 2 полностью"
    echo -e "X) Назад в главное меню"
    echo -e "------------------------------------------------------"

    read -p "Ваш выбор: " choice
    case $choice in
        1) install_hysteria ;;
        2) manage_service_status_restart hysteria-server.service ;;
        3) edit_masquerade ;;
        4) 
            # Вывод ссылки и QR (логику берем из инсталла)
            PASS=$(grep "password:" /etc/hysteria/config.yaml | awk '{print $2}')
            PORT=$(grep "listen:" /etc/hysteria/config.yaml | cut -d: -f3)
            IP=$(curl -s https://ifconfig.me)
            LINK="hysteria2://$PASS@$IP:$PORT/?insecure=1&sni=bing.com#Hysteria2"
            echo -e "${YELLOW}Ссылка: ${NC}$LINK"
            qrencode -t ansiutf8 "$LINK"
            read -p "Нажмите Enter..." ;;
        5) remove_hysteria ;;
        [Xx]) break ;;
    esac
done
