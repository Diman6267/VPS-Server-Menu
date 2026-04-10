#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

# ----------------------------------------------------------------------
# HYSTERIA: УСТАНОВКА / УДАЛЕНИЕ / ПОЛЬЗОВАТЕЛИ (Вынесенный блок)
# ----------------------------------------------------------------------
# Функция для автоматического получения домена из ACME или IP
function get_hy2_domain {
    # Ищем строку после "domains:", убираем лишние пробелы, тире и кавычки
    local DOMAIN=$(grep -A 1 "domains:" "$HYSTERIA_CONFIG" | grep "-" | sed 's/^[[:space:]]*- //;s/\"//g;s/[[:space:]]*$//')
    
    if [[ -z "$DOMAIN" ]]; then
        # Если домен в ACME не найден, берем внешний IP
        DOMAIN=$(curl -s --max-time 2 https://ifconfig.me || echo "your_server_ip")
    fi
    echo "$DOMAIN"
}

# Функция для получения порта
function get_hy2_port {
    local PORT=$(grep "listen:" "$HYSTERIA_CONFIG" | awk -F ':' '{print $NF}' | tr -d ' "')
    echo "${PORT:-8443}"
}
function install_hysteria {
    echo -e "${YELLOW}>>> Установка Hysteria 2...${NC}" 
    bash <(curl -fsSL https://get.hy2.sh/)

    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}       ⚙️  ПЕРВИЧНАЯ НАСТРОЙКА СЕРВЕРА               ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    read -p "Введите UDP порт [8443]: " HY_PORT
    HY_PORT=${HY_PORT:-8443}

    read -p "Сайт для маскировки (по умолчанию yahoo.com) [yahoo.com]: " HY_MASQ_INPUT
    HY_MASQ_INPUT=${HY_MASQ_INPUT:-yahoo.com}
    
    # Очищаем ввод от http://, https:// и слешей на конце (если ввели случайно)
    CLEAN_MASQ=$(echo "$HY_MASQ_INPUT" | sed -E 's~^(https?://)?([^/]+).*~\2~')
    
    # Формируем правильный URL для конфига
    HY_MASQ="https://${CLEAN_MASQ}/"

    echo -e "\n${CYAN}Выберите тип сертификата:${NC}"
    echo "1) Свой домен (авто-выпуск через ACME/Let's Encrypt)"
    echo "2) Самоподписанный (без домена, по IP)"
    read -p "Ваш выбор [1-2]: " CERT_TYPE

    mkdir -p /etc/hysteria/

    # Генерируем конфиг в зависимости от выбора
    if [ "$CERT_TYPE" == "1" ]; then
        read -p "Введите ваш домен (напр. domain.tech): " HY_DOMAIN
        echo -e "${YELLOW}Введите email для ACME (формат: admin@mail.com)${NC}"
read -p "Email [admin@$HY_DOMAIN]: " HY_EMAIL

# Если нажал Enter, создаем почту на базе твоего же домена
if [[ -z "$HY_EMAIL" ]]; then
    HY_EMAIL="admin@$HY_DOMAIN"
fi

# Простейшая проверка на валидность (наличие @ и точки)
if [[ ! "$HY_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo -e "${RED}⚠️ Ошибка: формат email неверный. Использую admin@$HY_DOMAIN${NC}"
    HY_EMAIL="admin@$HY_DOMAIN"
fi
        cat <<EOF > /etc/hysteria/config.yaml
listen: :$HY_PORT
acme:
  domains:
    - $HY_DOMAIN
  email: $HY_EMAIL
  type: http
auth:
  type: userpass
  userpass:
    Admin: "12345678"
masquerade:
  type: proxy
  proxy:
    url: $HY_MASQ
    rewriteHost: true
EOF
    else
        echo -e "${YELLOW}Генерация самоподписанного сертификата...${NC}"
		# Запрашиваем SNI (маскировку)
        read -p "Введите SNI для маскировки [$CLEAN_MASQ]: " HY_SNI
        HY_SNI=${HY_SNI:-$CLEAN_MASQ}
        
        # Генерируем сертификат именно на этот домен
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$HY_SNI" -days 3650 2>/dev/null
        
        # Сохраним SNI в файл, чтобы функция генерации ссылок его видела
        echo "$HY_SNI" > /etc/hysteria/sni.txt
        cat <<EOF > /etc/hysteria/config.yaml
listen: :$HY_PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: userpass
  userpass:
    Admin: "12345678"
masquerade:
  type: proxy
  proxy:
    url: $HY_MASQ
    rewriteHost: true
EOF
    fi
    # Создаем базовый passwords.json для твоего скрипта пользователей
    echo '["12345678"]' > /etc/hysteria/passwords.json
# ВАЖНО: Применяем права доступа для всей папки (для любого типа конфига)
if id "hysteria" &>/dev/null; then
        chown -R hysteria:hysteria /etc/hysteria
        chmod 600 /etc/hysteria/server.key 2>/dev/null
    fi
    # Открываем порт в UFW и запускаем сервис
    if command -v ufw &> /dev/null; then
        ufw allow $HY_PORT/udp >/dev/null 2>&1
    fi
    systemctl enable --now hysteria-server.service
    systemctl restart hysteria-server.service

    echo -e "${GREEN}✅ Установка Hysteria 2 и базовая настройка завершена.${NC}"
    echo -e "${YELLOW}Создан тестовый пользователь: Admin / 12345678${NC}"
    echo -e "Вы можете изменить его в меню управления пользователями."
    read -p "Нажмите Enter для продолжения..."
}

function remove_hysteria {
    local attempts=0
    local confirmed=false

    echo -e "${RED}==================================================${NC}"
    echo -e "${RED}      ⚠️    ОПАСНО: УДАЛЕНИЕ СЛУЖБЫ HYSTERIA 2    ⚠️     ${NC}"
    echo -e "${RED}==================================================${NC}"
    echo -e "${YELLOW}Это действие полностью удалит Hysteria и все ее конфигурационные файлы.${NC}"
    
    while [ $attempts -lt 3 ]; do
        read -p "$(echo -e "${RED}ПОДТВЕРДИТЕ (попытка $((attempts+1))/3). Вы уверены, что хотите удалить Hysteria? [yes/no]: ${NC}")" confirm
        if [[ "$confirm" == "yes" ]]; then
            confirmed=true
            break
        fi
        attempts=$((attempts + 1))
    done

    if [ "$confirmed" = true ]; then
        echo -e "${YELLOW}Запускаю удаление...${NC}"
        
        # Вызываем официальный скрипт удаления
        bash <(curl -fsSL https://get.hy2.sh/) --remove
        
        echo ""
        read -p "$(echo -e "${CYAN}Выполнить автоматическую очистку конфигурации и хвостов (как рекомендует скрипт)? [y/N]: ${NC}")" cleanup_confirm
        if [[ "$cleanup_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Удаление конфигурации и systemd файлов...${NC}"
            rm -rf /etc/hysteria
            userdel -r hysteria 2>/dev/null
            rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service
            rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service
            systemctl daemon-reload
            echo -e "${GREEN}✅ Дополнительная очистка завершена.${NC}"
        else
            echo -e "${YELLOW}Дополнительная очистка пропущена.${NC}"
        fi

        echo -e "${GREEN}✅ Hysteria 2 успешно удалена.${NC}"
        read -p "Нажмите Enter для продолжения..."
    fi
}

# Функция для безопасного URL-кодирования спецсимволов
function urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

function display_single_hysteria_uri {
    local username=$1
    local password=$2

    # 1. Пытаемся вытащить домен из блока acme
    local DOMAIN=$(grep -A 1 "domains:" "$HYSTERIA_CONFIG" | grep "-" | sed 's/^[[:space:]]*- //;s/\"//g' | tr -d '\r')
    
    # 2. Достаем порт из конфига
    local PORT=$(grep "listen:" "$HYSTERIA_CONFIG" | awk -F ':' '{print $NF}' | tr -d ' "')
    PORT=${PORT:-8443}

    local FINAL_ADDR
    local PARAMS

    if [[ -n "$DOMAIN" ]]; then
        # РЕЖИМ ACME (Домен)
        FINAL_ADDR="$DOMAIN"
        PARAMS="sni=$DOMAIN"
    else
        # РЕЖИМ САМОПОДПИСАННЫЙ (IP)
        FINAL_ADDR=$(curl -s --max-time 2 https://ifconfig.me)
        PARAMS="insecure=1&sni=$HY_SNI"
    fi

    # Кодируем пользователя и пароль для безопасности URI
    local safe_username=$(urlencode "$username")
    local safe_password=$(urlencode "$password")

    # Сборка финальной ссылки с безопасными значениями
    local HY_URI="hysteria2://${safe_username}:${safe_password}@${FINAL_ADDR}:${PORT}/?${PARAMS}"

    echo -e "\n${CYAN}==================================================${NC}"
    echo -e "${GREEN}✅ ССЫЛКА HYSTERIA 2 ДЛЯ $username:${NC}"
    
    if command -v qrencode &> /dev/null; then
        echo -e "\n>>> QR-код:"
        qrencode -t ANSI256 "$HY_URI"
    else
        echo -e "${RED}❌ qrencode не установлен. Установите: apt install qrencode${NC}"
    fi

    echo -e "--------------------------------------------------"
    echo -e "${BLUE}🔗 ССЫЛКА (скопируйте):${NC}"
    echo -e "${YELLOW}$HY_URI${NC}"
    echo -e "${CYAN}==================================================${NC}\n"
}

function generate_hysteria_uri {
    USERS=$(awk '/userpass:/ {p=1; next} /masquerade:/ {p=0} p && /^[[:space:]]{4}.*:/' "$HYSTERIA_CONFIG" | sed -e 's/^[ \t]*//' -e 's/"//g' -e 's/:.*//')
    
    if [[ -z "$USERS" ]]; then
        echo -e "${RED}❌ В конфиге нет активных пользователей.${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    clear
    echo -e "${CYAN}==================================================${NC}"
    echo -e "${CYAN}          🔗 СОЗДАНИЕ ССЫЛКИ HYSTERIA 2 🔗           ${NC}"
    echo -e "${CYAN}==================================================${NC}"
    
    USER_ARRAY=($USERS)
    for i in "${!USER_ARRAY[@]}"; do
        echo -e "    $((i+1))) ${USER_ARRAY[i]}"
    done
    
    read -p "Выберите номер пользователя [1-${#USER_ARRAY[@]}]: " USER_INDEX
    
    if [[ "$USER_INDEX" -gt 0 && "$USER_INDEX" -le "${#USER_ARRAY[@]}" ]]; then
        SELECTED_USER="${USER_ARRAY[$((USER_INDEX-1))]}"
        USER_PASS=$(grep "$SELECTED_USER:" "$HYSTERIA_CONFIG" | sed -e 's/.*: //g' -e 's/"//g')
        if [[ -z "$USER_PASS" ]]; then
            echo -e "${RED}❌ Не удалось найти пароль.${NC}"
            return
        fi
        display_single_hysteria_uri "$SELECTED_USER" "$USER_PASS"
    else
        echo -e "${RED}❌ Неверный номер.${NC}"
    fi
}

function manage_hysteria_users {
    if [ ! -f "$HYSTERIA_CONFIG" ]; then
        echo -e "${RED}❌ Ошибка: Конфиг не найден ($HYSTERIA_CONFIG)${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    while true; do
        clear
        echo -e "${CYAN}==================================================${NC}"
        echo -e "${CYAN}       👥 УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ HYSTERIA 2     ${NC}"
        echo -e "${CYAN}==================================================${NC}"

        echo -e "${BLUE}ТЕКУЩИЕ ПОЛЬЗОВАТЕЛИ:${NC}"
        USERS_RAW=$(awk '/userpass:/ {p=1; next} /masquerade:/ {p=0} p && /^[[:space:]]{4}.*:/' "$HYSTERIA_CONFIG")
        
        if [ -z "$USERS_RAW" ]; then
            echo -e "    -> ${YELLOW}Нет активных пользователей.${NC}"
        fi

        echo "$USERS_RAW" | while read -r line; do
            CLEAN_LINE=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/"//g' -e 's/: /:/')
            echo -e "    -> $CLEAN_LINE"
        done
        echo -e "${BLUE}--------------------------------------------------${NC}"

        echo -e "${YELLOW}    1) ➕  Добавить нового пользователя${NC}"
        echo -e "${RED}    2) ❌  Удалить пользователя${NC}"
        echo -e "${GREEN}    3) 🔗  Создать ссылку Hysteria (URI) ${NC}"
        echo -e "${RED}    X) 🔙  Назад в меню Hysteria${NC}"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        
        read -p "Ваш выбор [1-3, X]: " choice

        case $choice in
            1)
                read -p "Введите имя пользователя (Символы @, : и кавычки запрещены): " NEW_USER
				# Запрещаем @, : и кавычки
				if [[ "$NEW_USER" =~ [@:\"] || -z "$NEW_USER" ]]; then
					echo -e "${RED}❌ Некорректное имя. Символы @, : и кавычки запрещены.${NC}"
					break
				fi
                read -p "Сгенерировать пароль? [Y/n]: " GENERATE_PASS
              
                if [[ "$GENERATE_PASS" =~ ^[Yy]$ || -z "$GENERATE_PASS" ]]; then
                    NEW_PASS=$(openssl rand -hex 8)
                    echo -e "${GREEN}Пароль: $NEW_PASS${NC}"
                else
                    read -p "Введите пароль (Символы @, : и кавычки запрещены.): " NEW_PASS
					# Проверка ручного ввода пароля на запрещенные символы
				if [[ "$NEW_PASS" =~ [@:\"] ]]; then
					echo -e "${RED}❌ Некорректный пароль. Символы @, : и кавычки запрещены.${NC}"
					break
				fi
               fi
				

                if [[ -z "$NEW_PASS" ]]; then echo -e "${RED}❌ Пароль пуст.${NC}"; break; fi

                sudo sed -i "/[[:space:]]*userpass:/a \    $NEW_USER: \"$NEW_PASS\"" "$HYSTERIA_CONFIG"
                echo -e "${GREEN}✅ Пользователь $NEW_USER добавлен.${NC}"
                display_single_hysteria_uri "$NEW_USER" "$NEW_PASS"
                restart_hysteria
          
                ;;

            2)
                USERS=$(awk '/userpass:/ {p=1; next} /masquerade:/ {p=0} p && /^    .*:/' "$HYSTERIA_CONFIG" | sed -e 's/^[ \t]*//' -e 's/"//g' -e 's/:.*//')
                if [[ -z "$USERS" ]]; then echo -e "${RED}❌ Нет пользователей.${NC}"; break; fi
                
                echo -e "\n${YELLOW}Выберите пользователя для удаления:${NC}"
                USER_ARRAY=($USERS)
                for i in "${!USER_ARRAY[@]}"; do echo -e "    $((i+1))) ${USER_ARRAY[i]}"; done
                
                read -p "Номер [1-${#USER_ARRAY[@]}]: " USER_INDEX
       
                if [[ "$USER_INDEX" -gt 0 && "$USER_INDEX" -le "${#USER_ARRAY[@]}" ]]; then
                    DEL_USER="${USER_ARRAY[$((USER_INDEX-1))]}"
                    sudo sed -i "/^[[:space:]]*$DEL_USER:/d" "$HYSTERIA_CONFIG"
                    echo -e "${RED}✅ Пользователь $DEL_USER удален.${NC}"
            
                    restart_hysteria
                else
                    echo -e "${RED}❌ Неверный номер.${NC}"
                fi
                ;;
            3) generate_hysteria_uri ;;
            [Xx]) return ;;
            *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
        esac
        read -p "Нажмите Enter для продолжения..."
    done
}

function manage_hysteria_service {
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}        🎭 УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA 2 🎭            ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        
        STATUS_HYS=$(get_service_status $HYSTERIA_SERVICE)
        
        STATUS_DISPLAY=$(if [ "$STATUS_HYS" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
        echo -e "${BLUE}Текущий статус: [${STATUS_DISPLAY}]${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"

        echo -e "${GREEN}1) 📥  Установить Hysteria 2${NC}"
        echo -e "${YELLOW}2) 🚥  Статус / Запустить / Остановить / Перезапустить сервис${NC}"
        echo -e "${CYAN}3) 👥  Управление пользователями${NC}"
        echo -e "${RED}4) 🗑️  Удалить Hysteria 2${NC}"
        echo -e "${RED}X) 🔙  Назад в главное меню${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
    
        read -p "Ваш выбор [1-4, X]: " choice
        echo ""

        case $choice in
            1) install_hysteria ;;
            2) manage_service_status_restart $HYSTERIA_SERVICE ;;
            3) manage_hysteria_users ;;
            4) remove_hysteria ;;
            [Xx]) return ;;
            *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
        esac
        read -p "Нажмите Enter для продолжения..."
    done
}
manage_hysteria_service
