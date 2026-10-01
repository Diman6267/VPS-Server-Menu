#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

# ----------------------------------------------------------------------
# НАСТРОЙКИ СЕРВЕРА И ФУНКЦИИ ПРОВЕРКИ
# ----------------------------------------------------------------------

# --- ПРОВЕРКИ СТАТУСА ---

function check_ufw_installed {
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}❌ UFW не установлен. Установите UFW (sudo apt install ufw) для управления PING.${NC}"
        return 1
    fi
    return 0
}

function get_bbr_status {
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "active"
    else
        echo "inactive"
    fi
}

function get_ping_status {
    local RULES_FILE="/etc/ufw/before.rules"
    if grep -q "^[[:space:]]*[^#]*ufw-before-input -p icmp --icmp-type echo-request -j DROP" "$RULES_FILE" 2>/dev/null; then
        echo "disabled"
    else
        echo "enabled"
    fi
}

function get_ufw_status {
    if sudo ufw status | grep -q "Status: active"; then echo "active"; else echo "inactive"; fi
}

function get_timezone_status {
    timedatectl | grep "Time zone" | awk '{print $3}'
}
function get_swap_status {
    local swap_total_kb=$(grep -i '^SwapTotal:' /proc/meminfo | awk '{print $2}')
    local swap_free_kb=$(grep -i '^SwapFree:' /proc/meminfo | awk '{print $2}')
    if [ -z "$swap_total_kb" ] || [ "$swap_total_kb" -eq 0 ]; then
        echo -e "${RED}ОТКЛЮЧЕН${NC}"
    else
        local swap_total_mb=$((swap_total_kb / 1024))
        local swap_used_mb=$(( (swap_total_kb - swap_free_kb) / 1024 ))
        local swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "?")
        echo -e "${GREEN}АКТИВЕН (${swap_total_mb} МБ | Исп: ${swap_used_mb} МБ | Swappiness: ${swappiness})${NC}"
    fi
}
# ----------------------------------------------------------------------
# НОВЫЕ ПУНКТЫ (UFW И TIMEZONE)
# ----------------------------------------------------------------------

function show_ufw_menu {
    while true; do
        clear
        echo -e "${CYAN}--- 🛡️ УПРАВЛЕНИЕ ФАЙРВОЛОМ (UFW) -----------------------${NC}"
        echo -e "    Статус: [$(if [ "$(get_ufw_status)" == "active" ]; then echo -e "${GREEN}ВКЛЮЧЕН${NC}"; else echo -e "${RED}ВЫКЛЮЧЕН${NC}"; fi)]"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "1) 🟢  Включить UFW"
        echo -e "2) 🔴  Выключить UFW"
        echo -e "3) 🔓  Разрешить порт (allow)"
        echo -e "4) 🔒  Запретить порт (deny)"
        echo -e "5) 🗑️   Удалить правило (по номеру)"
        echo -e "6) 📜  Список правил (с номерами)"
        echo -e "7) 🔄  Перезагрузить (reload)"
        echo -e "X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -p "Выбор: " u_choice

        case $u_choice in
            1) sudo ufw --force enable ;;
            2) sudo ufw disable ;;
            3|4) 
                [ "$u_choice" == "3" ] && action="allow" || action="deny"
                
                echo -e "${YELLOW}(Введите 0 или просто Enter для отмены)${NC}"
                read -p "Введите порт: " p
                
                # Проверка на отмену
                if [[ -z "$p" || "$p" == "0" ]]; then
                    echo -e "${BLUE}Действие отменено.${NC}"
                    sleep 1
                    continue
                fi

                echo -e "Выберите протокол для порта $p:"
                echo -e "1) TCP\n2) UDP\n3) Оба (и TCP и UDP)\n0) Отмена"
                read -p "Выбор [1-3, 0]: " proto_choice
                
                case $proto_choice in
                    1) res=$(sudo ufw $action "$p/tcp") ;;
                    2) res=$(sudo ufw $action "$p/udp") ;;
                    3) res=$(sudo ufw $action "$p") ;;
                    *) echo -e "${BLUE}Действие отменено.${NC}"; sleep 1; continue ;;
                esac
                
                echo -e "${YELLOW}Результат:${NC} $res"
                read -p "Нажмите Enter для продолжения..." ;;
            
            5) 
                echo -e "${GREEN}Текущие пронумерованные правила:${NC}"
                sudo ufw status numbered
                echo -e "${YELLOW}(Введите 0 или просто Enter для отмены)${NC}"
                read -p "Введите НОМЕР правила для удаления: " n
                
                if [[ -z "$n" || "$n" == "0" ]]; then
                    echo -e "${BLUE}Удаление отменено.${NC}"
                    sleep 1
                    continue
                fi
                
                # Подтверждение удаления
                read -p "Вы уверены, что хотите удалить правило #$n? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    res=$(sudo ufw --force delete "$n")
                    echo -e "${YELLOW}Результат:${NC} $res"
                else
                    echo -e "${BLUE}Удаление отменено.${NC}"
                fi
                read -p "Нажмите Enter..." ;;
                
            6) 
                echo -e "${GREEN}Текущие правила UFW:${NC}"
                sudo ufw status numbered
                read -p "Нажмите Enter..." ;;
                
            7) 
                sudo ufw reload
                read -p "Нажмите Enter..." ;;
                
            [Xx]) return ;;
        esac
    done
}

