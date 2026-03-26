#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
CONFIG_FILE="/etc/server-menu/mtproxy.conf"

# Инициализация папок
sudo mkdir -p /etc/server-menu
[ ! -f "$USER_DB" ] && sudo touch $USER_DB

# Функция загрузки настроек (порт и тег)
function load_config {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        MTP_PORT="8448"
        MTP_TAG="386fa80854214cc50f61914065327bfd"
    fi
}

# Функция синхронизации Docker
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
        echo -e "${GREEN}✅ Контейнер обновлен и запущен на порту $MTP_PORT!${NC}"
    else
        echo -e "${RED}⚠️ Нет активных ключей. Прокси остановлен.${NC}"
    fi
    sleep 2
}

function draw_header {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}             🛡️  УПРАВЛЕНИЕ MTPROTO PROXY 🛡️            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
}

while true; do
    draw_header
    # Проверка, установлен ли прокси
    if sudo docker ps -a --format '{{.Names}}' | grep -q "mtproto-proxy"; then
        status_msg="${GREEN}УСТАНОВЛЕН И РАБОТАЕТ${NC}"
    else
        status_msg="${RED}НЕ УСТАНОВЛЕН / ОСТАНОВЛЕН${NC}"
    fi

    echo -e "Статус: $status_msg"
    echo -e "${BLUE}--- УПРАВЛЕНИЕ СЕРВИСОМ ------------------------------${NC}"
    echo -e "${YELLOW}1) 🚀 Быстрая установка (Docker + Proxy + UFW)${NC}"
    echo -e "${RED}2) 🗑️  Полное удаление MTProxy и очистка системы${NC}"
    echo -e "${BLUE}--- ПОЛЬЗОВАТЕЛИ -------------------------------------${NC}"
    echo -e "${YELLOW}3) ➕ Добавить пользователя${NC}"
    echo -e "${YELLOW}4) 📋 Список, ссылки и QR-коды${NC}"
    echo -e "${YELLOW}5) ❌ Удалить пользователя${NC}"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "${CYAN}X) 🔙 Назад в главное меню${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    read -p "$(echo -e ${CYAN}"Ваш выбор: "${NC})" sub
    
    case $sub in
        1) # УСТАНОВКА
            draw_header
            echo -e "${YELLOW}Начало установки...${NC}"
            # Проверка Docker
            if ! command -v docker &> /dev/null; then
                echo -e "${YELLOW}Установка Docker...${NC}"
                sudo apt-get update && sudo apt-get install docker.io xxd qrencode -y
                sudo systemctl enable --now docker
            fi
            
            read -p "Введите порт (по умолчанию 8448): " input_port
            MTP_PORT=${input_port:-8448}
            read -p "Введите TAG от бота (Enter если нет): " input_tag
            MTP_TAG=${input_tag:-"386fa80854214cc50f61914065327bfd"}
            
            echo "MTP_PORT=$MTP_PORT" | sudo tee $CONFIG_FILE > /dev/null
            echo "MTP_TAG=$MTP_TAG" | sudo tee -a $CONFIG_FILE > /dev/null
            
            sudo ufw allow $MTP_PORT/tcp
            
            # Если база пуста, создаем первого юзера
            if [ ! -s "$USER_DB" ]; then
                new_sec=$(head -c 16 /dev/urandom | xxd -ps)
                echo "Admin|$new_sec" | sudo tee -a $USER_DB > /dev/null
            fi
            
            sync_mtp
            ;;

        2) # УДАЛЕНИЕ
            draw_header
            echo -e "${RED}ВНИМАНИЕ! Это полностью удалит контейнер и базу пользователей!${NC}"
            read -p "Вы уверены? (y/n): " confirm
            if [[ $confirm == [yY] ]]; then
                load_config
                sudo docker stop mtproto-proxy &>/dev/null
                sudo docker rm mtproto-proxy &>/dev/null
                sudo ufw delete allow $MTP_PORT/tcp &>/dev/null
                sudo rm -f $USER_DB $CONFIG_FILE
                echo -e "${GREEN}Все данные удалены.${NC}"
                sleep 2
            fi
            ;;

        3) # ДОБАВИТЬ
            draw_header
            read -p "Имя: " uname
            [ -z "$uname" ] && continue
            new_sec=$(head -c 16 /dev/urandom | xxd -ps)
            echo "$uname|$new_sec" | sudo tee -a $USER_DB > /dev/null
            sync_mtp
            ;;
            
        4) # СПИСОК
            load_config
            draw_header
            while IFS='|' read -r name key; do
                link="tg://proxy?server=185.223.169.56&port=$MTP_PORT&secret=dd$key"
                echo -e "${YELLOW}👤 $name${NC} | ${CYAN}$link${NC}"
                qrencode -t ANSIUTF8 "$link"
                echo "------------------------------------------------------"
            done < $USER_DB
            read -p "Enter..."
            ;;
            
        5) # УДАЛИТЬ ЮЗЕРА
            draw_header
            mapfile -t users < $USER_DB
            for i in "${!users[@]}"; do echo -e "${CYAN}$((i+1)))${NC} ${users[$i]%%|*}"; done
            read -p "Номер: " num
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -le "${#users[@]}" ]; then
                sudo sed -i "${num}d" $USER_DB
                sync_mtp
            fi
            ;;

        x|X|ч|Ч)
            break
            ;;
    esac
done
