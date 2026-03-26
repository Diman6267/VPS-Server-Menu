#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
CONFIG_FILE="/etc/server-menu/mtproxy.conf"

# Создаем папку и файл базы, если их нет
sudo mkdir -p /etc/server-menu
[ ! -f "$USER_DB" ] && sudo touch $USER_DB

# Функция определения внешнего IPv4
function get_my_ip {
    local ip=$(curl -s -4 icanhazip.com || curl -s -4 ifconfig.me || curl -s -4 api.ipify.org)
    [ -z "$ip" ] && ip=$(hostname -I | awk '{print $1}')
    echo "$ip"
}

# Загрузка настроек
function load_config {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        MTP_PORT="8448"
        MTP_TAG=""
        MTP_IP=$(get_my_ip)
    fi
}

# Синхронизация с Docker
function sync_mtp {
    load_config
    local secrets=$(awk -F'|' '{print $2}' $USER_DB | paste -sd "," -)
    
    echo -e "${YELLOW}🔄 Обновление контейнера Docker...${NC}"
    sudo docker stop mtproto-proxy &>/dev/null
    sudo docker rm mtproto-proxy &>/dev/null
    
    if [ -n "$secrets" ]; then
        # Формируем параметры. Важно: для работы тега часто нужен порт 8888
        local tag_param=""
        [ -n "$MTP_TAG" ] && tag_param="-e TAG=$MTP_TAG -p 8888:8888"
        
        sudo docker run -d --name mtproto-proxy --restart always \
            -p $MTP_PORT:443 $tag_param \
            -e SECRET="$secrets" \
            telegrammessenger/proxy:latest &>/dev/null
        echo -e "${GREEN}✅ Прокси успешно запущен!${NC}"
    else
        echo -e "${RED}⚠️ Список ключей пуст. Прокси остановлен.${NC}"
    fi
    sleep 1
}

# Красивый вывод инфо о пользователе
function show_user_info {
    local name=$1
    local key=$2
    # УБИРАЕМ "dd" перед $key
    local link="tg://proxy?server=$MTP_IP&port=$MTP_PORT&secret=$key"
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
    load_config
    draw_header
    echo -e "${BLUE}--- ПОЛЬЗОВАТЕЛИ -------------------------------------${NC}"
    echo -e "${YELLOW}1) ➕ Добавить пользователей${NC}"
    echo -e "${YELLOW}2) 📋 Показать пользователей${NC}"
    echo -e "${RED}3) ❌ Удалить пользователей (выбор нескольких)${NC}"
    echo -e "${BLUE}--- СЕРВИС (IP: $MTP_IP | Port: $MTP_PORT) ---${NC}"
    echo -e "${GREEN}4) 🚀 Установка / Смена настроек${NC}"
    echo -e "${RED}5) 🗑️  Полное удаление прокси${NC}"
    echo -e "${CYAN}X) 🔙 Назад${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    read -p "$(echo -e ${CYAN}"Ваш выбор: "${NC})" sub
    
    case $sub in
        1)
            draw_header
            read -p "Сколько пользователей добавить? " ucount
            [[ ! "$ucount" =~ ^[0-9]+$ ]] && ucount=1
            new_users=()
            for (( i=1; i<=ucount; i++ )); do
                echo -e "${YELLOW}Имя для пользователя #$i:${NC}"
                read -p "> " uname
                [ -z "$uname" ] && uname="User_$RANDOM"
                # Генерируем ровно 32 символа hex
                usecret=$(head -c 16 /dev/urandom | xxd -ps)
                echo "$uname|$usecret" | sudo tee -a $USER_DB > /dev/null
                new_users+=("$uname|$usecret")
            done
            sync_mtp
            draw_header
            echo -e "${GREEN}✨ КЛЮЧИ СОЗДАНЫ:${NC}"
            for entry in "${new_users[@]}"; do
                IFS='|' read -r n k <<< "$entry"
                show_user_info "$n" "$k"
            done
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            if ! command -v qrencode &> /dev/null; then sudo apt-get install qrencode -y &>/dev/null; fi
            draw_header
            if [ ! -s "$USER_DB" ]; then echo -e "${RED}База пользователей пуста!${NC}"; sleep 2; continue; fi
            while IFS='|' read -r name key; do
                show_user_info "$name" "$key"
            done < $USER_DB
            read -p "Нажмите Enter..."
            ;;
        3)
            draw_header
            mapfile -t users < $USER_DB
            if [ ${#users[@]} -eq 0 ]; then echo -e "${RED}Удалять некого!${NC}"; sleep 2; continue; fi
            for i in "${!users[@]}"; do echo -e "${CYAN}$((i+1)))${NC} ${users[$i]%%|*}"; done
            echo -e "${YELLOW}Введите номера через пробел (например: 1 3):${NC}"
            read -p "> " -a nums
            # Сортируем номера по убыванию, чтобы не сбить индексы при удалении строк
            sorted_nums=($(printf '%s\n' "${nums[@]}" | sort -nr))
            for n in "${sorted_nums[@]}"; do
                if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -le "${#users[@]}" ]; then
                    sudo sed -i "${n}d" $USER_DB
                fi
            done
            sync_mtp
            ;;
        4)
            draw_header
            det_ip=$(get_my_ip)
            read -p "Подтвердите IP сервера ($det_ip): " p_ip; MTP_IP=${p_ip:-$det_ip}
            read -p "Порт (8448): " p_port; MTP_PORT=${p_port:-8448}
            echo -e "${YELLOW}TAG нужен только для @MTProxybot. Если не используете — просто Enter.${NC}"
            read -p "Введите TAG: " p_tag; MTP_TAG=${p_tag:-""}
            
            # Сохраняем в конфиг
            sudo bash -c "cat > $CONFIG_FILE" <<EOF
MTP_IP="$MTP_IP"
MTP_PORT="$MTP_PORT"
MTP_TAG="$MTP_TAG"
EOF
            sudo ufw allow $MTP_PORT/tcp &>/dev/null
            sync_mtp
            ;;
        5)
            draw_header
            read -p "Удалить прокси и базу пользователей? (y/n): " confirm
            if [[ $confirm == [yY] ]]; then
                sudo docker stop mtproto-proxy &>/dev/null
                sudo docker rm mtproto-proxy &>/dev/null
                sudo rm -f $USER_DB $CONFIG_FILE
                echo -e "${RED}Всё удалено.${NC}"; sleep 2
            fi
            ;;
        x|X|ч|Ч) break ;;
    esac
done