function set_timezone_menu {
    while true; do
        clear
        echo -e "${CYAN}--- 🕒 НАСТРОЙКА ЧАСОВОГО ПОЯСА -------------------------${NC}"
        echo -e "    Текущий пояс: ${GREEN}$(get_timezone_status)${NC}"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "1) 🏰  Калининград (MSK-1)   5) 🏔️  Екатеринбург (MSK+2)"
        echo -e "2) 🏛️   Москва (MSK)          6) 🌲 Новосибирск (MSK+4)"
        echo -e "3) 🚀  Самара (MSK+1)        7) ⚓ Владивосток (MSK+7)"
        echo -e "4) 🌍  UTC                   8) ❄️  Магадан (MSK+8)"
        echo -e "X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -p "Выбор [1-8, X]: " t_choice
        case $t_choice in
            1) sudo timedatectl set-timezone Europe/Kaliningrad ;;
            2) sudo timedatectl set-timezone Europe/Moscow ;;
            3) sudo timedatectl set-timezone Europe/Samara ;;
            4) sudo timedatectl set-timezone UTC ;;
            5) sudo timedatectl set-timezone Asia/Yekaterinburg ;;
            6) sudo timedatectl set-timezone Asia/Novosibirsk ;;
            7) sudo timedatectl set-timezone Asia/Vladivostok ;;
            8) sudo timedatectl set-timezone Asia/Magadan ;;
            [Xx]) return ;;
        esac
        echo -e "${GREEN}✅ Готово.${NC}" ; sleep 1
    done
}

# ----------------------------------------------------------------------
# BBR: УПРАВЛЕНИЕ ОПТИМИЗАЦИЕЙ СЕТИ (Оригинал)
# ----------------------------------------------------------------------

function enable_bbr {
    local SYSCTL_CONF="/etc/sysctl.conf"
    if [ "$(get_bbr_status)" == "active" ]; then
        echo -e "${YELLOW}BBR уже активен. Действие отменено.${NC}"
        return
    fi
    echo -e "${CYAN}>>> Активация BBR...${NC}"
    sudo sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
    echo "net.core.default_qdisc=fq" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    sudo sysctl -p > /dev/null
    if [ "$(get_bbr_status)" == "active" ]; then echo -e "${GREEN}✅ BBR успешно активирован.${NC}"; fi
}

