#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
CONFIG_FILE="/etc/server-menu/mtproxy.conf"

sudo mkdir -p /etc/server-menu
[ ! -f "$USER_DB" ] && sudo touch $USER_DB

# --- УТИЛИТЫ ---
function get_my_ip {
    local ip=$(curl -s -4 icanhazip.com || curl -s -4 ifconfig.me || curl -s -4 api.ipify.org)
    [ -z "$ip" ] && ip=$(hostname -I | awk '{print $1}')
    echo "$ip"
}

function load_config {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        MTP_PORT="8448"
        MTP_TAG=""
        MTP_IP=$(get_my_ip)
    fi
}

function sync_mtp {
    load_config
    # Собираем все секреты, убираем пустые строки
    local secrets=$(awk -F'|' '{print $2}' $USER_DB | grep -v '^$' | paste -sd "," -)

    echo -e "${YELLOW}🔄 Перезапуск Docker-контейнера...${NC}"
    sudo docker stop mtproto-proxy &>/dev/null
    sudo docker rm mtproto-proxy &>/dev/null

    if [ -n "$secrets" ]; then
        # Если TAG есть, добавляем его и пробрасываем порт 8888 для статистики
        local tag_param=""
        [ -n "$MTP_TAG" ] && tag_param="-e TAG=$MTP_TAG -p 8888:8888"
        
        sudo docker run -d --name mtproto-proxy --restart always \
            -p $MTP_PORT:443 $tag_param \
            -e SECRET="$secrets" \
            telegrammessenger/proxy:latest &>/dev/null
        echo -e "${GREEN}✅ Прокси запущен на порту $MTP_PORT!${NC}"
    else
        echo -e "${RED}⚠️ Нет активных ключей. Прокси остановлен.${NC}"
    fi
    echo -e "${CYAN}Нажмите Enter, чтобы продолжить...${NC}"
    read -r
}

function show_user_info {
    local name=$1
    local key=$2
    local link=""

    # Если ключ стандартный (32 симв), добавляем dd. Если старый длинный — оставляем как есть.
    if [ ${#key} -eq 32 ]; then
        link="tg://proxy?server=$MTP_IP&port=$MTP_PORT&secret=dd$key"
    else
        link="tg://proxy?server=$MTP_IP&port=$MTP_PORT&secret=$key"
    fi

    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "${YELLOW}👤 Пользователь:${NC} ${GREEN}$name${NC}"
    echo -e "${YELLOW}🔗 Ссылка:${NC} ${CYAN}$link${NC}"
    qrencode -t ANSIUTF8 "$link"
}

function draw_header {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}             ✈️  УПРАВЛЕНИЕ MTPROTO PROXY ✈️            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
}

# --- ОСНОВНОЙ ЦИКЛ ---
while true; do
    load_config
    draw_header
    echo -e "${BLUE}--- ПОЛЬЗОВАТЕЛИ -------------------------------------${NC}"
    echo -e "${YELLOW}1) ➕ Добавить пользователей (массово)${NC}"
    echo -e "${YELLOW}2) 📋 Список всех QR-кодов и ссылок${NC}"
    echo -e "${RED}3) ❌ Удалить пользователей (выбор нескольких)${NC}"
    echo -e "${BLUE}--- СЕРВИС (IP: $MTP_IP | Port: $MTP_PORT) ---${NC}"
    echo -e "${GREEN}4) 🚀 Установка / Смена настроек (IP/Порт/Тег)${NC}"
    echo -e "${RED}5) 🗑️  Полное удаление прокси${NC}"
    echo -e "${CYAN}X) 🔙 Назад в главное меню${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    read -p "$(echo -e ${CYAN}"Ваш выбор: "${NC})" sub
    
    case $sub in
        1)
            draw_header
            read -p "Сколько пользователей добавить? " ucount
            [[ ! "$ucount" =~ ^[0-9]+$ ]] && ucount=1
            new_users=()
            for (( i=1; i<=ucount; i++ )); do
                echo -e "${YELLOW}Введите имя для пользователя #$i:${NC}"
                read -p "> " uname
                [ -z "$uname" ] && uname="User_$RANDOM"
                # Генерируем ровно 32 символа (16 байт)
                usecret=$(head -c 16 /dev/urandom | xxd -ps -c 16)
                echo "$uname|$usecret" | sudo tee -a $USER_DB > /dev/null
                new_users+=("$uname|$usecret")
            done
            sync_mtp
            draw_header
            echo -e "${GREEN}✨ НОВЫЕ ПОЛЬЗОВАТЕЛИ ДОБАВЛЕНЫ:${NC}"
            for entry in "${new_users[@]}"; do
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
            read -p "Нажмите Enter..."
            ;;
            
        3)
            draw_header
            mapfile -t users < $USER_DB
            if [ ${#users[@]} -eq 0 ]; then echo -e "${RED}Список пуст!${NC}"; sleep 2; continue; fi
            for i in "${!users[@]}"; do echo -e "${CYAN}$((i+1)))${NC} ${users[$i]%%|*}"; done
            echo -e "${YELLOW}Введите номера через пробел (напр: 1 3 5):${NC}"
            read -p "Номера: " -a nums
            # Удаляем с конца, чтобы не плыли индексы
            sorted_nums=($(printf '%s\n' "${nums[@]}" | sort -nr))
            for n in "${sorted_nums[@]}"; do
                if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -le "${#users[@]}" ]; then
                    sudo sed -i "${n}d" $USER_DB
                fi
            done
            sync_mtp
            ;;

        4)
            function check_docker {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker не найден. Начинаю установку...${NC}"
        curl -fsSL https://get.docker.com | sh
        sudo systemctl enable --now docker
        echo -e "${GREEN}✅ Docker установлен и добавлен в автозагрузку!${NC}"
    fi
}
            check_docker
            draw_header
            det_ip=$(get_my_ip)
            read -p "Подтвердите IPv4 ($det_ip): " p_ip; MTP_IP=${p_ip:-$det_ip}
            read -p "Порт (8448): " p_port; MTP_PORT=${p_port:-8448}
            echo -e "${YELLOW}TAG нужен только для @MTProxybot. Если нет — просто Enter.${NC}"
            read -p "Введите TAG: " p_tag; MTP_TAG=${p_tag:-""}
            
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
            read -p "Удалить контейнер и ВСЕХ пользователей? (y/n): " confirm
            if [[ $confirm == [yY] ]]; then
                sudo docker stop mtproto-proxy &>/dev/null
                sudo docker rm mtproto-proxy &>/dev/null
                sudo docker rmi telegrammessenger/proxy:latest
                sudo rm -rf /etc/server-menu/mtproxy.conf /etc/server-menu/mtproxy_users.list
                sudo rm -f $USER_DB $CONFIG_FILE
                echo -e "${RED}Всё удалено.${NC}"; echo -e "${CYAN}Нажмите Enter, чтобы продолжить...${NC}"
    read -r
            fi
            ;;

        x|X|ч|Ч) break ;;
    esac
done
