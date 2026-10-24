#!/bin/bash
if [ -f "/root/VPS-Server-Menu/_config_and_utils.sh" ]; then
    source /root/VPS-Server-Menu/_config_and_utils.sh
elif [ -f "/usr/local/bin/_config_and_utils.sh" ]; then
    source /usr/local/bin/_config_and_utils.sh
fi

# ----------------------------------------------------------------------
# УПРАВЛЕНИЕ CLOUDFLARE WARP
# ----------------------------------------------------------------------

function get_warp_status {
    if ! command -v warp-cli &> /dev/null; then
        echo -e "${RED}НЕ УСТАНОВЛЕН${NC}"
    elif systemctl is-active --quiet warp-svc; then
        echo -e "${GREEN}АКТИВЕН (только systemd)${NC}"
    else
        echo -e "${YELLOW}ОСТАНОВЛЕН${NC}"
    fi
}

function filter_warp_cron {
    awk '!(NF >= 8 && $1 !~ /^#/ && $6 == "systemctl" && $7 == "restart" && $8 == "warp-svc")'
}

function update_warp_cron_rule {
    local cron_rule="${1:-}" existing filtered
    if ! existing=$(LC_ALL=C crontab -l 2>&1); then
        case "$existing" in
            *'no crontab for '*) existing='' ;;
            *) echo 'Не удалось прочитать crontab; расписание не изменено.' >&2; return 1 ;;
        esac
    fi
    filtered=$(printf '%s\n' "$existing" | filter_warp_cron)
    {
        [ -z "$filtered" ] || printf '%s\n' "$filtered"
        [ -z "$cron_rule" ] || printf '%s\n' "$cron_rule"
    } | crontab - || {
        echo 'Не удалось применить crontab; прежнее расписание сохранено.' >&2
        return 1
    }
}

function setup_warp_cron {
    local cron_choice cron_rule custom_cron
    while true; do
        clear
        echo -e "${CYAN}--- 🔄 НАСТРОЙКА АВТОПЕРЕЗАПУСКА WARP --------------------${NC}"
        echo -e "    Текущий статус: $(get_warp_cron_status)"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "1) 🌙  Каждую ночь (в 03:00)"
        echo -e "2) 📅  Раз в неделю (в Воскресенье ночью)"
        echo -e "3) ⏳  Каждые 12 часов"
        echo -e "4) 🚫  Отключить автоперезапуск"
        echo -e "5) ✍️   Задать свой график (формат Cron)"
        echo -e "X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -r -p "Выбор: " cron_choice
        case $cron_choice in
            1) cron_rule="0 3 * * * systemctl restart warp-svc >/dev/null 2>&1" ;;
            2) cron_rule="0 3 * * 0 systemctl restart warp-svc >/dev/null 2>&1" ;;
            3) cron_rule="0 */12 * * * systemctl restart warp-svc >/dev/null 2>&1" ;;
            4)
                if update_warp_cron_rule ''; then
                    echo -e "${GREEN}✅ Отключено.${NC}"; sleep 1; return
                fi
                sleep 2; continue ;;
            5)
                echo -e "\n${CYAN}╭─── Справка по формату Cron ──────────────────────╮${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}* * * * *${NC}                                       ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ │ │ │${NC}                                       ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ │ │ └${NC} День недели (0-7, где 0 или 7 это Вс) ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ │ └────${NC} Месяц (1-12)                        ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ └──────${NC} День месяца (1-31)                  ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ └────────${NC} Часы (0-23)                         ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}└──────────${NC} Минуты (0-59)                       ${CYAN}│${NC}"
                echo -e "${CYAN}╰──────────────────────────────────────────────────╯${NC}"
                echo -e "${YELLOW}Доступные форматы: ${GREEN}*${NC} (все), ${GREEN}1-5${NC} (диапазон), ${GREEN}6,0${NC} (список), ${GREEN}*/10${NC} (шаг)"
                echo -e "${YELLOW}Популярные примеры:${NC}"
                echo -e "  ${GREEN}0 5 * * *${NC}    (Каждый день ровно в 05:00)"
                echo -e "  ${GREEN}*/30 * * * *${NC} (Каждые 30 минут)"
                echo -e "  ${GREEN}0 2 * * 1-5${NC}  (По будням в 02:00)"
                echo -e "  ${GREEN}0 12 * * 6,0${NC} (По выходным в 12:00)"
                echo ""
                read -r -p "Ваш график (5 значений через пробел): " custom_cron
                
                # Простая проверка: должно быть ровно 5 "слов" (значений)
                if [[ $(echo "$custom_cron" | wc -w) -eq 5 ]]; then
                    cron_rule="$custom_cron systemctl restart warp-svc >/dev/null 2>&1"
                else
                    echo -e "${RED}❌ Ошибка! Нужно ввести ровно 5 значений (например: 0 4 * * *).${NC}"
                    sleep 2
                    continue
                fi
                ;;
            [Xx]) return ;;
            *) continue ;;
        esac
        
        # Применяем правило
        if update_warp_cron_rule "$cron_rule"; then
            echo -e "${GREEN}✅ Расписание обновлено!${NC}"; sleep 1; return
        fi
        sleep 2
    done
}


