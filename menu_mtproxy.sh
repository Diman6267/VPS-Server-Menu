#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
[ ! -f "$USER_DB" ] && sudo touch $USER_DB

# Функция синхронизации Docker с файлом пользователей
function sync_mtp {
    local port="8448" # Порт, который мы выбрали
    local tag="386fa80854214cc50f61914065327bfd"
    local secrets=$(awk -F'|' '{print $2}' $USER_DB | paste -sd "," -)

    sudo docker stop mtproto-proxy &>/dev/null
    sudo docker rm mtproto-proxy &>/dev/null

    if [ -n "$secrets" ]; then
        sudo docker run -d --name mtproto-proxy --restart always \
            -p $port:443 -p 8888:8888 \
            -e SECRET="$secrets" -e TAG="$tag" \
            telegrammessenger/proxy:latest
        echo -e "${GREEN}Контейнер перезапущен с актуальными ключами.${NC}"
    else
        echo -e "${RED}Нет активных ключей. Прокси остановлен.${NC}"
    fi
}

function show_mtproxy_menu {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}             🛡️ УПРАВЛЕНИЕ MTPROTO PROXY 🛡️            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${YELLOW}1) ➕ Добавить пользователя (Имя)${NC}"
    echo -e "${YELLOW}2) 📋 Список пользователей и ссылки (Fake TLS)${NC}"
    echo -e "${RED}3) ❌ Удалить пользователя${NC}"
    echo -e "${CYAN}0) Назад в главное меню${NC}"
    echo -e "${CYAN}======================================================${NC}"
}
function show_links {
    # Проверяем наличие qrencode
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}Установка утилиты для QR-кодов...${NC}"
        sudo apt-get update && sudo apt-get install qrencode -y
    fi

    clear
    echo -e "${BLUE}СПИСОК ПОЛЬЗОВАТЕЛЕЙ И QR-КОДЫ:${NC}"
    echo "------------------------------------------------------"
    
    while IFS='|' read -r name key; do
        local link="tg://proxy?server=185.223.169.56&port=8448&secret=dd$key"
        
        echo -e "${YELLOW}Пользователь:${NC} ${GREEN}$name${NC}"
        echo -e "${YELLOW}Ссылка:${NC} $link"
        echo -e "${CYAN}QR-код для сканирования:${NC}"
        
        # Генерируем QR-код прямо в терминале
        qrencode -t ANSIUTF8 "$link"
        
        echo "------------------------------------------------------"
    done < $USER_DB
    
    read -p "Нажмите Enter, чтобы вернуться в меню..."
}
while true; do
    show_mtproxy_menu
    read -p "Выбор: " sub
    case $sub in
        1)
            read -p "Введите имя (напр. MyPhone): " uname
            new_sec=$(head -c 16 /dev/urandom | xxd -ps)
            echo "$uname|$new_sec" | sudo tee -a $USER_DB > /dev/null
            sync_mtp
            sleep 2
            ;;
        2)
            clear
            echo -e "${BLUE}СПИСОК ПОЛЬЗОВАТЕЛЕЙ:${NC}"
            echo "------------------------------------------------------"
            while IFS='|' read -r name key; do
                echo -e "${YELLOW}Пользователь:${NC} $name"
                echo -e "${GREEN}Ссылка:${NC} tg://proxy?server=185.223.169.56&port=8448&secret=dd$key"
                echo "------------------------------------------------------"
            done < $USER_DB
            read -p "Нажмите Enter..."
            ;;
        3)
            echo -e "${RED}Кого удалить?${NC}"
            mapfile -t users < $USER_DB
            for i in "${!users[@]}"; do echo "$((i+1))) ${users[$i]%%|*}"; done
            read -p "Номер: " num
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -le "${#users[@]}" ]; then
                sudo sed -i "${num}d" $USER_DB
                sync_mtp
            fi
            sleep 1
            ;;
        0) break ;;
    esac
done
