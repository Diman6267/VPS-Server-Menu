#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

# ----------------------------------------------------------------------
# HYSTERIA: УСТАНОВКА / УДАЛЕНИЕ / ПОЛЬЗОВАТЕЛИ (Вынесенный блок)
# ----------------------------------------------------------------------

function install_hysteria {
    echo -e "${YELLOW}>>> Установка Hysteria 2...${NC}" 
    bash <(curl -fsSL https://get.hy2.sh/)
    echo -e "${GREEN}✅ Установка Hysteria 2 завершена.${NC}"
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
        bash <(curl -fsSL https://get.hy2.sh/) --remove
        echo -e "${GREEN}✅ Hysteria 2 успешно удалена.${NC}"
    else
        echo -e "${GREEN}Операция отменена. Служба Hysteria не была удалена.${NC}"
    fi
}

function display_single_hysteria_uri {
    SELECTED_USER=$1
    USER_PASS=$2

    SERVER_PORT=$(grep '^listen:' "$HYSTERIA_CONFIG" | awk '{print $NF}' | sed 's/:/ /g' | awk '{print $NF}')
    SERVER_PORT=${SERVER_PORT:-8443}
    SERVER_ADDR=$(grep -A 1 'domains:' "$HYSTERIA_CONFIG" | tail -n 1 | sed -e 's/^[[:space:]]*//' -e 's/- //')
    SERVER_ADDR=${SERVER_ADDR:-<IP или Домен>}
    SNI_HOST=$SERVER_ADDR
    
    if [ "$SERVER_ADDR" == "<IP или Домен>" ]; then
        echo -e "${RED}❌ ВНИМАНИЕ: Не удалось автоматически найти домен в конфиге.${NC}"
    fi

    HYSTERIA_URI="hysteria2://$SELECTED_USER:$USER_PASS@$SERVER_ADDR:$SERVER_PORT/?sni=$SNI_HOST"
    
    echo -e "\n${GREEN}==================================================${NC}"
    echo -e "${GREEN}✅ ССЫЛКА HYSTERIA 2 ДЛЯ $SELECTED_USER:${NC}"
    
    # ИСПРАВЛЕНИЕ: Проверка и установка qrencode
    if check_and_install_qrencode; then 
        echo -e "\n${CYAN}>>> QR-код:${NC}"
        echo "$HYSTERIA_URI" | qrencode -t UTF8
        echo -e "${CYAN}--------------------------------------------------${NC}"
    else
        echo -e "${YELLOW}💡 QR-код не будет отображен.${NC}"
    fi
    # -----------------------------------------------
    
    echo -e "${CYAN}🔗 ССЫЛКА (скопируйте):${NC}"
    echo -e "$HYSTERIA_URI"
    echo -e "${GREEN}==================================================${NC}"
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

        echo -e "${YELLOW}    1) Добавить нового пользователя${NC}"
        echo -e "${RED}    2) Удалить пользователя${NC}"
        echo -e "${GREEN}    3) Создать ссылку Hysteria (URI) ${NC}"
        echo -e "${RED}    X) Назад в меню Hysteria${NC}"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        
        read -p "Ваш выбор [1-3, X]: " choice

        case $choice in
            1)
                read -p "Введите имя пользователя: " NEW_USER
                if [[ "$NEW_USER" =~ [:\"] || -z "$NEW_USER" ]]; then
                    echo -e "${RED}❌ Некорректное имя пользователя.${NC}"
                    break
                fi
                read -p "Сгенерировать пароль? [Y/n]: " GENERATE_PASS
              
                if [[ "$GENERATE_PASS" =~ ^[Yy]$ || -z "$GENERATE_PASS" ]]; then
                    NEW_PASS=$(openssl rand -hex 8)
                    echo -e "${GREEN}Пароль: $NEW_PASS${NC}"
                else
                    read -p "Введите пароль: " NEW_PASS
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
        echo -e "${CYAN}        👻 УПРАВЛЕНИЕ СЕРВИСОМ HYSTERIA 2 👻            ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        
        STATUS_HYS=$(get_service_status $HYSTERIA_SERVICE)
        
        STATUS_DISPLAY=$(if [ "$STATUS_HYS" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
        echo -e "${BLUE}Текущий статус: [${STATUS_DISPLAY}]${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"

        echo -e "${GREEN}1) Установить Hysteria 2${NC}"
        echo -e "${YELLOW}2) Статус / Запустить / Остановить / Перезапустить сервис${NC}"
        echo -e "${CYAN}3) Управление пользователями${NC}"
        echo -e "${RED}4) Удалить Hysteria 2${NC}"
        echo -e "${RED}X) Назад в главное меню${NC}"
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