function get_warp_cron_status {
    local cron_rule
    cron_rule=$(crontab -l 2>/dev/null | awk 'NF >= 8 && $1 !~ /^#/ && $6 == "systemctl" && $7 == "restart" && $8 == "warp-svc" {print; exit}')
    
    if [ -z "$cron_rule" ]; then
        echo -e "${RED}ВЫКЛЮЧЕН${NC}"
        return
    fi

    local m=$(echo "$cron_rule" | awk '{print $1}')
    local h=$(echo "$cron_rule" | awk '{print $2}')
    local d=$(echo "$cron_rule" | awk '{print $3}')
    local mon=$(echo "$cron_rule" | awk '{print $4}')
    local dow=$(echo "$cron_rule" | awk '{print $5}')

    # 0. Ежеминутно (* * * * * или * * * * 0-7)
    if [[ "$m" == "*" && "$h" == "*" && "$d" == "*" && "$mon" == "*" && ("$dow" == "*" || "$dow" == "0-7") ]]; then
        echo -e "${GREEN}Каждую минуту (Осторожно!)${NC}"

    # 1. Ежедневно в определенное время (0 2 * * * или 0 2 * * 0-7)
    elif [[ "$d" == "*" && "$mon" == "*" && ("$dow" == "*" || "$dow" == "0-7") && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$((10#$h))" "$((10#$m))"
        echo -e "${GREEN}Ежедневно в $formatted_time${NC}"

    # 2. По будням (например, 0 2 * * 1-5)
    elif [[ "$d" == "*" && "$mon" == "*" && "$dow" == "1-5" && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$((10#$h))" "$((10#$m))"
        echo -e "${GREEN}По будням в $formatted_time${NC}"

    # 3. По выходным (например, 0 2 * * 6,0 или 6,7)
    elif [[ "$d" == "*" && "$mon" == "*" && ("$dow" == "6,0" || "$dow" == "0,6" || "$dow" == "6,7") && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$((10#$h))" "$((10#$m))"
        echo -e "${GREEN}По выходным в $formatted_time${NC}"

    # 4. Раз в неделю (конкретный день, например 0 3 * * 0)
    elif [[ "$d" == "*" && "$mon" == "*" && "$dow" =~ ^[0-7]$ && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$((10#$h))" "$((10#$m))"
        local days=("Вс" "Пн" "Вт" "Ср" "Чт" "Пт" "Сб" "Вс")
        echo -e "${GREEN}Раз в неделю (${days[$dow]} $formatted_time)${NC}"

    # 5. Ежемесячно (например, 0 5 15 * * -> 15-го числа)
    elif [[ "$d" =~ ^[0-9]+$ && "$mon" == "*" && "$dow" == "*" && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$((10#$h))" "$((10#$m))"
        echo -e "${GREEN}Каждое $d-е число в $formatted_time${NC}"

    # 6. Точная дата / Ежегодно (например, 23 4 21 3 * -> 21 Марта в 04:23)
    elif [[ "$d" =~ ^[0-9]+$ && "$mon" =~ ^[0-9]+$ && "$dow" == "*" && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$((10#$h))" "$((10#$m))"
        local months=("" "Января" "Февраля" "Марта" "Апреля" "Мая" "Июня" "Июля" "Августа" "Сентября" "Октября" "Ноября" "Декабря")
        echo -e "${GREEN}Ежегодно $d ${months[$((10#$mon))]} в $formatted_time${NC}"

    # 7. Каждые X часов (например, 0 */12 * * *)
    elif [[ "$h" == */* && "$m" =~ ^[0-9]+$ && "$d" == "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        local hours=${h#*/}
        echo -e "${GREEN}Каждые $hours ч.${NC}"

    # 8. Каждые X минут (например, */30 * * * *)
    elif [[ "$m" == */* && "$h" == "*" && "$d" == "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        local mins=${m#*/}
        echo -e "${GREEN}Каждые $mins мин.${NC}"

    # 9. Если кастомный (совсем сложная комбинация)
    else
        echo -e "${GREEN}Свой график ($m $h $d $mon $dow)${NC}"
    fi
}

# WARPSCOUT работает отдельно от официального warp-cli / warp-svc.
function install_warpscout() (
    local installer
    umask 077
    installer=$(mktemp) || return 1
    trap 'rm -f -- "$installer"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}❌ Для установки WARPSCOUT нужен curl (apt install curl).${NC}"
        return 1
    fi
    echo -e "${CYAN}>>> Загрузка официального installer WARPSCOUT...${NC}"
    if ! curl -fSL --connect-timeout 15 --max-time 120 \
        https://raw.githubusercontent.com/vernette/warpscout/master/install.sh -o "$installer"; then
        echo -e "${RED}❌ Не удалось загрузить installer с GitHub. Повторите позже.${NC}"
        return 1
    fi
    # Повторный запуск обновляет бинарник; актуальная версия остаётся на месте.
    INSTALL_DIR=/usr/local/bin sh "$installer" --yes || return "$?"
    /usr/local/bin/warpscout version
)

function prepare_warpscout_data {
    if ! (umask 077; mkdir -p -- "$warpscout_dir") || ! chmod 700 "$warpscout_dir"; then
        echo -e "${RED}❌ Не удалось подготовить каталог: ${warpscout_dir}${NC}"
        return 1
    fi
    if [ -f "$warpscout_account" ] && ! chmod 600 "$warpscout_account"; then
        echo -e "${RED}❌ Не удалось защитить account: ${warpscout_account}${NC}"
        return 1
    fi
}

function show_warpscout_status {
    local version
    if [ ! -x "$warpscout_bin" ]; then
        echo -e "📦 WARPSCOUT: ${RED}НЕ УСТАНОВЛЕН${NC}"
    elif version=$("$warpscout_bin" version); then
        printf '%b%s%b\n' "📦 WARPSCOUT: ${GREEN}" "$version" "$NC"
    else
        echo -e "📦 WARPSCOUT: ${RED}ОШИБКА ЗАПУСКА — повторите установку${NC}"
    fi
    if [ -s "$warpscout_account" ] && [ -r "$warpscout_account" ]; then
        echo -e "🔑 Account: ${GREEN}ФАЙЛ НАЙДЕН${NC}"
    else
        echo -e "🔑 Account: ${YELLOW}ОТСУТСТВУЕТ / ПУСТ / НЕДОСТУПЕН${NC}"
    fi
    printf '   %s\n' "$warpscout_account"
}

function run_warpscout_command() (
    # Изменения cwd/umask и обработчиков сигналов не затрагивают родительское меню.
    trap - INT
    umask 077
    cd -- "$warpscout_dir" || return 1
    "$warpscout_bin" "$@"
)

function register_warpscout_account {
    # upstream register при повторном запуске меняет ключи. Здесь только создание.
    if [ -e "$warpscout_account" ] || [ -L "$warpscout_account" ]; then
        echo -e "${YELLOW}Account уже существует и сохранён без изменений.${NC}"
        printf 'Путь: %s\n' "$warpscout_account"
        echo "Для ручного управления используйте warpscout register -h."
        return 0
    fi
    if run_warpscout_command register -a "$warpscout_account"; then
        if [ -s "$warpscout_account" ]; then
            echo -e "${GREEN}✅ Account создан: ${warpscout_account}${NC}"
            return 0
        fi
        echo -e "${RED}❌ WARPSCOUT не создал account file.${NC}"
        return 1
    else
        return "$?"
    fi
}

function scan_warpscout_endpoints {
    local mode="$1" result_dir result=0
    local -a scan_args
    if [ ! -s "$warpscout_account" ] || [ ! -r "$warpscout_account" ]; then
        echo -e "${YELLOW}Сначала создайте account (пункт 2).${NC}"
        return 1
    fi
    result_dir=$(mktemp -d "$warpscout_dir/scan-$(date +%Y%m%d-%H%M%S)-XXXXXX") || return 1
    scan_args=(scan -a "$warpscout_account" -p awg -P -exclude-node DME -o "$result_dir/report.txt")
    case "$mode" in
        best) scan_args+=(-best) ;;
        config) scan_args+=(-conf "$result_dir/warp.conf") ;;
    esac
    echo -e "${CYAN}>>> AWG scan с проверкой туннеля, без узла DME.${NC}"
    echo "Проверяется сеть этой VPS. Каждый пункт запускает новый scan."
    echo "Ctrl+C — остановить scan и вернуться в меню (возможны частичные результаты)."
    printf 'Каталог результатов: %s\n' "$result_dir"
    run_warpscout_command "${scan_args[@]}" || result=$?
    if [ -s "$result_dir/report.txt" ]; then
        printf 'Отчёт: %s\n' "$result_dir/report.txt"
    elif [ "$result" -eq 0 ]; then
        echo -e "${RED}❌ Отчёт не был сохранён.${NC}"
        result=1
    fi
    if [ "$mode" = config ]; then
        if [ -s "$result_dir/warp.conf" ]; then
            printf 'AmneziaWG config: %s\n' "$result_dir/warp.conf"
        elif [ "$result" -eq 0 ]; then
            echo -e "${RED}❌ Config не был создан.${NC}"
            result=1
        fi
    fi
    return "$result"
}

function run_warpscout_menu {
    local warpscout_bin="/usr/local/bin/warpscout"
    local warpscout_dir="/root/.config/warpscout"
    local warpscout_account="$warpscout_dir/warpscout-account.json"
    local warpscout_choice result
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}             🛰️  ADVANCED WARPSCOUT / AmneziaWG             ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        show_warpscout_status
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e "${GREEN}1) 🚀  Установить / Обновить WARPSCOUT${NC}"
        echo -e "${YELLOW}2) 🔑  Создать WARP account (если отсутствует)${NC}"
        echo -e "${YELLOW}3) 🔎  Рекомендуемый scan (AWG, ping, без DME)${NC}"
        echo -e "${YELLOW}4) 🏆  Найти лучший endpoint (новый scan)${NC}"
        echo -e "${YELLOW}5) 📄  Создать AmneziaWG config (новый scan)${NC}"
        echo -e "${CYAN}6) ℹ️   Проверить статус / Наличие account${NC}"
        echo -e "${RED}X) 🔙  Назад в Endpoint Manager${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        read -r -p "Ваш выбор: " warpscout_choice || return 0
        result=0
        case "$warpscout_choice" in
            1) install_warpscout || result=$? ;;
            2|3|4|5)
                if [ ! -x "$warpscout_bin" ]; then
                    echo -e "${YELLOW}Сначала установите WARPSCOUT (пункт 1).${NC}"
                elif prepare_warpscout_data; then
                    case "$warpscout_choice" in
                        2) register_warpscout_account || result=$? ;;
                        3) scan_warpscout_endpoints scan || result=$? ;;
                        4) scan_warpscout_endpoints best || result=$? ;;
                        5) scan_warpscout_endpoints config || result=$? ;;
                    esac
                fi
                ;;
            6) show_warpscout_status ;;
            [Xx]) return 0 ;;
            *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
        esac
        if [ "$result" -eq 130 ]; then
            echo -e "${YELLOW}Операция прервана.${NC}"
        elif [ "$result" -ne 0 ]; then
            echo -e "${RED}❌ Операция WARPSCOUT завершилась с кодом ${result}. См. сообщения выше.${NC}"
        fi
        read -r -p "Нажмите Enter для возврата в WARPSCOUT menu..." || return 0
    done
}

# JSON CLI проверен с Cloudflare WARP 2026.8.2110.0. Неизвестная схема — отказ от изменений.
function warp_cli {
    local output result=0
    output=$(LC_ALL=C timeout --kill-after=2 8 warp-cli --accept-tos --json "$@") || result=$?
    if [ "$result" -ne 0 ]; then
        printf '%s\n' "$output" >&2
        return "$result"
    fi
    printf '%s\n' "$output"
}

# registration show is the readiness probe: only a known response may authorize
# an initial registration. Never include CLI output (which may contain IDs) in UI.
function warp_registration_state {
    local output rc=0 code
    output=$(warp_cli registration show 2>&1) || rc=$?
    if jq -e 'type == "object" and (.code | type == "string")' \
        <<< "$output" >/dev/null 2>&1; then
        code=$(jq -r '.code' <<< "$output")
        case "$code" in
            MissingRegistration) echo missing ;;
            FailedToConnectToDaemon) echo daemon-unavailable ;;
            *) echo unknown ;;
        esac
    elif [ "$rc" -eq 0 ]; then
        if jq -e 'type == "object" and (has("code") | not) and
            ((.id | type == "string" and length > 0) or
             (.registration_id | type == "string" and length > 0))' \
            <<< "$output" >/dev/null 2>&1; then
            echo present
        else
            echo unknown
        fi
    elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        echo daemon-unavailable
    else
        # Narrow compatibility fallback for older non-JSON CLI output.
        case "$output" in
            'No registration'|'Registration missing'|'Not registered') echo missing ;;
            *) echo unknown ;;
        esac
    fi
}

function wait_warp_registration_state {
    local attempt state
    for ((attempt=0; attempt<5; attempt++)); do
        state=$(warp_registration_state)
        case "$state" in
            present|missing) printf '%s\n' "$state"; return 0 ;;
            daemon-unavailable)
                if [ "$attempt" -lt 4 ]; then sleep 2; fi ;;
            *) echo 'Неизвестный ответ WARP CLI; проверьте warp-cli status и journalctl -u warp-svc.' >&2; return 1 ;;
        esac
    done
    echo 'WARP daemon недоступен через CLI; проверьте systemctl status warp-svc и journalctl -u warp-svc.' >&2
    return 1
}

function warp_auto_schema_known {
    # В settings/sources контракте Option override отсутствует в обеих картах для AUTO.
    # При иной структуре или неизвестном endpoint-поле не предполагаем AUTO.
    jq -e '. as $root | .settings as $s | .sources as $sources |
        if ($sources | type != "object") then false else
        (["always_on", "operation_mode", "proxy_port", "warp_tunnel_protocol"] |
            all(. as $key | ($sources[$key] | type == "string" and length > 0))) and
        ([$s, $sources] | all(keys | all(test("endpoint"; "i") | not))) and
        ($root | keys | sort == ["settings", "sources"]) end' <<< "$warp_settings" >/dev/null
}

function read_warp_state {
    warp_settings='' warp_status='' warp_protocol='' warp_endpoint='' warp_port='' warp_mode=''
    command -v warp-cli >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 &&
        command -v timeout >/dev/null 2>&1 || return 1
    systemctl is-active --quiet warp-svc || return 1
    warp_settings=$(warp_cli settings) || return 1
    # Отсутствующий override в этой схеме означает AUTO; неизвестную схему не принимаем за AUTO.
    jq -e '.settings | type == "object" and
        (.operation_mode | type == "string") and
        (.always_on | type == "boolean") and
        (.warp_tunnel_protocol == "masque" or .warp_tunnel_protocol == "wireguard") and
        (if .operation_mode == "proxy" then
            (.proxy_port | type == "number" and . >= 1 and . <= 65535 and floor == .)
         else
            ((has("proxy_port") | not) or
             (.proxy_port | type == "number" and . >= 1 and . <= 65535 and floor == .))
         end) and
        ((has("override_warp_endpoint") | not) or
          (.override_warp_endpoint | type == "string" and length > 0))' \
        <<< "$warp_settings" >/dev/null || return 1
    warp_mode=$(jq -r '.settings.operation_mode' <<< "$warp_settings")
    warp_protocol=$(jq -r '.settings.warp_tunnel_protocol' <<< "$warp_settings")
    if jq -e '.settings | has("override_warp_endpoint")' <<< "$warp_settings" >/dev/null; then
        warp_endpoint=$(jq -r '.settings.override_warp_endpoint' <<< "$warp_settings")
    elif warp_auto_schema_known; then
        warp_endpoint=AUTO
    else
        warp_endpoint=UNKNOWN
    fi
    warp_port=$(jq -r '.settings.proxy_port // empty' <<< "$warp_settings")
    warp_status=$(warp_cli status | jq -er '.status | select(type == "string")') || return 1
}

function show_warp_connection {
    local registration_state package_state='не подтверждён'
    if command -v dpkg-query >/dev/null 2>&1; then
        package_state='не установлен'
        if dpkg-query -W -f='${Status}' cloudflare-warp 2>/dev/null |
            grep -qx 'install ok installed'; then
            package_state='установлен'
        fi
    fi
    printf '📦 Пакет WARP: %s\n' "$package_state"
    if ! command -v warp-cli >/dev/null 2>&1; then
        echo '⚙️ warp-svc: не проверен'
        echo '🔌 CLI/daemon: недоступен'
        echo '🪪 Регистрация: не определена'
        echo '🔗 Туннель / SOCKS5: не определены'
        return
    fi
    printf '⚙️ warp-svc: %s\n' "$(get_warp_status)"
    if ! systemctl is-active --quiet warp-svc; then
        echo '🔌 CLI/daemon: не проверен (служба остановлена)'
        echo '🪪 Регистрация: не определена'
        echo '🔗 Туннель / SOCKS5: не определены'
        return
    fi
    registration_state=$(warp_registration_state)
    case "$registration_state" in
        present) echo '🔌 CLI/daemon: доступен'; echo '🪪 Регистрация: есть' ;;
        missing) echo '🔌 CLI/daemon: доступен'; echo '🪪 Регистрация: отсутствует' ;;
        daemon-unavailable) echo '🔌 CLI/daemon: недоступен'; echo '🪪 Регистрация: не определена' ;;
        *) echo '🔌 CLI/daemon: ответ не распознан'; echo '🪪 Регистрация: не определена' ;;
    esac
    if [ "$registration_state" = present ] && read_warp_state 2>/dev/null; then
        local endpoint_display="$warp_endpoint"
        [ "$endpoint_display" != UNKNOWN ] || endpoint_display="UNKNOWN (неизвестная схема override)"
        local transport='не подтверждён (нужен подключённый MASQUE/QUIC)'
        if get_warp_scan_profile quiet; then transport='MASQUE / QUIC'; fi
        printf '🔗 Туннель: %s\n🌐 Transport: %s\n🎯 Endpoint: %s\n🔌 SOCKS5: 127.0.0.1:%s (mode: %s)\n' \
            "$warp_status" "$transport" "$endpoint_display" "$warp_port" "$warp_mode"
        check_warp_health quiet 2>/dev/null || true
        printf '❤️ WARP: %s — %s\n' "$warp_health" "$warp_health_detail"
    else
        echo -e "${YELLOW}🔗 Туннель / Протокол / Endpoint / SOCKS5: не определены${NC}"
    fi
}

function check_warp_health {
    local trace key value listener_rows expected_port="${WARP_HEALTH_EXPECTED_PORT:-}"
    warp_exit_ip='' warp_colo='' warp_location=''
    warp_health=DOWN
    warp_health_detail="warp-cli отсутствует или warp-svc не активен"
    if command -v warp-cli >/dev/null 2>&1 && systemctl is-active --quiet warp-svc; then
        warp_health=DEGRADED
        warp_health_detail="Невозможно прочитать JSON state (нужны jq, timeout и совместимый warp-cli)"
        if read_warp_state; then
            warp_health=DOWN
            warp_health_detail="Туннель: $warp_status; mode: $warp_mode"
            if [ -n "$expected_port" ] && [ "$warp_port" != "$expected_port" ]; then
                warp_health_detail="SOCKS5 port: $warp_port; требуется: $expected_port"
            elif [ "$warp_status" = Connected ] && [ "$warp_mode" = proxy ]; then
                warp_health_detail="SOCKS5 listener 127.0.0.1:$warp_port отсутствует или порт открыт публично"
                if ! command -v ss >/dev/null 2>&1; then
                    warp_health=DEGRADED
                    warp_health_detail="Нужен ss для проверки SOCKS5 listener"
                elif ! listener_rows=$(ss -H -lnt "sport = :$warp_port" 2>/dev/null); then
                    warp_health=DEGRADED
                    warp_health_detail="Не удалось проверить SOCKS5 listener"
                elif printf '%s\n' "$listener_rows" | awk -v port="$warp_port" '
                    $4 == "127.0.0.1:" port || $4 == "[::1]:" port {found=1; next}
                    NF {public=1}
                    END {exit !(found && !public)}'; then
                    warp_health=DEGRADED
                    warp_health_detail="SOCKS5 trace недоступен (нужен curl)"
                    if command -v curl >/dev/null 2>&1 && trace=$(curl --disable -fsS \
                        --connect-timeout 4 --max-time 10 --noproxy "" \
                        --proxy "socks5h://127.0.0.1:$warp_port" https://www.cloudflare.com/cdn-cgi/trace); then
                        local warp_flag='' exit_ip='' colo='' location=''
                        while IFS='=' read -r key value; do
                            case "$key" in
                                warp) warp_flag="$value" ;;
                                ip) exit_ip="$value" ;;
                                colo) colo="$value" ;;
                                loc) location="$value" ;;
                            esac
                        done <<< "$trace"
                        warp_health_detail="warp=${warp_flag:-unknown}; IP=${exit_ip:-unknown}; colo=${colo:-unknown}; loc=${location:-unknown}"
                        warp_exit_ip="$exit_ip" warp_colo="$colo" warp_location="$location"
                        [ "$warp_flag" != on ] || warp_health=HEALTHY
                    fi
                fi
            fi
        fi
    fi
    if [ "${1:-}" != quiet ]; then print_warp_health; fi
    [ "$warp_health" = HEALTHY ]
}