function disable_bbr {
    local SYSCTL_CONF="/etc/sysctl.conf"
    if [ "$(get_bbr_status)" == "inactive" ]; then
        echo -e "${YELLOW}BBR уже не используется. Действие отменено.${NC}"
        return
    fi
    echo -e "${CYAN}>>> Отключение BBR (возврат к Cubic)...${NC}"
    sudo sed -i '/net.core.default_qdisc/d' "$SYSCTL_CONF"
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' "$SYSCTL_CONF"
    echo "net.core.default_qdisc=fq_codel" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    echo "net.ipv4.tcp_congestion_control=cubic" | sudo tee -a "$SYSCTL_CONF" > /dev/null
    sudo sysctl -p > /dev/null
    if [ "$(get_bbr_status)" == "inactive" ]; then echo -e "${GREEN}✅ BBR успешно отключен.${NC}"; fi
}

function show_bbr_menu {
    while true; do
        clear
        STATUS=$(get_bbr_status)
        echo -e "${CYAN}--- 📈 УПРАВЛЕНИЕ ОПТИМИЗАЦИЕЙ BBR -----------------------${NC}"
        echo -e "    Текущий статус: [$(if [ "$STATUS" == "active" ]; then echo -e "${GREEN}АКТИВЕН${NC}"; else echo -e "${RED}ОТКЛЮЧЕН${NC}"; fi)]"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "${GREEN}1) 🟢  Активировать BBR${NC}"
        echo -e "${RED}2) 🔴  Деактивировать BBR (возврат к Cubic)${NC}"
        echo -e "${YELLOW}3) ℹ️   Показать текущий алгоритм (sysctl)${NC}"
        echo -e "${RED}X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -p "Ваш выбор [1-3, X]: " choice
        case $choice in
            1) enable_bbr ;;
            2) disable_bbr ;;
            3) sysctl net.ipv4.tcp_congestion_control ;;
            [Xx]) return ;;
        esac
        read -p "Нажмите Enter для продолжения..."
    done
}

# ----------------------------------------------------------------------
# PING: УПРАВЛЕНИЕ ЗАПРЕТОМ PING (Оригинал)
# ----------------------------------------------------------------------

function manage_ping_logic {
    local RULES_FILE="/etc/ufw/before.rules"
    local ACTION=$1  # "disable" или "enable"

    if [ "$ACTION" == "disable" ]; then
        # 1. Массовая замена ACCEPT на DROP (и в INPUT, и в FORWARD)
        sudo sed -i '/ufw-before-input -p icmp --icmp-type .* -j ACCEPT/s/ACCEPT/DROP/' "$RULES_FILE"
        sudo sed -i '/ufw-before-forward -p icmp --icmp-type .* -j ACCEPT/s/ACCEPT/DROP/' "$RULES_FILE"
        
        # 2. Добавляем source-quench ТОЛЬКО в блок INPUT (после echo-request)
        if ! grep -q "source-quench -j DROP" "$RULES_FILE"; then
            sudo sed -i '/ufw-before-input -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-input -p icmp --icmp-type source-quench -j DROP' "$RULES_FILE"
        fi
        echo -e "${GREEN}✅ Пинг запрещен. (Блок FORWARD только переведен в DROP)${NC}"
    else
        # 1. Массовая замена DROP на ACCEPT обратно
        sudo sed -i '/ufw-before-input -p icmp --icmp-type .* -j DROP/s/DROP/ACCEPT/' "$RULES_FILE"
        sudo sed -i '/ufw-before-forward -p icmp --icmp-type .* -j DROP/s/DROP/ACCEPT/' "$RULES_FILE"
        
        # 2. Удаляем source-quench (он был только в INPUT)
        sudo sed -i '/source-quench -j ACCEPT/d' "$RULES_FILE"
        echo -e "${GREEN}✅ Пинг разрешен.${NC}"
    fi
    sudo ufw reload > /dev/null
}

