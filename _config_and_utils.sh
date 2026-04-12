#!/bin/bash

# ======================================================================
# ОБЩИЕ ПЕРЕМЕННЫЕ И ФУНКЦИИ ДЛЯ ВСЕХ СКРИПТОВ
# ======================================================================
# Перехват Ctrl+C (SIGINT) во всех скриптах: прерывает действие и перезапускает текущее меню
trap 'echo -e "\n${YELLOW}⚠️ Действие прервано. Возврат в меню...${NC}"; sleep 1.5; exec bash "$0"' SIGINT
# Цвета ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Определите имена и пути
HYSTERIA_SERVICE="hysteria-server.service"
SCANER_PATH="/root/RealiTLScanner-linux-64"
HYSTERIA_CONFIG="/etc/hysteria/config.yaml"
XUI_SERVICE="x-ui"

# --- ОБЩИЕ УТИЛИТЫ ---

# 1. Проверка статуса сервиса
function get_service_status() {
    # Получаем статус и обрезаем пробельные символы (включая \n) для безопасного сравнения
    sudo systemctl is-active "$1" 2>/dev/null | tr -d '[:space:]'
}

# 2. Перезапуск службы Hysteria
function restart_hysteria {
    echo -e "\n${YELLOW}Перезапуск службы Hysteria...${NC}"
    sudo systemctl restart $HYSTERIA_SERVICE
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Служба Hysteria успешно перезапущена!${NC}"
    else
        echo -e "${RED}❌ Ошибка при перезапуске службы Hysteria. Проверьте логи: journalctl -u $HYSTERIA_SERVICE${NC}"
    fi
}

# 3. Вспомогательное меню для старта/стопа сервисов
function manage_service_status_restart {
    SERVICE_NAME=$1
    
    echo -e "\n${CYAN}>>> Действия для службы $SERVICE_NAME${NC}"
    echo -e "  1) ℹ️   Статус ${GREEN}(status)${NC}"
    echo -e "  2) ▶️   Запустить ${GREEN}(start)${NC}"
    echo -e "  3) ⏹️   Остановить ${RED}(stop)${NC}"
    echo -e "  4) 🔄  Перезапустить ${YELLOW}(restart)${NC}"
    echo -e "  5) 📄  Посмотреть логи в реальном времени ${CYAN}(logs)${NC}"
    echo -e "  X) 🔙  Назад"
    
    read -p "Ваш выбор [1-5, X]: " action
    
    case $action in
        1) 
            echo -e "${BLUE}------------------------------------------------------${NC}"
            sudo systemctl status $SERVICE_NAME --no-pager 
            ;;
        2) sudo systemctl start $SERVICE_NAME && echo -e "${GREEN}✅ Запущено!${NC}" ;;
        3) sudo systemctl stop $SERVICE_NAME && echo -e "${RED}🛑 Остановлено!${NC}" ;;
        4) sudo systemctl restart $SERVICE_NAME && echo -e "${YELLOW}🔄 Перезапущено!${NC}" ;;
        5) 
            echo -e "${YELLOW}ℹ️  Открываю журнал (последние 50 строк + новые события).${NC}"
            echo -e "${GREEN}ℹ️  Для ВЫХОДА обратно в меню нажмите Ctrl+C.${NC}"
            sleep 2
            sudo journalctl -u $SERVICE_NAME -n 50 -f
            ;;
        [Xx]) return ;;
        *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
    esac
    
    echo -e "${BLUE}------------------------------------------------------${NC}"
    read -p "Нажмите Enter для возврата в меню..."
}
# 4. Получение кода статуса ядра IPv6
function get_ipv6_status_code() {
    cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null
    if [ $? -ne 0 ]; then
        echo 0 
    fi
}

# 5. Получение публичного IPv6-адреса
function get_public_ipv6 {
    local status_code=$(get_ipv6_status_code)
    
    if [ "$status_code" -eq 1 ]; then
        echo -e "${RED}Отключен${NC}"
        return
    fi
    
    # Способ 1: Получаем реальный внешний IP через API (самый надежный)
    IP_ADDR=$(curl -s -6 --max-time 2 ifconfig.me || curl -s -6 --max-time 2 api6.ipify.org)
    
    # Способ 2: Если API недоступен, парсим систему (игнорируем локальные fe80 и fd)
    if [[ -z "$IP_ADDR" ]]; then
        IP_ADDR=$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/ {print $2}' | cut -d '/' -f 1 | grep -v -i "^fe80" | grep -v -i "^fd" | head -n 1)
    fi
    
    if [[ -z "$IP_ADDR" ]]; then
        echo -e "${YELLOW}Включен, адрес не назначен${NC}"
    else
        echo -e "${GREEN}$IP_ADDR${NC}"
    fi
}
# ----------------------------------------------------------------------
# УСТАНОВКА ДОПОЛНИТЕЛЬНЫХ УТИЛИТ
# ----------------------------------------------------------------------

function check_and_install_qrencode {
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}💡 Утилита 'qrencode' не найдена.${NC}"
        read -p "$(echo -e "${YELLOW}Установить qrencode для отображения QR-кода? [Y/n]: ${NC}")" INSTALL_QR
        
        if [[ "$INSTALL_QR" =~ ^[Yy]$ || -z "$INSTALL_QR" ]]; then
            echo -e "${CYAN}>>> Запуск установки qrencode...${NC}"
            if command -v apt &> /dev/null; then
                sudo apt update -y > /dev/null 2>&1
                sudo apt install qrencode -y
            elif command -v yum &> /dev/null; then
                sudo yum install qrencode -y
            elif command -v dnf &> /dev/null; then
                sudo dnf install qrencode -y
            else
                echo -e "${RED}❌ Не удалось найти подходящий менеджер пакетов (apt, yum, dnf). Установите qrencode вручную.${NC}"
                return 1
            fi
            
            if command -v qrencode &> /dev/null; then
                echo -e "${GREEN}✅ qrencode успешно установлен.${NC}"
                return 0 # Установка успешна
            else
                echo -e "${RED}❌ Установка qrencode завершилась неудачей.${NC}"
                return 1
            fi
        fi
        return 1 # Пользователь отказался или установка не удалась
    fi
    return 0 # Уже установлен
}