function warp_health_exit_code {
    case "$warp_health" in
        HEALTHY) return 0 ;;
        DEGRADED) return 2 ;;
        DOWN|*) return 3 ;;
    esac
}

function print_warp_health_json {
    if ! command -v jq >/dev/null 2>&1; then
        python3 - "$warp_health" "$warp_health_detail" "${warp_mode:-}" "${warp_port:-}" \
            "${warp_endpoint:-}" "${warp_exit_ip:-}" "${warp_colo:-}" "${warp_location:-}" <<'PY'
import json, sys
status, reason, mode, port, endpoint, ip, colo, location = sys.argv[1:]
print(json.dumps(dict(status=status, reason=reason, mode=mode,
    port=int(port) if port.isdigit() else None, endpoint=endpoint,
    exitIp=ip, colo=colo, location=location), separators=(',', ':')))
PY
        return
    fi
    jq -Mc -n --arg status "$warp_health" --arg reason "$warp_health_detail" \
        --arg mode "${warp_mode:-}" --arg port "${warp_port:-}" \
        --arg endpoint "${warp_endpoint:-}" --arg exit_ip "${warp_exit_ip:-}" \
        --arg colo "${warp_colo:-}" --arg location "${warp_location:-}" \
        '{status:$status,reason:$reason,mode:$mode,port:($port|tonumber? // null),
          endpoint:$endpoint,exitIp:$exit_ip,colo:$colo,location:$location}'
}