function show_ping_menu {
    check_ufw_installed || return
    PING_STATUS=$(get_ping_status)

    echo -e "\n${CYAN}>>> УПРАВЛЕНИЕ ПИНГОМ (ICMP)${NC}"
    if [ "$PING_STATUS" == "enabled" ]; then
        echo -e "Текущий статус: ${GREEN}РАЗРЕШЕН${NC}"
        read -p "Желаете ЗАПРЕТИТЬ пинг? [y/N]: " act
        [[ "$act" =~ ^[Yy]$ ]] && manage_ping_logic "disable"
    else
        echo -e "Текущий статус: ${RED}ЗАПРЕЩЕН${NC}"
        read -p "Желаете РАЗРЕШИТЬ пинг? [y/N]: " act
        [[ "$act" =~ ^[Yy]$ ]] && manage_ping_logic "enable"
    fi
    sleep 2
}
# ----------------------------------------------------------------------
# SSL: УПРАВЛЕНИЕ СЕРТИФИКАТАМИ
# ----------------------------------------------------------------------

# Глобальная переменная директории для сертификатов
SSL_SAVE_DIR="/root/cert"

function manage_ssl_menu {
    # Проверяем и ставим certbot, если его нет
    if ! command -v certbot &> /dev/null; then
        echo -e "${YELLOW}Установка Certbot для работы с сертификатами...${NC}"
        sudo apt update && sudo apt install -y certbot
    fi

    # Создаем папку, если ее нет
    mkdir -p "$SSL_SAVE_DIR"

    while true; do
        clear
        echo -e "${CYAN}--- 🔐 УПРАВЛЕНИЕ СЕРТИФИКАТАМИ (SSL/ACME) ----------------${NC}"
        echo -e "    Папка сохранения: ${GREEN}$SSL_SAVE_DIR${NC}"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "1) ➕  Получить сертификат (Один домен или Multi-domain SAN)"
        echo -e "2) 📋  Список сохраненных сертификатов"
        echo -e "3) ❌  Отозвать и удалить сертификат"
        echo -e "4) ⚙️   Изменить папку по умолчанию"
        echo -e "X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -p "Выбор: " ssl_choice

        case $ssl_choice in
            1)
                read -p "Сколько доменов включить в сертификат? (по умолчанию 1): " d_count
                [[ ! "$d_count" =~ ^[0-9]+$ ]] && d_count=1
                
                DOMAINS_ARGS=""
                FIRST_DOMAIN=""
                for (( i=1; i<=d_count; i++ )); do
                    read -p "Введите домен #$i (например, example.com): " dom
                    if [ -n "$dom" ]; then
                        DOMAINS_ARGS="$DOMAINS_ARGS -d $dom"
                        [ -z "$FIRST_DOMAIN" ] && FIRST_DOMAIN="$dom"
                    fi
                done
                
                if [ -z "$FIRST_DOMAIN" ]; then
                    echo -e "${RED}Домены не введены. Отмена.${NC}"; sleep 1; continue
                fi

                # Автоматически освобождаем 80 порт перед запросом
                if ss -tlpn | grep -q ":80 "; then
                    echo -e "${YELLOW}Порт 80 занят! Временно останавливаем службы (nginx/apache/hysteria)...${NC}"
                    sudo systemctl stop nginx apache2 hysteria-server 2>/dev/null
                fi

                echo -e "${CYAN}Запрашиваем сертификат...${NC}"
                # Запрашиваем email для уведомлений
                echo -e "${YELLOW}Email нужен Let's Encrypt только для уведомлений об истечении сертификата.${NC}"
                read -p "Введите email (или нажмите Enter, чтобы выпустить без почты): " acme_email

                if [ -z "$acme_email" ]; then
                    EMAIL_ARG="--register-unsafely-without-email"
                else
                    EMAIL_ARG="-m $acme_email"
                fi

                echo -e "${CYAN}Запрашиваем сертификат...${NC}"
                # Запрашиваем через standalone сервер
                sudo certbot certonly --standalone $DOMAINS_ARGS --non-interactive --agree-tos $EMAIL_ARG
                
                if [ $? -eq 0 ]; then
                    # Копируем ключи в пользовательскую папку
                    mkdir -p "$SSL_SAVE_DIR/$FIRST_DOMAIN"
                    cp /etc/letsencrypt/live/$FIRST_DOMAIN/fullchain.pem "$SSL_SAVE_DIR/$FIRST_DOMAIN/fullchain.pem"
                    cp /etc/letsencrypt/live/$FIRST_DOMAIN/privkey.pem "$SSL_SAVE_DIR/$FIRST_DOMAIN/privkey.pem"
                    
                    echo -e "\n${GREEN}✅ Сертификаты успешно выпущены и скопированы!${NC}"
                    echo -e "${YELLOW}Путь к Fullchain (Сертификат): ${NC}$SSL_SAVE_DIR/$FIRST_DOMAIN/fullchain.pem"
                    echo -e "${YELLOW}Путь к Privkey (Ключ):       ${NC}$SSL_SAVE_DIR/$FIRST_DOMAIN/privkey.pem"
                else
                    echo -e "\n${RED}❌ Ошибка при выпуске сертификата.${NC}"
                    echo -e "Убедитесь, что IP домена настроен правильно, а порты 80 и 443 открыты в UFW."
                fi
                read -p "Нажмите Enter..." ;;
            
            2)
                echo -e "${GREEN}Сертификаты в базе системы (Certbot):${NC}"
                sudo certbot certificates 2>/dev/null | grep -E 'Certificate Name|Domains|Expiry Date' || echo "Нет активных."
                
                echo -e "\n${GREEN}Сертификаты в вашей папке ($SSL_SAVE_DIR):${NC}"
                ls -lh "$SSL_SAVE_DIR" 2>/dev/null || echo "Папка пуста."
                read -p "Нажмите Enter..." ;;

            3)
                echo -e "${GREEN}Доступные сертификаты для удаления:${NC}"
                sudo certbot certificates 2>/dev/null | grep "Certificate Name:"
                
                echo -e "${YELLOW}(Введите 0 или просто Enter для отмены)${NC}"
                read -p "Введите имя сертификата (Certificate Name) для отзыва: " del_dom
                
                if [[ -z "$del_dom" || "$del_dom" == "0" ]]; then
                    echo -e "${BLUE}Удаление отменено.${NC}"; sleep 1; continue
                fi
                
                # Отзываем и удаляем
                sudo certbot revoke --cert-name "$del_dom" --delete-after-revoke --reason unspecified
                rm -rf "$SSL_SAVE_DIR/$del_dom"
                
                echo -e "${GREEN}✅ Сертификат $del_dom отозван и удален со всех папок.${NC}"
                read -p "Нажмите Enter..." ;;

            4)
                read -p "Введите новый путь [текущий: $SSL_SAVE_DIR]: " new_dir
                if [ -n "$new_dir" ]; then
                    SSL_SAVE_DIR="$new_dir"
                    mkdir -p "$SSL_SAVE_DIR"
                    echo -e "${GREEN}✅ Путь успешно изменен.${NC}"
                fi
                ;;
            [Xx]) return ;;
        esac
    done
}
# ----------------------------------------------------------------------
# SWAP: УПРАВЛЕНИЕ ФАЙЛОМ ПОДКАЧКИ
# ----------------------------------------------------------------------

