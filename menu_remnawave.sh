#!/bin/bash

# ======================================================================
# МЕНЮ УПРАВЛЕНИЯ REMNAWAVE (На базе DigneZzZ/remnawave-scripts)
# ======================================================================

source /usr/local/bin/_config_and_utils.sh

GITHUB_BASE="https://github.com/DigneZzZ/remnawave-scripts/raw/main"
MIRROR_BASE="https://cdn.jsdelivr.net/gh/DigneZzZ/remnawave-scripts@main"

# Функция запуска скриптов DigneZzZ с автопереключением на зеркало jsDelivr
function run_dignezzz {
    local script_name="$1"
    shift
    local args="$@"

    echo -e "${CYAN}>>> Загрузка ${script_name} (${args})...${NC}"
    if curl -ILsf --connect-timeout 5 "${GITHUB_BASE}/${script_name}" >/dev/null 2>&1; then
        bash <(curl -Ls "${GITHUB_BASE}/${script_name}") @ $args
    else
        echo -e "${YELLOW}⚠️ GitHub недоступен, используем зеркало jsDelivr...${NC}"
        bash <(curl -Ls "${MIRROR_BASE}/${script_name}") @ $args
    fi
}

function get_container_status {
    local name="$1"
    if command -v docker &>/dev/null && sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -Eq "^${name}$"; then
        echo -e "${GREEN}РАБОТАЕТ${NC}"
    elif command -v docker &>/dev/null && sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Eq "^${name}$"; then
        echo -e "${YELLOW}Остановлен${NC}"
    else
        echo -e "${RED}Не установлен${NC}"
    fi
}

function show_rw_menu {
    [ -f /root/VPS-Server-Menu/patch_full_backup.py ] && python3 /root/VPS-Server-Menu/patch_full_backup.py >/dev/null 2>&1
    clear
    local st_panel=$(get_container_status "remnawave")
    local st_sub=$(get_container_status "remnawave-subscription-page")
    local st_node=$(get_container_status "remnanode")
    local st_steal=$(get_container_status "caddy|remnawave-selfsteal|selfsteal")
    if [[ "$st_steal" == *"Не установлен"* ]] && systemctl is-active --quiet caddy 2>/dev/null; then
        st_steal="${GREEN}РАБОТАЕТ (Systemd)${NC}"
    fi
    local st_bot=$(get_container_status "remnawave-admin-bot-1")

    local cli_rw=$(command -v remnawave &>/dev/null && echo -e "${GREEN}Установлен${NC}" || echo -e "${YELLOW}Нет${NC}")
    local cli_node=$(command -v remnanode &>/dev/null && echo -e "${GREEN}Установлен${NC}" || echo -e "${YELLOW}Нет${NC}")
    local cli_steal=$(command -v selfsteal &>/dev/null && echo -e "${GREEN}Установлен${NC}" || (systemctl is-active --quiet caddy 2>/dev/null && echo -e "${GREEN}Systemd${NC}" || echo -e "${YELLOW}Нет${NC}"))

    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}           🌊  УПРАВЛЕНИЕ REMNAWAVE  🌊               ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${BLUE}--- СТАТУС КОНТЕЙНЕРОВ -------------------------------${NC}"
    echo -e "  🖥️   Панель (remnawave):       [$st_panel]"
    echo -e "  📄  Страница подписок:        [$st_sub]"
    echo -e "  🛰️   Нода (remnanode):         [$st_node]"
    echo -e "  🔒  Selfsteal (Caddy):        [$st_steal]"
    echo -e "  🤖  Админ-бот (Case211):      [$st_bot]"
    echo -e "${BLUE}--- УТИЛИТЫ DIGNEZZZ CLI -----------------------------${NC}"
    echo -e "  remnawave: [$cli_rw] | remnanode: [$cli_node] | selfsteal: [$cli_steal]"
    echo -e "${BLUE}------------------------------------------------------${NC}"
    echo -e "${GREEN}--- 🛰️  НОДА (REMNANODE) ---${NC}"
    echo -e "${YELLOW}1) 🚀  Установить Ноду с нуля (DigneZzZ Installer)${NC}"
    echo -e "${YELLOW}2) 🎛️   Открыть меню Ноды (remnanode CLI)${NC}"
    echo -e "${YELLOW}3) 🔄  Перезапустить контейнер remnanode и показать логи${NC}"
    echo ""
    echo -e "${GREEN}--- 🖥️  ПАНЕЛЬ И ПОДПИСКИ (REMNAWAVE PANEL) ---${NC}"
    echo -e "${YELLOW}4) 🚀  Установить Панель с нуля (DigneZzZ Installer)${NC}"
    echo -e "${YELLOW}5) 🎛️   Открыть меню Панели (remnawave CLI: бэкапы/апдейт/боты)${NC}"
    echo -e "${YELLOW}6) 📦  Создать бэкап Панели (remnawave backup)${NC}"
    echo -e "${YELLOW}7) 🔄  Перезапустить стек Панели (/opt/remnawave)${NC}"
    echo ""
    echo -e "${GREEN}--- 🎭  МАСКИРОВКА И ДОП. МОДУЛИ ---${NC}"
    echo -e "${CYAN}8) 🔒  Caddy Selfsteal — установка и меню маскировки Reality${NC}"
    echo -e "${CYAN}9) 🌐  WARP & Tor Manager для Xray (wtm)${NC}"
    echo -e "${CYAN}10) 🤖 Перезапустить Админ-бота (/opt/remnawave-admin)