function print_warp_health {
    case "$warp_health" in
        HEALTHY) echo -e "${GREEN}❤️  WARP HEALTHY${NC}" ;;
        DEGRADED) echo -e "${YELLOW}❤️  WARP DEGRADED${NC}" ;;
        DOWN) echo -e "${RED}❤️  WARP DOWN${NC}" ;;
    esac
    printf '%s\n' "$warp_health_detail"
}

function wait_warp_health {
    local attempt
    for ((attempt=0; attempt<6; attempt++)); do
        if check_warp_health quiet; then
            if [ "${1:-}" != quiet ]; then print_warp_health; fi
            return 0
        fi
        sleep 2
    done
    if [ "${1:-}" != quiet ]; then print_warp_health; fi
    return 1
}

function normalize_warp_endpoint {
    # ipaddress проверяет IPv4/IPv6 полностью, включая сжатые и IPv4-mapped адреса.
    command -v python3 >/dev/null 2>&1 || { echo "Нужен python3 для проверки endpoint." >&2; return 1; }
    python3 - "$1" <<'PY'
import ipaddress, re, sys
match = re.fullmatch(r'(?:\[([^\]]+)\]|([^:]+)):([0-9]{1,5})', sys.argv[1])
try:
    if not match:
        raise ValueError()
    addr = ipaddress.ip_address(match[1] or match[2])
    port = int(match[3])
    if bool(match[1]) != (addr.version == 6) or not 1 <= port <= 65535 or '%' in str(addr):
        raise ValueError()
except ValueError:
    print('Нужен IPv4:PORT или [IPv6]:PORT, порт 1–65535.', file=sys.stderr)
    sys.exit(1)
print(f'[{addr}]:{port}' if addr.version == 6 else f'{addr}:{port}')
PY
}