SWAP_FILE="/swapfile"

function create_or_resize_swap {
    echo -e "\n${CYAN}>>> ВЫБОР РАЗМЕРА SWAP-ФАЙЛА${NC}"
    echo -e "1) 1 ГБ (1024 МБ)"
    echo -e "2) 2 ГБ (2048 МБ) — Рекомендуется для VPS с 1-2 ГБ ОЗУ"
    echo -e "3) 4 ГБ (4096 МБ)"
    echo -e "4) Указать свой размер (в МБ)"
    echo -e "0) Отмена"
    read -p "Ваш выбор [1-4, 0]: " sz_choice

    local size_mb=0
    case $sz_choice in
        1) size_mb=1024 ;;
        2) size_mb=2048 ;;
        3) size_mb=4096 ;;
        4)
            read -p "Введите размер в МБ (например, 1536): " custom_mb
            if [[ ! "$custom_mb" =~ ^[0-9]+$ ]] || [ "$custom_mb" -lt 64 ]; then
                echo -e "${RED}❌ Некорректный размер (минимум 64 МБ).${NC}"
                return
            fi
            size_mb=$custom_mb
            ;;
        *) echo -e "${BLUE}Действие отменено.${NC}"; return ;;
    esac

    # Сбрасываем дисковый кэш, чтобы освободить максимум ОЗУ
    sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1

    local swap_total_kb=$(grep -i '^SwapTotal:' /proc/meminfo | awk '{print $2}')
    local swap_free_kb=$(grep -i '^SwapFree:' /proc/meminfo | awk '{print $2}')
    local swap_used_kb=$((swap_total_kb - swap_free_kb))
    local mem_avail_kb=$(grep -i '^MemAvailable:' /proc/meminfo | awk '{print $2}')

    local TEMP_SWAP="/swap_buffer.tmp"
    local need_buffer=0

    # Если в свапе есть данные и свободной ОЗУ меньше чем (Занятый Swap + 150 МБ запаса)
    if [ "$swap_used_kb" -gt 0 ] && [ "$mem_avail_kb" -lt $((swap_used_kb + 153600)) ]; then
        need_buffer=1
    fi

    local free_disk_mb=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$free_disk_mb" -le $((size_mb + 512)) ]; then
        echo -e "${RED}❌ Недостаточно места на диске! Свободно: ${free_disk_mb} МБ, требуется минимум $((size_mb + 512)) МБ.${NC}"
        return
    fi

    # Создаём временный буфер подкачки, чтобы OOM Killer не убил swapoff
    if [ "$need_buffer" -eq 1 ]; then
        local buf_mb=$(( (swap_used_kb / 1024) + 256 ))
        echo -e "${YELLOW}>>> ОЗУ заполнена. Создаём временный буфер подкачки (${buf_mb} МБ) для безопасного переноса...${NC}"
        sudo rm -f "$TEMP_SWAP"
        if ! sudo fallocate -l "${buf_mb}M" "$TEMP_SWAP" 2>/dev/null; then
            sudo dd if=/dev/zero of="$TEMP_SWAP" bs=1M count="$buf_mb" status=none
        fi
        sudo chmod 600 "$TEMP_SWAP"
        sudo mkswap "$TEMP_SWAP" > /dev/null
        sudo swapon "$TEMP_SWAP"
    fi

    if grep -q "^$SWAP_FILE " /proc/swaps; then
        echo -e "${YELLOW}>>> Отключение старого $SWAP_FILE...${NC}"
        if ! sudo swapoff "$SWAP_FILE"; then
            echo -e "${RED}❌ Не удалось отключить $SWAP_FILE (нехватка памяти).${NC}"
            [ "$need_buffer" -eq 1 ] && sudo swapoff "$TEMP_SWAP" 2>/dev/null && sudo rm -f "$TEMP_SWAP"
            return
        fi
    fi

    sudo rm -f "$SWAP_FILE"

    echo -e "${CYAN}>>> Выделение ${size_mb} МБ под $SWAP_FILE...${NC}"
    if ! sudo fallocate -l "${size_mb}M" "$SWAP_FILE" 2>/dev/null; then
        echo -e "${YELLOW}fallocate не поддерживается ФС, используем dd (подождите)...${NC}"
        sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$size_mb" status=progress
    fi

    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE" > /dev/null

    if sudo swapon "$SWAP_FILE"; then
        if ! grep -q "^$SWAP_FILE " /etc/fstab; then
            echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
        fi
        echo -e "${GREEN}✅ Swap размером ${size_mb} МБ успешно создан и активирован!${NC}"
    else
        echo -e "${RED}❌ Ошибка активации swapon.${NC}"
        sudo rm -f "$SWAP_FILE"
    fi

    # Отключаем и удаляем временный буфер (данные перетекают в новый 2 ГБ /swapfile)
    if [ "$need_buffer" -eq 1 ]; then
        echo -e "${YELLOW}>>> Перенос данных в новый Swap и удаление временного буфера...${NC}"
        sudo swapoff "$TEMP_SWAP" 2>/dev/null
        sudo rm -f "$TEMP_SWAP"
    fi
}

