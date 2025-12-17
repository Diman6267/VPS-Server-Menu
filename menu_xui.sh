#!/bin/bash
source /usr/local/bin/_config_and_utils.sh

# ----------------------------------------------------------------------
# X-UI: УПРАВЛЕНИЕ (Вынесенный блок)
# ----------------------------------------------------------------------

function manage_xui_service {
    local SERVICE_NAME=$XUI_SERVICE
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}          🛠️  УПРАВЛЕНИЕ X-UI ПАНЕЛЬЮ 🛠️              ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        
        STATUS_XUI=$(get_service_status $SERVICE_NAME)
        
        STATUS_DISPLAY=$(if [ "$STATUS_XUI" == "active" ]; then echo -e "${GREEN}РАБОТАЕТ${NC}"; else echo -e "${RED}ОСТАНОВЛЕН${NC}"; fi)
        echo -e "${BLUE}Текущий статус: [${STATUS_DISPLAY}]${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"

        echo -e "${GREEN}1) Установить X-UI (3x-ui)${NC}"
        echo -e "${YELLOW}2) Статус / Запустить / Остановить / Перезапустить сервис${NC}"
        echo -e "${CYAN}3) Запустить панель X-UI (команда x-ui)${NC}"
        echo -e "${RED}X) Назад"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        read -p "Ваш выбор [1-3, X]: " choice
        echo ""

        case $choice in
            1)
                echo -e "${YELLOW}>>> Запуск установки 3x-ui...${NC}"
                bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
                ;;
            2) 
                manage_service_status_restart $SERVICE_NAME
                ;;
            3)
                echo -e "${YELLOW}Запускаю X-UI... (Для выхода из X-UI используйте Ctrl+C)${NC}"
                if command -v x-ui &> /dev/null; then
                    x-ui
                elif [ -f "/usr/local/bin/x-ui" ]; then
                    /usr/local/bin/x-ui
                elif [ -f "/usr/bin/x-ui" ]; then
                     /usr/bin/x-ui
                else
                    echo -e "${RED}Команда x-ui не найдена.${NC}"
                fi
                read -p "Нажмите Enter для возврата в меню..."
                ;;
            [Xx]) return ;;
            *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
        esac
        read -p "Нажмите Enter для продолжения..."
    done
}
manage_xui_service