function validate_warp_endpoint {
    normalize_warp_endpoint "$1" >/dev/null
}

function set_warp_endpoint {
    if [ "$1" = AUTO ]; then
        warp_cli tunnel endpoint reset >/dev/null
    else
        warp_cli tunnel endpoint set "$1" >/dev/null
    fi
}

function warp_config_matches {
    local expected="$1" expected_endpoint actual_endpoint
    read_warp_state || return 1
    expected_endpoint=$(jq -r '.endpoint' <<< "$expected")
    actual_endpoint="$warp_endpoint"
    if [ "$expected_endpoint" != AUTO ] && [ "$actual_endpoint" != AUTO ]; then
        expected_endpoint=$(normalize_warp_endpoint "$expected_endpoint") || return 1
        actual_endpoint=$(normalize_warp_endpoint "$actual_endpoint") || return 1
    fi
    [ "$expected_endpoint" = "$actual_endpoint" ] || return 1
    jq -e --argjson expected "$expected" '
        .settings as $s | $expected | .mode == $s.operation_mode and
        .port == $s.proxy_port and .protocol == $s.warp_tunnel_protocol' <<< "$warp_settings" >/dev/null
}

function rollback_warp_change {
    [ "$warp_pending" -eq 1 ] || return 0
    # Повторный Ctrl+C не должен оборвать восстановление посередине.
    trap '' INT TERM
    local failed=0
    echo -e "${YELLOW}Изменение не прошло проверку. Восстанавливаю прежние настройки WARP...${NC}"
    warp_cli disconnect >/dev/null || failed=1
    warp_cli mode proxy >/dev/null || failed=1
    warp_cli proxy port "$(jq -r '.port' <<< "$warp_before")" >/dev/null || failed=1
    warp_cli tunnel protocol set "$(jq -r '.protocol | if . == "masque" then "MASQUE" else "WireGuard" end' <<< "$warp_before")" >/dev/null || failed=1
    set_warp_endpoint "$(jq -r '.endpoint' <<< "$warp_before")" || failed=1
    if [ "$(jq -r '.connected' <<< "$warp_before")" = true ]; then
        warp_cli connect >/dev/null || failed=1
        wait_warp_health || failed=1
    else
        warp_cli disconnect >/dev/null || failed=1
        check_warp_health || true
        echo "До изменения WARP был отключён; восстановлено отключённое состояние."
        read_warp_state && [ "$warp_status" = Disconnected ] || failed=1
    fi
    warp_config_matches "$warp_before" || failed=1
    if [ "$failed" -eq 0 ]; then
        echo -e "${GREEN}✅ Rollback завершён.${NC}"
    else
        echo -e "${RED}❌ Rollback не подтверждён полностью. Проверьте warp-cli status и журнал warp-svc.${NC}"
    fi
}

function apply_warp_change() (
    local action="$1" value="$2" optimization_mode="${3:-}" metrics="${4:-}" warp_before warp_target warp_pending=0 dependency
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    # Сериализуем изменения из разных экземпляров меню; state хранится только в памяти.
    for dependency in jq timeout curl ss python3 flock; do
        command -v "$dependency" >/dev/null 2>&1 || { printf 'Нужна команда: %s\n' "$dependency"; return 1; }
    done
    exec 9>>"${WARP_LOCK_FILE:-/run/lock/vps-server-menu-warp.lock}" || return 1
    flock -n 9 || { echo "Другое меню уже меняет настройки WARP."; return 1; }
    if ! read_warp_state || [ "$warp_mode" != proxy ]; then
        echo -e "${RED}Нужен активный warp-svc с известным JSON state и mode proxy.${NC}"
        return 1
    fi
    if [ "$warp_endpoint" = UNKNOWN ]; then
        echo "Текущий endpoint/AUTO в этой версии CLI не подтверждён; безопасный rollback невозможен."
        return 1
    fi
    warp_cli tunnel endpoint set --help >/dev/null && warp_cli tunnel endpoint reset --help >/dev/null &&
        warp_cli tunnel protocol set --help >/dev/null || return 1
    warp_before=$(jq -c --arg endpoint "$warp_endpoint" '.settings | {mode:.operation_mode,port:.proxy_port,
        protocol:.warp_tunnel_protocol,endpoint:$endpoint,connected:.always_on}' <<< "$warp_settings") || return 1
    warp_target="$warp_before"
    case "$action" in
        endpoint)
            if [ "$value" != AUTO ]; then value=$(normalize_warp_endpoint "$value") || return 1; fi
            warp_target=$(jq -c --arg value "$value" '.endpoint=$value' <<< "$warp_target") ;;
        protocol)
            # Runtime: proxy mode в текущем warp-svc поддерживает только MASQUE/QUIC.
            [ "$value" = masque ] || { echo "WireGuard недоступен в SOCKS5 proxy mode."; return 1; }
            warp_target=$(jq -c '.protocol="masque" | .endpoint="AUTO"' <<< "$warp_target") ;;
        port)
            if ! [[ "$value" =~ ^[0-9]{1,5}$ ]] || [ "$((10#$value))" -lt 1 ] || [ "$((10#$value))" -gt 65535 ]; then
                echo "Нужен SOCKS5 порт 1–65535."
                return 1
            fi
            warp_target=$(jq -c --argjson value "$((10#$value))" '.port=$value' <<< "$warp_target") ;;
        *) return 1 ;;
    esac
    [ "$(jq -r '.protocol' <<< "$warp_target")" = masque ] || {
        echo "Proxy mode требует MASQUE; текущий протокол не поддерживается."; return 1;
    }
    trap 'rollback_warp_change' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    warp_pending=1
    warp_cli disconnect >/dev/null || return 1
    case "$action" in
        protocol) warp_cli tunnel protocol set MASQUE >/dev/null || return 1 ;;
        port) warp_cli proxy port "$value" >/dev/null || return 1 ;;
    esac
    if [ "$action" != port ]; then
        set_warp_endpoint "$(jq -r '.endpoint' <<< "$warp_target")" || return 1
    fi
    warp_cli connect >/dev/null || return 1
    if wait_warp_health quiet && warp_config_matches "$warp_target"; then
        warp_pending=0
        echo -e "${GREEN}✅ Настройки применены; SOCKS5 trace подтвердил warp=on.${NC}"
        if [ -n "$optimization_mode" ]; then
            print_warp_candidate "$optimization_mode" "$warp_endpoint" "$metrics"
            printf 'SOCKS5:      127.0.0.1:%s\nWARP:        %s\nExit IP:     %s\nColo:        %s\nLocation:    %s\n' \
                "$warp_port" "$warp_health" "${warp_exit_ip:-не определён}" "${warp_colo:-не определён}" "${warp_location:-не определена}"
        else
            print_warp_health
        fi
        return 0
    fi
    return 1
)

