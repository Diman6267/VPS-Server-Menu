#!/bin/bash
# Подключаем твои цвета (NC, CYAN, YELLOW, GREEN, RED, BLUE)
source /usr/local/bin/_config_and_utils.sh

USER_DB="/etc/server-menu/mtproxy_users.list"
[ ! -f "$USER_DB" ] && sudo mkdir -p /etc/server-menu && sudo touch $USER_DB

# Функция синхронизации Docker
function sync_mtp {
    local port="8448"
    local tag="386fa80854214cc50f61914065327bfd"
    local secrets=$(awk -F'|' '{print $2}' $USER_DB | paste -sd "," -)

    echo -e "${YELLOW}🔄 Синхронизация Docker...${NC}"
    sudo docker stop mtproto-proxy &>/dev/null
    sudo docker rm mtproto-proxy &>/dev/null

    if [ -n "$secrets" ]; then
        sudo docker run -d --name mtproto-proxy --restart always \
            -p $port:443 -p 8888:8888 \
            -e SECRET="$secrets" -e TAG="$tag" \
            telegrammessenger/proxy:latest &>/dev/null
        echo -e "${GREEN}✅ Контейнер успешно обновлен и запущен!${NC}"
    else
        echo -e "${RED}⚠️ Нет активных ключей. Прокси остановлен.${NC}"
    fi
    sleep 2
}

# Функция вывода красивого заголовка
function draw_header {
    clear
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}             🛡️  УПРАВЛЕНИЕ MTPROTO PROXY 🛡️            ${NC}"
    echo -e "${CYAN}======================================================${NC}"
}

while true; do
    draw_header
    echo -e "${BLUE}--- ПОЛЬЗОВАТЕЛИ -------------------------------------${NC}"
    echo -e "${YELLOW}1) ➕ Добавить нового пользователя${NC}"
    echo -e "${YELLOW}2) 📋 Список пользователей, ссылки и QR-коды${NC}"
    echo -e "${RED}3) ❌ Удалить пользователя из системы${NC}"
    echo -e "${BLUE}--- НАСТРОЙКИ ----------------------------------------${NC}"
    echo -e "${GREEN}4) 🤖 Обновить Proxy Tag (@MTProxybot)${NC}"
    echo -e "${CYAN}X) 🔙 Назад в главное меню${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    read -p "$(echo -e ${CYAN}"Ваш выбор: "${NC})" sub
    
    case $sub in
        1)
            draw_header
            echo -e "${YELLOW}Введите имя для нового ключа (напр. iPhone_Diman):${NC}"
            read -p "> " uname
            if [ -z "$uname" ]; then continue; fi
            
            new_sec=$(head -c 16 /dev/urandom | xxd -ps)
            echo "$uname|$new_sec" | sudo tee -a $USER_DB > /dev/null
            sync_mtp
            ;;
            
        2)
            if ! command -v qrencode &> /dev/null; then 
                echo -e "${YELLOW}Установка qrencode...${NC}"
                sudo apt-get install qrencode -y &>/dev/null
            fi
            
            draw_header
            echo -e "${BLUE}ДЕЙСТВУЮЩИЕ ПОДКЛЮЧЕНИЯ:${NC}"
            echo "------------------------------------------------------"
            
            while IFS='|' read -r name key; do
                link="tg://proxy?server=185.223.169.56&port=8448&secret=dd$key"
                echo -e "${YELLOW}👤 Пользователь:${NC} ${GREEN}$name${NC}"
                echo -e "${YELLOW}🔗 Ссылка:${NC} ${CYAN}$link${NC}"
                echo -e "${BLUE}📱 QR-код для сканирования:${NC}"
                qrencode -t ANSIUTF8 "$link"
                echo -e "${BLUE}------------------------------------------------------${NC}"
            done < $USER_DB
            
            read -p "$(echo -e ${YELLOW}"Нажмите Enter для возврата..."${NC})"
            ;;
            
        3)
            draw_header
            echo -e "${RED}Выберите номер пользователя для удаления:${NC}"
            mapfile -t users < $USER_DB
            if [ ${#users[@]} -eq 0 ]; then
                echo -e "${YELLOW}Список пуст.${NC}"
                sleep 2
                continue
            fi
            
            for i in "${!users[@]}"; do
                echo -e "${CYAN}$((i+1)))${NC} ${users[$i]%%|*}"
            done
            
            read -p "Номер: " num
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -le "${#users[@]}" ]; then
                target_name=${users[$((num-1))]%%|*}
                sudo sed -i "${num}d" $USER_DB
                echo -e "${RED}Пользователь $target_name удален.${NC}"
                sync_mtp
            else
                echo -e "${RED}Неверный номер!${NC}"
                sleep 2
            fi
            ;;

        4)
            draw_header
            echo -e "${YELLOW}Текущий TAG:${NC} 386fa80854214cc50f61914065327bfd"
            read -p "Введите новый TAG от @MTProxybot: " ntag
            if [ -n "$ntag" ]; then
                # Здесь можно добавить сохранение тега в конфиг, если нужно
                sync_mtp
            fi
            ;;

       x|X)
            break
            ;;
            
        *)
            echo -e "${RED}Неверный пункт!${NC}"
            sleep 1
            ;;
    esac
done