function manage_swap_menu {
    while true; do
        clear
        echo -e "${CYAN}--- 💾 УПРАВЛЕНИЕ ФАЙЛОМ ПОДКАЧКИ (SWAP) -----------------${NC}"
        echo -e "    Статус: [$(get_swap_status)]"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "1) 🟢  Создать / Изменить размер Swap-файла"
        echo -e "2) 🔴  Отключить и удалить Swap-файл"
        echo -e "3) 🔄  Очистить Swap (перенести данные обратно в ОЗУ)"
        echo -e "4) ⚙️   Настроить агрессивность (vm.swappiness)"
        echo -e "X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -p "Ваш выбор [1-4, X]: " sw_choice

        case $sw_choice in
            1) create_or_resize_swap ;;
            2) remove_swap ;;
            3) flush_swap ;;
            4) set_swappiness ;;
            [Xx]) return ;;
            *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
        esac
        read -p "Нажмите Enter для продолжения..."
    done
}
# ----------------------------------------------------------------------
# ГЛАВНЫЙ ЦИКЛ МЕНЮ УСТАНОВКИ (Оригинал + 2 пункта)
# ----------------------------------------------------------------------

function run_setup_menu {
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}       ⚙️  МЕНЮ НАСТРОЙКИ И ОПТИМИЗАЦИИ СЕРВЕРА ⚙️      ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        
        BBR_STATUS=$(get_bbr_status)
        PING_STATUS=$(get_ping_status)
        
        echo -e "${BLUE}--- ТЕКУЩИЕ СТАТУСЫ ----------------------------------${NC}"
        echo -e "📈  BBR:       [$(if [ "$BBR_STATUS" == "active" ]; then echo -e "${GREEN}АКТИВЕН${NC}"; else echo -e "${RED}ОТКЛЮЧЕН${NC}"; fi)]"
        echo -e "🏓  PING:      [$(if [ "$PING_STATUS" == "enabled" ]; then echo -e "${GREEN}РАЗРЕШЕН${NC}"; else echo -e "${RED}ЗАПРЕЩЕН${NC}"; fi)]"
        echo -e "🛡️   UFW:       [$(if [ "$(get_ufw_status)" == "active" ]; then echo -e "${GREEN}АКТИВЕН${NC}"; else echo -e "${RED}ОТКЛЮЧЕН${NC}"; fi)]"
        echo -e "🕒  Timezone:  [${YELLOW}$(get_timezone_status)${NC}]"
        echo -e "💾  SWAP:      [$(get_swap_status)]"
        echo -e "${BLUE}------------------------------------------------------${NC}"

       echo -e "${CYAN}1) 📈  Управление BBR (Оптимизация сети)${NC}"
        echo -e "${CYAN}2) 🏓  Управление PING (Запрет ICMP)${NC}"
        echo -e "${CYAN}3) 🛡️   Управление Файрволом (UFW)${NC}"
        echo -e "${CYAN}4) 🕒  Настройка Timezone (Часовой пояс)${NC}"
        echo -e "${CYAN}5) 🔐  Управление SSL сертификатами${NC}"
        echo -e "${YELLOW}6) ☁️   Управление Cloudflare WARP${NC}"
        echo -e "${CYAN}7) 💾  Управление Swap (Файл подкачки)${NC}"
        echo -e "${RED}X) 🔙  Назад в главное меню${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        read -p "Ваш выбор [1-6, X]: " choice
        case $choice in
            1) show_bbr_menu ;;
            2) show_ping_menu ;;
            3) show_ufw_menu ;;
            4) set_timezone_menu ;;
            5) manage_ssl_menu ;;
            6) bash /root/VPS-Server-Menu/menu_warp.sh ;;
            7) manage_swap_menu ;;
            [Xx]) return ;;
        esac
    done
}
run_setup_menu
