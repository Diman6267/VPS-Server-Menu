#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
[ ! -f "$USER_DB" ] && sudo mkdir -p /etc/server-menu && sudo touch $USER_DB

function sync_mtp {
    local port="8448"
    local tag="386fa80854214cc50f61914065327bfd"
    local secrets=$(awk -F'|' '{print $2}' $USER_DB | paste -sd "," -)

    sudo docker stop mtproto-proxy &>/dev/null
    sudo docker rm mtproto-proxy &>/dev/null

    if [ -n "$secrets" ]; then
        sudo docker run -d --name mtproto-proxy --restart always \
            -p $port:443 -p 8888:8888 \
            -e SECRET="$secrets" -e TAG="$tag" \
            telegrammessenger/proxy:latest
        echo -e "${GREEN}Контейнер обновлен.${NC}"
    else
        echo -e "${RED}Нет ключей. Прокси остановлен.${NC}"
    fi
}

while true; do
    clear
    echo -e "${CYAN}=== УПРАВЛЕНИЕ MTPROTO (С QR-КОДАМИ) ===${NC}"
    echo -e "1) ➕ Добавить пользователя"
    echo -e "2) 📋 Список, ссылки и QR-коды"
    echo -e "3) ❌ Удалить пользователя"
    echo -e "0) Назад"
    read -p "Выбор: " sub
    case $sub in
        1)
            read -p "Имя (напр. iPhone): " uname
            new_sec=$(head -c 16 /dev/urandom | xxd -ps)
            echo "$uname|$new_sec" | sudo tee -a $USER_DB > /dev/null
            sync_mtp
            sleep 2 ;;
        2)
            if ! command -v qrencode &> /dev/null; then sudo apt-get install qrencode -y; fi
            clear
            while IFS='|' read -r name key; do
                link="tg://proxy?server=185.223.169.56&port=8448&secret=dd$key"
                echo -e "${YELLOW}Пользователь:${NC} $name"
                echo -e "${GREEN}Ссылка:${NC} $link"
                qrencode -t ANSIUTF8 "$link"
                echo "------------------------------------------------"
            done < $USER_DB
            read -p "Enter для выхода..." ;;
        3)
            mapfile -t users < $USER_DB
            for i in "${!users[@]}"; do echo "$((i+1))) ${users[$i]%%|*}"; done
            read -p "Номер для удаления: " num
            sed -i "${num}d" $USER_DB
            sync_mtp
            sleep 1 ;;
        0) break ;;
    esac
done