function get_warp_scan_profile {
    local stats
    # Версия сама по себе не доказывает transport. Нужны фактические UDP stats и SNI.
    stats=$(warp_cli tunnel stats) || stats='{}'
    if [ "$(jq -r '.protocol // ""' <<< "$stats")" = 'MASQUE (HTTPS via UDP)' ]; then
        warp_scan_sni=$(jq -er '.tls.sni | select(type == "string" and test("^[a-zA-Z0-9.-]+$"))' <<< "$stats") || return 1
        return 0
    fi
    if [ "${1:-}" != quiet ]; then
        echo "Transport official proxy не подтверждён как MASQUE/QUIC; автоматический scan отменён."
    fi
    return 1
}

function read_warp_candidate_metrics {
    # Только plain report upstream, первая таблица рабочих endpoint, точное совпадение.
    # Отсутствующий/изменённый/частичный report влияет лишь на отображение метрик.
    python3 - "$1" "$2" <<'PYMETRICS'
import json, math, pathlib, re, sys
metrics = dict(speed=None, ping=None, loss=None)
try:
    lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
    rows, started, speed = [], False, False
    header = r'ENDPOINT\s+ENDPOINT PING\s+TUN PING\s+LOSS(\s+SPEED)?\s+SEEN AS\s+NODE\s+NODE LOCATION'
    for line in lines:
        if not started:
            match = re.fullmatch(header, line.strip())
            if match:
                started, speed = True, bool(match[1])
            continue
        if not line.strip() or line.lstrip().startswith('#'):
            break
        fields = line.split()
        if fields and fields[0] == sys.argv[2]:
            rows.append(fields)
    if len(rows) == 1:
        row = rows[0]
        # Нужен полный ряд: endpoint, endpoint ping, tunnel ping, loss, [speed], country/node/location.
        offset = (2 if len(row) > 5 and row[5] == 'Mbps' else 1) if speed else 0
        if len(row) >= 7 + offset:
            if re.fullmatch(r'(?:[0-9]+(?:\.[0-9]+)?)(?:ns|µs|us|ms|s)', row[2]):
                metrics['ping'] = row[2]
            if re.fullmatch(r'[0-9]+(?:\.[0-9]+)?%', row[3]) and 0 <= float(row[3][:-1]) <= 100:
                metrics['loss'] = row[3]
            if speed and offset == 2 and re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', row[4]):
                value = float(row[4])
                if math.isfinite(value) and value > 0:
                    metrics['speed'] = row[4] + ' Mbps'
except (OSError, UnicodeError, ValueError):
    pass
print(json.dumps(metrics))
PYMETRICS
}

function print_warp_candidate {
    local label='Минимальная задержка / стабильность'
    [ "$1" != speed ] || label='Максимальная скорость'
    printf '\nРежим:       %s\nEndpoint:    %s\n' "$label" "$2"
    jq -r '"Speed:       " + (.speed // "не измерялась / недоступна"),
        "Tunnel ping: " + (.ping // "недоступен"), "Loss:        " + (.loss // "недоступны")' <<< "$3"
}

function scan_official_warp_candidate {
    local mode="$1" result_dir="$2"
    local args=(scan -a "$warpscout_account" -p masque -P -best -plain
        -masque-sni "$warp_scan_sni" -o "$result_dir/report.txt")
    case "$mode" in
        speed) args+=(-best-by speed) ;;
        latency) ;;
        *) return 1 ;;
    esac
    if ! run_warpscout_command "${args[@]}" > "$result_dir/best.txt"; then
        echo -e "${RED}Scan не завершился успешно; WARP не изменён.${NC}"
        return 1
    fi
    warp_candidate_endpoint=$(cat "$result_dir/best.txt")
    validate_warp_endpoint "$warp_candidate_endpoint" || return 1
    warp_candidate_metrics=$(read_warp_candidate_metrics "$result_dir/report.txt" "$warp_candidate_endpoint") ||
        warp_candidate_metrics='{"speed":null,"ping":null,"loss":null}'
    printf 'Отчёт: %s (если сохранён WARPSCOUT)\n' "$result_dir/report.txt"
}

function generate_warp_xray_outbound {
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    if ! read_warp_state || [ "$warp_mode" != proxy ]; then
        echo 'Нужен WARP в proxy mode с известным SOCKS5 портом.' >&2
        return 1
    fi
    jq -Mn --argjson port "$warp_port" '{tag:"warp-outbound",protocol:"socks",
        settings:{servers:[{address:"127.0.0.1",port:$port,users:[]}]}}'
}

function show_warp_xray_outbound {
    generate_warp_xray_outbound || return 1
    echo 'Добавьте этот outbound в Xray/3x-ui и направьте нужные routing rules на tag "warp-outbound".'
}

function optimize_warp_endpoint {
    local mode="${1:-speed}" warp_candidate_endpoint warp_candidate_metrics
    local warpscout_bin="/usr/local/bin/warpscout" warpscout_dir="/root/.config/warpscout"
    local warpscout_account="$warpscout_dir/warpscout-account.json" answer result_dir warp_scan_sni
    case "$mode" in speed|latency) ;; *) return 1 ;; esac
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    if ! read_warp_state || [ "$warp_mode" != proxy ]; then
        echo "Нужен активный WARP в mode proxy."
        return 1
    fi
    if [ "$warp_protocol" != masque ]; then
        echo "Текущий протокол SOCKS5 proxy не поддерживается; для поиска нужен MASQUE/QUIC."
        return 1
    fi
    get_warp_scan_profile || return 1
    if [ ! -x "$warpscout_bin" ]; then
        read -r -p "Установить WARPSCOUT для поиска endpoint? [y/N]: " answer || return 1
        [[ "$answer" =~ ^[Yy]$ ]] || return 1
        install_warpscout || return 1
    fi
    prepare_warpscout_data || return 1
    if [ ! -s "$warpscout_account" ]; then
        read -r -p "Создать отдельный WARPSCOUT account? [y/N]: " answer || return 1
        [[ "$answer" =~ ^[Yy]$ ]] || return 1
        register_warpscout_account || return 1
    fi
    result_dir=$(mktemp -d "$warpscout_dir/official-$(date +%Y%m%d-%H%M%S)-XXXXXX") || return 1
    echo -e "${CYAN}>>> MASQUE/QUIC scan для official SOCKS5 WARP; смена Cloudflare node не гарантируется.${NC}"
    printf 'Результаты: %s\n' "$result_dir"
    scan_official_warp_candidate "$mode" "$result_dir" || return 1
    # Protocol мог измениться из другого shell за время scan: проверяем повторно.
    read_warp_state && [ "$warp_protocol" = masque ] && [ "$warp_mode" = proxy ] || return 1
    print_warp_candidate "$mode" "$warp_candidate_endpoint" "$warp_candidate_metrics"
    apply_warp_change endpoint "$warp_candidate_endpoint" "$mode" "$warp_candidate_metrics"
}

