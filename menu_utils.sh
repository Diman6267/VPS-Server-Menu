#!/bin/bash
if [ -f "/root/VPS-Server-Menu/_config_and_utils.sh" ]; then
    source /root/VPS-Server-Menu/_config_and_utils.sh
elif [ -f "/usr/local/bin/_config_and_utils.sh" ]; then
    source /usr/local/bin/_config_and_utils.sh
fi

# Функция проверки и установки зависимостей
function check_utils_deps {
    local deps=("htop" "ncdu" "nethogs" "mtr")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}>>> Установка недостающих утилит: ${missing[*]}...${NC}"
        apt-get update >/dev/null 2>&1
        apt-get install -y "${missing[@]}" >/dev/null 2>&1
        echo -e "${GREEN}✅ Утилиты установлены.${NC}"
        sleep 1
    fi
}

function run_utils_menu {
    check_utils_deps
    
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}               🛠️  СИСТЕМНЫЕ УТИЛИТЫ 🛠️               ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${GREEN}1) 📊 Мониторинг ресурсов (htop)${NC}"
        echo -e "${GREEN}2) 💾 Анализ места на диске (ncdu)${NC}"
        echo -e "${GREEN}3) 🚦 Мониторинг сетевого трафика (nethogs)${NC}"
        echo -e "${GREEN}4) 🌍 Внешний IP сервера (IPv4 / IPv6)${NC}"
        echo -e "${GREEN}5) 📡 Пинг и трассировка (ping / mtr)${NC}"
        echo -e "${GREEN}6) 🔓 Активные порты (ss)${NC}"
        echo -e "${RED}7) 💀 Завершение процессов (kill)${NC}"
        echo -e "${YELLOW}8) 🧹 Очистка системы (кэш, старые ядра, логи)${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e "${RED}X) 🔙  Назад в главное меню${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        read -p "Ваш выбор: " choice
        case $choice in
            1)
                htop
                ;;
            2)
                echo -e "\n${CYAN}--- Параметры сканирования (ncdu) ---${NC}"
                echo -e "1) Весь диск (/)"
                echo -e "2) Системные логи (/var/log)"
                echo -e "3) Текущая папка ($(pwd))"
                echo -e "4) Ввести путь вручную"
                read -p "Выбор: " ncdu_opt
                case $ncdu_opt in
                    1) ncdu / ;;
                    2) ncdu /var/log ;;
                    3) ncdu . ;;
                    4) read -p "Введите путь: " custom_path; if [ -d "$custom_path" ]; then ncdu "$custom_path"; else echo -e "${RED}Папка не найдена.${NC}"; sleep 2; fi ;;
                esac
                ;;
            3)
                echo -e "\n${CYAN}--- Доступные интерфейсы ---${NC}"
                # Получаем список интерфейсов, исключая loopback (lo)
                ip -br link show | awk '{print $1}' | grep -v "^lo$" | awk '{print NR ") " $1}'
                echo -e "A) Все сразу"
                read -p "Выберите интерфейс: " net_opt
                if [[ "$net_opt" =~ ^[Aa]$ ]]; then
                    nethogs
                elif [[ "$net_opt" =~ ^[0-9]+$ ]]; then
                    iface=$(ip -br link show | awk '{print $1}' | grep -v "^lo$" | sed -n "${net_opt}p")
                    if [ -n "$iface" ]; then
                        nethogs "$iface"
                    else
                        echo -e "${RED}Неверный выбор.${NC}"; sleep 1
                    fi
                fi
                ;;
            4)
                echo -e "\n${CYAN}--- Проверка IP ---${NC}"
                echo -e "${YELLOW}IPv4:${NC} $(curl -4 -s -m 4 ifconfig.me || echo 'Недоступен')"
                echo -e "${YELLOW}IPv6:${NC} $(curl -6 -s -m 4 ifconfig.me || echo 'Недоступен')"
                read -p "Нажмите Enter..."
                ;;
            5)
                echo -e "\n${CYAN}--- Пинг и Трассировка ---${NC}"
                read -p "Введите IP или домен (например, 8.8.8.8 или google.com): " target
                if [ -z "$target" ]; then continue; fi
                echo -e "1) Обычный ping (4 пакета)"
                echo -e "2) Непрерывный ping (Ctrl+C для выхода)"
                echo -e "3) Трассировка MTR (в реальном времени)"
                read -p "Выбор: " ping_opt
                case $ping_opt in
                    1) ping -c 4 "$target" ;;
                    2) ping "$target" ;;
                    3) mtr "$target" ;;
                esac
                read -p "Нажмите Enter..."
                ;;
            6)
                echo -e "\n${CYAN}--- Активные порты (ss) ---${NC}"
                echo -e "1) Только TCP-порты"
                echo -e "2) Только UDP-порты"
                echo -e "3) Все активные порты (TCP + UDP)"
                read -p "Выбор: " port_opt
                echo ""
                case $port_opt in
                    1) ss -tlpn ;;
                    2) ss -ulpn ;;
                    3) ss -tulpn ;;
                esac
                echo ""
                read -p "Нажмите Enter..."
                ;;
            7)
                echo -e "\n${CYAN}--- Завершение процессов ---${NC}"
                echo -e "1) Найти процесс по имени (узнать PID)"
                echo -e "2) Убить по точному PID (kill -9)"
                echo -e "3) Убить все процессы по имени (killall -9)"
                read -p "Выбор: " kill_opt
                case $kill_opt in
                    1)
                        read -p "Введите часть имени: " s_name
                        echo -e "${YELLOW}Найденные процессы:${NC}"
                        ps aux | grep -i "$s_name" | grep -v "grep" | awk '{print "PID: " $2 " | Владелец: " $1 " | Команда: " $11}'
                        ;;
                    2)
                        read -p "Введите PID: " k_pid
                        if kill -9 "$k_pid" 2>/dev/null; then echo -e "${GREEN}Процесс $k_pid жестоко убит.${NC}"; else echo -e "${RED}Ошибка: Процесс не найден или нет прав.${NC}"; fi
                        ;;
                    3)
                        read -p "Введите точное имя (например, nginx): " k_name
                        if killall -9 "$k_name" 2>/dev/null; then echo -e "${GREEN}Процессы $k_name убиты.${NC}"; else echo -e "${RED}Процесс не найден.${NC}"; fi
                        ;;
                esac
                read -p "Нажмите Enter..."
                ;;
            8)
                echo -e "\n${CYAN}--- Очистка системы ---${NC}"
                echo -e "1) Очистить кэш скачанных пакетов (apt clean)"
                echo -e "2) Удалить ненужные зависимости (apt autoremove)"
                echo -e "3) Очистить системные логи (оставить за последние 3 дня)"
                echo -e "4) 🚀 Выполнить всё сразу"
                read -p "Выбор: " clean_opt
                case $clean_opt in
                    1) apt-get clean; echo -e "${GREEN}Кэш APT очищен.${NC}" ;;
                    2) DEBIAN_FRONTEND=noninteractive apt-get autoremove -y; echo -e "${GREEN}Зависимости очищены.${NC}" ;;
                    3) journalctl --vacuum-time=3d; echo -e "${GREEN}Старые логи удалены.${NC}" ;;
                    4) 
                       apt-get clean
                       DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
                       journalctl --vacuum-time=3d
                       echo -e "${GREEN}Полная очистка завершена! Место освобождено.${NC}"
                       ;;
                esac
                read -p "Нажмите Enter..."
                ;;
            [Xx])
                return
                ;;
            *) continue ;;
        esac
    done
}

run_utils_menu
