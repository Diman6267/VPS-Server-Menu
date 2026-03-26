#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
CONFIG_FILE="/etc/server-menu/mtproxy.conf"
# Пытаемся получить IP сервера автоматически
SERVER_IP=$(curl -s icanhazip.com)
[ -z "$SERVER_IP" ] && SERVER_IP="185.223.169.56"

sudo mkdir -p /etc/server-menu
[ ! -f "$USER_DB" ] && sudo touch $USER_DB

function load_config {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        MTP_PORT="8448"
        MTP_TAG="386fa80854214cc50f61914065327bfd"
    fi
}

function sync_mtp {
    load_config
    local secrets=$(awk -F'|' '{print $2}' $USER_DB | paste -sd "," -)
    echo -e "${YELLOW}🔄 Синхронизация Docker...${NC}"
    sudo docker stop mtproto-proxy &>/dev/null
    sudo docker rm mtproto-proxy &>/dev/null
    if [ -n "$secrets" ]; then
        sudo docker run -d --name mtproto-proxy --restart always \
            -p $MTP_PORT:443 -p 8888:8888 \
            -e SECRET="$secrets" -e TAG="$MTP_TAG" \
            telegrammessenger/proxy:latest &>/dev/null
        echo -e "${GREEN}✅ Контейнер обновлен!${NC}"
    else
        echo -e "${RED}⚠️ Нет ключей. Прокси остановлен.${NC}"
    fi
}

function show_user_info {
    local name=$1
    local key=$2
    local link="tg://proxy?server=$SERVER_IP&port=$MTP_PORT&secret=dd$key"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "${YELLOW}👤 Пользователь:${NC} ${GREEN}$name${NC}"
    echo -e "${YELLOW}🔗 Ссылка:${NC} ${CYAN}$link${NC}"
    qrencode -t ANSIUTF8 "$link"
}

function draw_header {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}             🛡️  УПРАВЛЕНИЕ MTPROTO PROXY 🛡️            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
}

while true; do
    draw_header
    load_config
    echo -e "${BLUE}--- ПОЛЬЗОВАТЕЛИ -------------------------------------${NC}"
    echo -e "${YELLOW}1) ➕ Добавить пользователей (одного или нескольких)${NC}"
    echo -e "${YELLOW}2) 📋 Список всех пользователей и QR-коды${NC}"
    echo -e "${RED}3) ❌ Удалить пользователей (выбор нескольких)${NC}"
    echo -e "${BLUE}--- СЕРВИС -------------------------------------------${NC}"
    echo -e "${GREEN}4) 🚀 Установка / Переустановка (Порт/Тег)${NC}"
    echo -e "${RED}5) 🗑️  Полное удаление прокси${NC}"
    echo -e "${CYAN}X) 🔙 Назад${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    read -p "$(echo -e ${CYAN}"Ваш выбор: "${NC})" sub
    
    case $sub in
        1)
            draw_header
            read -p "Сколько пользователей добавить? " ucount
            [[ ! "$ucount" =~ ^[0-9]+$ ]] && ucount=1
            
            new_users_list=()
            for (( i=1; i<=ucount; i++ )); do
                echo -e "${YELLOW}Введите имя для пользователя #$i:${NC}"
                read -p "> " uname
                [ -z "$uname" ] && uname="User_$RANDOM"
                
                usecret=$(head -c 16 /dev/urandom | xxd -ps)
                echo "$uname|$usecret" | sudo tee -a $USER_DB > /dev/null
                new_users_list+=("$uname|$usecret")
            done
            
            sync_mtp
            
            draw_header
            echo -e "${GREEN}✨ НОВЫЕ ПОЛЬЗОВАТЕЛИ ДОБАВЛЕНЫ:${NC}"
            for entry in "${new_users_list[@]}"; do
                IFS='|' read -r n k <<< "$entry"
                show_user_info "$n" "$k"
            done
            read -p "Нажмите Enter для продолжения..."
            ;;
            
        2)
            if ! command -v qrencode &> /dev/null; then sudo apt-get install qrencode -y &>/dev/null; fi
            draw_header
            [ ! -s "$USER_DB" ] && echo -e "${RED}Список пуст!${NC}"
            while IFS='|' read -r name key; do
                show_user_info "$name" "$key"
            done < $USER_DB
            read -p "Enter..."
            ;;
            
        3)
            draw_header
            mapfile -t users < $USER_DB
            if [ ${#users[@]} -eq 0 ]; then echo -e "${RED}Список пуст!${NC}"; sleep 2; continue; fi
            
            for i in "${!users[@]}"; do
                echo -e "${CYAN}$((i+1)))${NC} ${users[$i]%%|*}"
            done
            echo -e "${YELLOW}Введите номера пользователей через пробел (напр: 1 3 4)${NC}"
            read -p "Номера: " -a nums
            
            # Удаляем выбранные строки (с конца, чтобы индексы не плыли)
            sorted_nums=($(printf '%s\n' "${nums[@]}" | sort -nr))
            for n in "${sorted_nums[@]}"; do
                if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -le "${#users[@]}" ]; then
                    sudo sed -i "${n}d" $USER_DB
                fi
            done
            sync_mtp
            ;;

        4) # Установка / Переустановка
            draw_header
            read -p "Порт (8448): " p; MTP_PORT=${p:-8448}
            read -p "TAG бота: " t; MTP_TAG=${t:-"386fa80854214cc50f61914065327bfd"}
            echo "MTP_PORT=$MTP_PORT" | sudo tee $CONFIG_FILE > /dev/null
            echo "MTP_TAG=$MTP_TAG" | sudo tee -a $CONFIG_FILE > /dev/null
            sudo ufw allow $MTP_PORT/tcp &>/dev/null
            sync_mtp
            ;;

        5) # Удаление
            draw_header
            read -p "Удалить всё? (y/n): " confirm
            if [[ $confirm == [yY] ]]; then
                sudo docker stop mtproto-proxy &>/dev/null
                sudo docker rm mtproto-proxy &>/dev/null
                sudo rm -f $USER_DB $CONFIG_FILE
                echo -e "${RED}Удалено.${NC}"; sleep 2
            fi
            ;;

        x|X|ч|Ч) break ;;
    esac
done