function run_warp_endpoint_menu {
    local endpoint_choice endpoint
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    local warpscout_bin="/usr/local/bin/warpscout" warpscout_dir="/root/.config/warpscout"
    local warpscout_account="$warpscout_dir/warpscout-account.json"
    while true; do
        clear
        echo -e "${CYAN}--- 🎯 WARP ENDPOINT MANAGER / WARPSCOUT ---------------${NC}"
        show_warp_connection
        show_warpscout_status
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo "1) ⚡ Найти самый быстрый endpoint (рекомендуется)"
        echo "2) 🎯 Минимальная задержка / стабильность"
        echo "3) ✍️  Задать endpoint вручную"
        echo "4) 🔄 Вернуть Cloudflare AUTO"
        echo "5) ❤️  Проверить здоровье WARP"
        echo "6) 📋 Показать outbound для 3x-ui / Xray"
        echo "7) 🛰️  Advanced WARPSCOUT (standalone AWG / AmneziaWG)"
        echo "X) 🔙 Назад в WARP menu"
        read -r -p "Ваш выбор: " endpoint_choice || return 0
        case "$endpoint_choice" in
            1) optimize_warp_endpoint speed || true ;;
            2) optimize_warp_endpoint latency || true ;;
            3)
                read -r -p "Endpoint (IPv4:PORT или [IPv6]:PORT; Enter — отмена): " endpoint || return 0
                [ -z "$endpoint" ] || apply_warp_change endpoint "$endpoint"
                ;;
            4) apply_warp_change endpoint AUTO || true ;;
            5) check_warp_health || true ;;
            6) show_warp_xray_outbound || true ;;
            7) run_warpscout_menu ;;
            [Xx]) return 0 ;;
            *) echo -e "${RED}Неверный ввод.${NC}" ;;
        esac
        read -r -p "Нажмите Enter для возврата в Endpoint Manager..." || return 0
    done
}

function offer_warp_endpoint_recovery {
    local answer warp_scan_sni
    if ! get_warp_scan_profile quiet; then
        echo 'WARP установлен, но transport profile не удалось подтвердить. Автоматический подбор endpoint через WARPSCOUT сейчас недоступен. Проверьте warp-cli status и журнал warp-svc.'
        return 1
    fi
    read -r -p "Попробовать подобрать endpoint через WARPSCOUT? [y/N]: " answer || return 1
    [[ "$answer" =~ ^[Yy]$ ]] || return 1
    optimize_warp_endpoint
}

function install_official_warp() (
    local requested_port="${1:-40000}" noninteractive="${2:-0}" key_file='' codename
    local registration_state status_output current_status
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    if ! [[ "$requested_port" =~ ^[0-9]{1,5}$ ]] ||
        [ "$((10#$requested_port))" -lt 1 ] || [ "$((10#$requested_port))" -gt 65535 ]; then
        echo "Нужен SOCKS5 порт 1–65535." >&2
        return 64
    fi
    export WARP_HEALTH_EXPECTED_PORT="$requested_port"
    if command -v warp-cli >/dev/null 2>&1 && check_warp_health quiet 2>/dev/null; then
        if [ "$noninteractive" -eq 1 ]; then
            echo "WARP already HEALTHY; configuration unchanged." >&2
        else
            print_warp_health
        fi
        return 0
    fi
    trap '[ -z "$key_file" ] || rm -f -- "$key_file"' EXIT
    trap 'exit 130' INT
    if ! command -v warp-cli >/dev/null 2>&1; then
        echo -e "${CYAN}>>> Установка официального Cloudflare WARP...${NC}"
        if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 update &&
                DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y \
                    --no-install-recommends curl gpg ca-certificates || return 1
        fi
        key_file=$(mktemp) || return 1
        codename=$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}") || return 1
        if ! [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]]; then
            echo 'Не удалось определить поддерживаемый codename системы.' >&2
            return 1
        fi
        curl -fSL --connect-timeout 15 --max-time 120 https://pkg.cloudflareclient.com/pubkey.gpg -o "$key_file" &&
            gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "$key_file" || return 1
        chmod 644 /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg || return 1
        printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' \
            "$codename" > /etc/apt/sources.list.d/cloudflare-client.list || return 1
        DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 update &&
            DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y \
                --no-install-recommends cloudflare-warp jq python3 || return 1
        hash -r
    fi
    if ! systemctl is-enabled --quiet warp-svc; then
        systemctl enable warp-svc || return 1
    fi
    if ! systemctl is-active --quiet warp-svc; then
        systemctl start warp-svc || return 1
    fi
    registration_state=$(wait_warp_registration_state) || return 1
    if [ "$registration_state" = missing ]; then
        # Cloudflare's initial sequence registers before configuring or connecting.
        if ! warp_cli registration new >/dev/null 2>&1; then
            echo 'Не удалось создать регистрацию WARP; проверьте warp-cli status и journalctl -u warp-svc.' >&2
            return 1
        fi
        registration_state=$(wait_warp_registration_state) || return 1
        if [ "$registration_state" != present ]; then
            echo 'Создание регистрации WARP не подтверждено; настройки не изменены.' >&2
            return 1
        fi
    fi
    if ! read_warp_state 2>/dev/null; then
        echo "Невозможно достоверно прочитать настройки WARP; изменения остановлены." >&2
        return 1
    fi
    # A connected proxy is only interrupted when its mode or port must change.
    if [ "$warp_mode" != proxy ] || [ "$warp_port" != "$requested_port" ]; then
        if [ "$warp_status" = Connected ]; then
            warp_cli disconnect >/dev/null || return 1
        fi
        if [ "$warp_mode" != proxy ]; then
            warp_cli mode proxy >/dev/null || return 1
        fi
        if [ "$warp_port" != "$requested_port" ]; then
            warp_cli proxy port "$requested_port" >/dev/null || return 1
        fi
    fi
    status_output=$(warp_cli status 2>/dev/null) || return 1
    current_status=$(jq -er '.status | select(type == "string")' <<< "$status_output") || return 1
    if [ "$current_status" != Connected ] && ! warp_cli connect >/dev/null; then
        echo -e "${RED}WARP установлен, но connect не завершён.${NC}"
        return 1
    fi
    # A periodic restart is not required for a healthy daemon. The interactive
    # schedule editor remains available, but installation never adds a cron job.
    if [ "$noninteractive" -eq 1 ]; then return 0; fi
    if wait_warp_health; then
        echo -e "${GREEN}✅ WARP установлен; SOCKS5 127.0.0.1:${requested_port} проверен.${NC}"
    else
        echo -e "${YELLOW}WARP установлен, но tunnel/proxy health check не пройден.${NC}"
        # WARPSCOUT remains a manual Endpoint Manager action. AUTO health
        # failures are never followed by an unsolicited scanner run.
        echo "Откройте Endpoint Manager вручную, если требуется диагностика endpoint."
        return 1
    fi
)