11) ♻️  Восстановить доп. стек из бэкапа (Caddy + Бот Case211 + Нода)${NC}"
    echo ""
    echo -e "${RED}0) 🔙  Назад в главное меню${NC}"
    echo -e "${BLUE}------------------------------------------------------${NC}"
}

while true; do
    show_rw_menu
    PROMPT=$(echo -e "${CYAN}Ваш выбор: ${NC}")
    read -p "$PROMPT" rw_choice

    case $rw_choice in
        1)
            run_dignezzz "remnanode.sh" "install"
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            if ! command -v remnanode &>/dev/null; then
                echo -e "${YELLOW}Устанавливаем CLI-обёртку remnanode...${NC}"
                run_dignezzz "remnanode.sh" "install-script"
            fi
            sudo remnanode
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            if [ -d /opt/remnanode ]; then
                cd /opt/remnanode && docker compose restart && docker compose logs --tail=30
            else
                docker restart remnanode && docker logs --tail=30 remnanode
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        4)
            run_dignezzz "remnawave.sh" "install"
            read -p "Нажмите Enter для продолжения..."
            ;;
        5)
            if ! command -v remnawave &>/dev/null; then
                echo -e "${YELLOW}Устанавливаем CLI-обёртку remnawave...${NC}"
                run_dignezzz "remnawave.sh" "install-script"
            fi
            sudo remnawave
            read -p "Нажмите Enter для продолжения..."
            ;;
        6)
            if ! command -v remnawave &>/dev/null; then
                run_dignezzz "remnawave.sh" "install-script"
            fi
            sudo remnawave backup
            read -p "Нажмите Enter для продолжения..."
            ;;
        7)
            if [ -d /opt/remnawave ]; then
                echo -e "${YELLOW}>>> Перезапуск контейнеров в /opt/remnawave...${NC}"
                cd /opt/remnawave && docker compose restart && docker compose ps
            else
                echo -e "${RED}❌ Директория /opt/remnawave не найдена.${NC}"
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        8)
            if command -v selfsteal &>/dev/null; then
                sudo selfsteal
            else
                echo -e "${YELLOW}CLI selfsteal ещё не установлен. Выберите действие:${NC}"
                echo "  1) 🚀 Установить Caddy Selfsteal с нуля (@ install)"
                echo "  2) 🎛️ Только поставить CLI и открыть меню"
                read -p "Ваш выбор [1-2, Enter=1]: " st_act
                if [ "$st_act" == "2" ]; then
                    run_dignezzz "selfsteal.sh" "install-script"
                    sudo selfsteal
                else
                    run_dignezzz "selfsteal.sh" "install"
                fi
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        9)
            if ! command -v wtm &>/dev/null; then
                echo -e "${YELLOW}Устанавливаем CLI wtm (WARP & Tor Manager)...${NC}"
                run_dignezzz "wtm.sh" "install-script"
            fi
            sudo wtm
            read -p "Нажмите Enter для продолжения..."
            ;;
        10)
            if [ -d /opt/remnawave-admin ]; then
                echo -e "${YELLOW}>>> Перезапуск стека remnawave-admin...${NC}"
                cd /opt/remnawave-admin && docker compose restart && docker compose ps
            else
                echo -e "${RED}❌ Директория /opt/remnawave-admin не найдена.${NC}"
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        11)
            echo -e "\n${CYAN}♻️  Поиск последнего полного бэкапа...${NC}"
            latest_archive=$(ls -t /opt/remnawave/backups/*.tar.gz /root/remnawave_scheduled_*.tar.gz 2>/dev/null | head -n 1)
            if [ -z "$latest_archive" ]; then
                read -rp "Архивы не найдены. Укажите полный путь к файлу .tar.gz: " latest_archive
            else
                echo -e "Найден архив: ${GREEN}${latest_archive}${NC}"
                read -rp "Использовать его для восстановления Caddy, Бота и Ноды? (Y/n): " confirm_rest
                if [[ "$confirm_rest" =~ ^[Nn]$ ]]; then
                    read -rp "Укажите полный путь к нужному архиву .tar.gz: " latest_archive
                fi
            fi
            if [ -f "$latest_archive" ]; then
                tmp_rest="/tmp/rw_full_restore_$$"
                mkdir -p "$tmp_rest"
                tar xzf "$latest_archive" -C "$tmp_rest"
                restore_script=$(find "$tmp_rest" -name "restore-full-stack.sh" | head -n 1)
                if [ -n "$restore_script" ]; then
                    bash "$restore_script"
                else
                    echo -e "${RED}❌ В выбранном архиве нет блока restore-full-stack.sh (это старый архив).${NC}"
                fi
                rm -rf "$tmp_rest"
            else
                echo -e "${RED}❌ Файл архива не найден: ${latest_archive}${NC}"
            fi
            read -p "Нажмите Enter для продолжения..."
            ;;
        0|[QqXx])
            break
            ;;
        *)
            echo -e "${RED}❌ Неверный ввод.${NC}"
            sleep 1
            ;;
    esac
done