function warp_cli_api_usage {
    cat <<'EOF'
Usage:
  server-menu warp install [--port PORT] [--json]
  server-menu warp health [--port PORT] [--json]
  server-menu warp xray-outbound

Health exit codes: 0 HEALTHY, 2 DEGRADED, 3 DOWN, 64 usage error.
Install exit codes: 0 successful operation and HEALTHY, 1 operation failure,
2 DEGRADED or 3 DOWN after a successful operation, 64 usage error.
EOF
}

function run_warp_cli_api {
    local command="${1:-}" requested_port=40000 json=0 WARP_HEALTH_EXPECTED_PORT=''
    local install_result=0 health_result=0
    [ "$#" -gt 0 ] && shift
    case "$command" in
        install|health)
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --port) shift; requested_port="${1:-}" ;;
                    --json) json=1 ;;
                    -h|--help) warp_cli_api_usage; return 0 ;;
                    *) printf 'Unknown argument: %s\n' "$1" >&2; warp_cli_api_usage >&2; return 64 ;;
                esac
                shift
            done
            if ! [[ "$requested_port" =~ ^[0-9]{1,5}$ ]] ||
                [ "$((10#$requested_port))" -lt 1 ] || [ "$((10#$requested_port))" -gt 65535 ]; then
                echo "Нужен SOCKS5 порт 1–65535." >&2
                return 64
            fi
            if [ "$command" = install ]; then
                if [ "$json" -eq 1 ]; then
                    install_official_warp "$requested_port" 1 >&2 || install_result=$?
                else
                    install_official_warp "$requested_port" 1 || install_result=$?
                fi
                if [ "$install_result" -eq 0 ]; then
                    WARP_HEALTH_EXPECTED_PORT="$requested_port" wait_warp_health quiet || true
                fi
            fi
            WARP_HEALTH_EXPECTED_PORT="$requested_port"
            check_warp_health quiet || true
            warp_health_exit_code || health_result=$?
            if [ "$json" -eq 1 ]; then
                if [ "$command" = install ]; then
                    if command -v jq >/dev/null 2>&1; then
                        print_warp_health_json | jq -Mc --argjson result "$install_result" \
                            '. + {operation:{success:($result == 0),exitCode:$result}}'
                    else
                        print_warp_health_json | python3 -c 'import json,sys; data=json.load(sys.stdin); rc=int(sys.argv[1]); data["operation"]={"success":rc==0,"exitCode":rc}; print(json.dumps(data,separators=(",",":")))' "$install_result"
                    fi
                else
                    print_warp_health_json
                fi
            else
                print_warp_health
            fi
            if [ "$install_result" -ne 0 ]; then return 1; fi
            return "$health_result"
            ;;
        xray-outbound)
            [ "$#" -eq 0 ] || { warp_cli_api_usage >&2; return 64; }
            generate_warp_xray_outbound
            ;;
        -h|--help|'') warp_cli_api_usage ;;
        *) printf 'Unknown WARP command: %s\n' "$command" >&2; warp_cli_api_usage >&2; return 64 ;;
    esac
}

function run_warp_menu {
    local choice new_port conf
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}             ☁️  УПРАВЛЕНИЕ CLOUDFLARE WARP ☁️             ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        show_warp_connection
        echo -e "🔄 Авторестарт:   $(get_warp_cron_status)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e "${GREEN}1) 🚀  Установить WARP (режим SOCKS5)${NC}"
        echo -e "${YELLOW}2) ⚙️   Изменить порт прокси${NC}"
        echo -e "${YELLOW}3) 🔄  Настроить расписание автоперезапуска${NC}"
        echo -e "${YELLOW}4) 🛑  Остановить / Запустить службу${NC}"
        echo -e "${YELLOW}5) 📄  Просмотр логов (в реальном времени)${NC}"
        echo -e "${RED}6) 🗑️   Полностью удалить WARP из системы${NC}"
        echo -e "${CYAN}7) 🎯  Endpoint Manager / WARPSCOUT${NC}"
        echo -e "${CYAN}8) ❤️   Проверить здоровье WARP${NC}"
        echo -e "${RED}X) 🔙  Назад в предыдущее меню${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        read -r -p "Ваш выбор: " choice || return 0
        case $choice in
            1)
                trap ':' INT
                install_official_warp || echo -e "${YELLOW}Установка/проверка WARP не завершена успешно.${NC}"
                read -r -p "Нажмите Enter..."
                trap - INT
                ;;
            2)
                read -r -p "Новый SOCKS5 порт (1–65535): " new_port
                trap ':' INT
                apply_warp_change port "$new_port" || true
                read -r -p "Нажмите Enter..."
                trap - INT
                ;;
            3) setup_warp_cron ;;
            4)
                if systemctl is-active --quiet warp-svc; then
                    systemctl stop warp-svc
                else
                    systemctl start warp-svc
                fi ;;
            5)
                echo -e "${CYAN}>>> Просмотр логов warp-svc (Ctrl+C для выхода)...${NC}"
                sleep 1
                trap ' ' INT
                journalctl -eu warp-svc -f
                trap - INT
                ;;
            6)
                if ! command -v warp-cli &> /dev/null; then
                    echo -e "${RED}WARP не установлен.${NC}"; read -p "Enter..."; continue
                fi
                read -p "⚠️  Вы уверены, что хотите ПОЛНОСТЬЮ удалить WARP? (y/N): " conf
                if [[ "$conf" =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}Остановка и очистка...${NC}"
                    warp-cli --accept-tos disconnect >/dev/null 2>&1
                    systemctl disable --now warp-svc >/dev/null 2>&1
                    
                    if DEBIAN_FRONTEND=noninteractive apt-get purge -y cloudflare-warp >/dev/null 2>&1; then
                        rm -f /etc/apt/sources.list.d/cloudflare-client.list
                        rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
                        update_warp_cron_rule '' || true
                        hash -r 
                        echo -e "${GREEN}✅ WARP полностью удален из системы.${NC}"
                    else
                        echo -e "${RED}❌ Не удалось удалить пакет WARP через APT. Проверьте состояние apt/dpkg.${NC}"
                    fi
                fi
                read -p "Нажмите Enter..." ;;
            7)
                trap ':' INT
                run_warp_endpoint_menu
                trap - INT
                ;;
            8)
                trap ':' INT
                check_warp_health || true
                read -r -p "Нажмите Enter..."
                trap - INT
                ;;
            [Xx]) return ;;
        esac
    done
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [ "${1:-}" = --cli ]; then
        shift
        run_warp_cli_api "$@"
    else
        run_warp_menu
    fi
fi
