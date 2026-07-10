#!/bin/bash

# ============================================
# Just Remnawave Auto Installer
# Author: tneangel
# Repository: https://github.com/tneange1/Just-Remnawave-Auto-Installer
# ============================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ошибка: Скрипт нужно запускать от имени root (sudo).${NC}"
    exit 1
fi

# Создание глобального алиаса rw-installer
create_alias() {
    if [ ! -f /usr/local/bin/rw-installer ]; then
        echo -e "${YELLOW}📥 Скачиваем скрипт для глобального доступа...${NC}"
        curl -Ls https://raw.githubusercontent.com/tneange1/Just-Remnawave-Auto-Installer/main/setup.sh -o /usr/local/bin/rw-installer
        chmod +x /usr/local/bin/rw-installer
        echo -e "${GREEN}✅ Создан глобальный алиас: теперь можно запускать командой ${BOLD}rw-installer${NC}${GREEN} из любой директории.${NC}"
    fi
}

# Логотип
show_logo() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════╗"
    echo "  ║   ⚡ Just Remnawave Auto Installer by tneangel    ║"
    echo "  ╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Проверка и установка Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}🐳 Docker не найден. Устанавливаем...${NC}"
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}✅ Docker успешно установлен.${NC}"
    else
        echo -e "${GREEN}✅ Docker уже установлен.${NC}"
    fi
}

# ============================================
# СИСТЕМА БЛОКОВ CADDY
# ============================================

init_caddy_blocks() {
    mkdir -p /opt/remnawave/caddy/blocks
}

add_caddy_block() {
    local domain="$1"
    local block_content="$2"
    local blocks_dir="/opt/remnawave/caddy/blocks"
    
    init_caddy_blocks
    echo "$block_content" > "$blocks_dir/$domain"
    echo -e "${GREEN}✅ Блок для $domain сохранён.${NC}"
    rebuild_caddyfile
}

remove_caddy_block() {
    local domain="$1"
    local blocks_dir="/opt/remnawave/caddy/blocks"
    
    if [ -f "$blocks_dir/$domain" ]; then
        rm -f "$blocks_dir/$domain"
        echo -e "${GREEN}✅ Блок для $domain удалён.${NC}"
        rebuild_caddyfile
    else
        echo -e "${YELLOW}⚠️  Блок для $domain не найден.${NC}"
    fi
}

rebuild_caddyfile() {
    local blocks_dir="/opt/remnawave/caddy/blocks"
    local caddyfile="/opt/remnawave/caddy/Caddyfile"
    
    echo "# Remnawave Caddy Configuration" > "$caddyfile"
    echo "# Auto-generated - do not edit manually" >> "$caddyfile"
    echo "" >> "$caddyfile"
    
    if [ -d "$blocks_dir" ]; then
        for block_file in "$blocks_dir"/*; do
            if [ -f "$block_file" ]; then
                cat "$block_file" >> "$caddyfile"
                echo "" >> "$caddyfile"
            fi
        done
    fi
    
    cat >> "$caddyfile" << 'EOF'
:443 {
    tls internal
    respond 204
}
EOF
    
    echo -e "${GREEN}✅ Caddyfile пересобран.${NC}"
}

# ============================================
# ОПЦИЯ 1.1: УСТАНОВКА ПАНЕЛИ + ПОДПИСКИ
# ============================================
install_panel() {
    show_logo
    echo -e "${BLUE}${BOLD}🚀 Установка Remnawave Panel + Subscription Page${NC}\n"

    read -p "🌐 Введите домен для ПАНЕЛИ (например panel.myvpn.com): " PANEL_DOMAIN
    read -p "🌐 Введите домен для СТРАНИЦЫ ПОДПИСКИ (например sub.myvpn.com): " SUB_DOMAIN

    if [ -z "$PANEL_DOMAIN" ] || [ -z "$SUB_DOMAIN" ]; then
        echo -e "${RED}❌ Ошибка: Домены не могут быть пустыми!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    install_docker

    echo -e "\n${YELLOW}📥 Шаг 1. Скачиваем конфигурационные файлы...${NC}"
    mkdir -p /opt/remnawave && cd /opt/remnawave
    curl -s -o docker-compose.yml https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
    curl -s -o .env https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample

    echo -e "${YELLOW}🔐 Шаг 2. Генерируем секретные ключи...${NC}"
    sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
    sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env
    sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
    sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env

    pw=$(openssl rand -hex 24)
    sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
    sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^\@]*\(@.*\)|\1$pw\2|" .env

    echo -e "${YELLOW}🌐 Шаг 3. Настраиваем домены...${NC}"
    sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$PANEL_DOMAIN|" .env
    sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_DOMAIN|" .env

    echo -e "${YELLOW}🚀 Шаг 4. Запускаем основную панель...${NC}"
    docker compose up -d
    echo -e "${GREEN}✅ Панель запущена. Ожидаем инициализацию БД...${NC}"
    sleep 20

    echo -e "\n${YELLOW}🔧 Шаг 5. Настраиваем Caddy (HTTPS)...${NC}"
    mkdir -p /opt/remnawave/caddy && cd /opt/remnawave/caddy
    init_caddy_blocks

    PANEL_BLOCK="https://$PANEL_DOMAIN {
    reverse_proxy * http://remnawave:3000
}"
    add_caddy_block "$PANEL_DOMAIN" "$PANEL_BLOCK"

    cat > docker-compose.yml <<EOF
services:
    caddy:
        image: caddy:2.9
        container_name: 'caddy'
        hostname: caddy
        restart: always
        ports:
            - '0.0.0.0:443:443'
            - '0.0.0.0:80:80'
        networks:
            - remnawave-network
        volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - caddy-ssl-data:/data
networks:
    remnawave-network:
        name: remnawave-network
        driver: bridge
        external: true
volumes:
    caddy-ssl-data:
        driver: local
        external: false
        name: caddy-ssl-data
EOF
    docker compose up -d
    echo -e "${GREEN}✅ Caddy запущен. HTTPS готов.${NC}"

    echo -e "\n${YELLOW}${BOLD}⚠️  ВАЖНО: Создайте API Token в админке!${NC}"
    echo -e "1. Откройте в браузере: ${CYAN}https://$PANEL_DOMAIN${NC}"
    echo -e "2. Зарегистрируйтесь (первый вход)"
    echo -e "3. Перейдите в ${BOLD}Settings → API Tokens${NC} и создайте токен"
    echo -e "4. Скопируйте его и вставьте ниже\n"
    read -p "🔑 Вставьте API TOKEN: " API_TOKEN

    if [ -z "$API_TOKEN" ]; then
        echo -e "${RED}❌ Токен не введён. Страница подписки не будет установлена.${NC}"
    else
        echo -e "\n${YELLOW}📄 Шаг 6. Устанавливаем страницу подписки...${NC}"
        mkdir -p /opt/remnawave/subscription && cd /opt/remnawave/subscription

        cat > .env <<EOF
APP_PORT=3010
REMNAWAVE_PANEL_URL=http://remnawave:3000
REMNAWAVE_API_TOKEN=$API_TOKEN
TRUST_PROXY=1
EOF

        cat > docker-compose.yml <<EOF
services:
    remnawave-subscription-page:
        image: remnawave/subscription-page:latest
        container_name: remnawave-subscription-page
        hostname: remnawave-subscription-page
        restart: always
        env_file:
            - .env
        ports:
            - '127.0.0.1:3010:3010'
        networks:
            - remnawave-network
networks:
    remnawave-network:
        driver: bridge
        external: true
EOF
        docker compose up -d
        echo -e "${GREEN}✅ Страница подписки запущена.${NC}"

        echo -e "${YELLOW}🔄 Шаг 7. Добавляем домен подписки в Caddy...${NC}"
        
        SUB_BLOCK="https://$SUB_DOMAIN {
    reverse_proxy * http://remnawave-subscription-page:3010
}"
        add_caddy_block "$SUB_DOMAIN" "$SUB_BLOCK"
        
        cd /opt/remnawave/caddy
        docker compose down && docker compose up -d
        echo -e "${GREEN}✅ Caddy обновлён.${NC}"
    fi

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ УСТАНОВКА ПАНЕЛИ ЗАВЕРШЕНА! 🎉          ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}🌐 Админка:  ${BOLD}https://$PANEL_DOMAIN${NC}"
    echo -e "${CYAN}📄 Подписка: ${BOLD}https://$SUB_DOMAIN${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 1.2: УСТАНОВКА НОДЫ
# ============================================
install_node() {
    show_logo
    echo -e "${BLUE}${BOLD}🖥️  Установка Remnawave Node${NC}\n"
    echo -e "${YELLOW}⚠️  Нода устанавливается на ОТДЕЛЬНЫЙ сервер!${NC}\n"

    install_docker

    read -p "🔑 Введите SECRET KEY ноды (из панели): " NODE_SECRET
    read -p "🔌 Введите NODE PORT (по умолчанию 2222): " NODE_PORT

    if [ -z "$NODE_PORT" ]; then
        NODE_PORT=2222
    fi

    if [ -z "$NODE_SECRET" ]; then
        echo -e "${RED}❌ Ошибка: Secret Key обязателен!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "\n${YELLOW}📥 Настраиваем ноду...${NC}"
    mkdir -p /opt/remnanode && cd /opt/remnanode

    cat > docker-compose.yml <<EOF
services:
    remnanode:
        image: remnawave/node:latest
        container_name: remnanode
        hostname: remnanode
        restart: always
        network_mode: host
        environment:
            - NODE_PORT=$NODE_PORT
            - SECRET_KEY=$NODE_SECRET
EOF

    echo -e "${YELLOW}🚀 Запускаем ноду...${NC}"
    docker compose up -d
    echo -e "${GREEN}✅ Нода запущена!${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         ✅ НОДА УСТАНОВЛЕНА! 🎉                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}⚠️  ВАЖНО: Закройте порт ${BOLD}$NODE_PORT${NC}${YELLOW} в фаерволе ноды"
    echo -e "   для всех, КРОМЕ IP-адреса основной панели!${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 1.3: ОБНОВЛЕНИЕ КОМПОНЕНТОВ
# ============================================
update_components() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление компонентов Remnawave${NC}\n"
    
    echo -e "${BOLD}Что хотите обновить?${NC}"
    echo -e "  ${CYAN}1)${NC} 🚀 Обновить Панель + Страницу подписки"
    echo -e "  ${CYAN}2)${NC} 🖥️  Обновить Ноду"
    echo -e "  ${CYAN}0)${NC} 🔙 Назад"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" update_choice

    case $update_choice in
        1) update_panel ;;
        2) update_node ;;
        0) return ;;
        *)
            echo -e "${RED}❌ Неверный выбор.${NC}"
            sleep 2
            ;;
    esac
}

update_panel() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Panel + Subscription Page${NC}\n"

    if [ ! -d "/opt/remnawave" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnawave не найдена.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем основную панель...${NC}"
    cd /opt/remnawave
    docker compose pull
    docker compose down
    docker compose up -d
    echo -e "${GREEN}✅ Панель обновлена.${NC}"

    if [ -d "/opt/remnawave/subscription" ]; then
        echo -e "${YELLOW}📄 Обновляем страницу подписки...${NC}"
        cd /opt/remnawave/subscription
        docker compose pull
        docker compose down
        docker compose up -d
        echo -e "${GREEN}✅ Страница подписки обновлена.${NC}"
    fi

    docker image prune -f
    echo -e "\n${GREEN}✅ ОБНОВЛЕНИЕ ЗАВЕРШЕНО!${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_node() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Node${NC}\n"

    if [ ! -d "/opt/remnanode" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnanode не найдена.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    cd /opt/remnanode
    docker compose pull
    docker compose down
    docker compose up -d
    docker image prune -f
    echo -e "${GREEN}✅ Нода обновлена.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 2: CLOUDFLARE WARP (установка + удаление)
# ============================================
install_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Установка Cloudflare WARP${NC}\n"

    install_docker

    echo -e "${YELLOW}📥 Запускаем официальный скрипт установки warp-native...${NC}"
    bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)
    
    echo -e "${GREEN}✅ WARP успешно установлен!${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

uninstall_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🗑️  Удаление Cloudflare WARP${NC}\n"

    echo -e "${YELLOW}📥 Запускаем официальный скрипт удаления...${NC}"
    bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/uninstall.sh) || true
    
    echo -e "${GREEN}✅ WARP успешно удалён.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 3: БЭКАПЫ
# ============================================
run_backup() {
    show_logo
    echo -e "${BLUE}${BOLD}💾 Запуск скрипта бэкапов${NC}\n"

    if [ ! -f "/tmp/backup-restore.sh" ]; then
        echo -e "${YELLOW}📥 Скачиваем скрипт бэкапов...${NC}"
        curl -Ls https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh -o /tmp/backup-restore.sh
        chmod +x /tmp/backup-restore.sh
        echo -e "${GREEN}✅ Скрипт скачан.${NC}\n"
    fi

    echo -e "${YELLOW}Запускаем скрипт бэкапов...${NC}\n"
    bash /tmp/backup-restore.sh
    
    echo -e "\n${GREEN}✅ Скрипт бэкапов завершён.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 4: ЛОГИ
# ============================================
show_logs_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}📋 Просмотр логов${NC}\n"
        echo -e "${BOLD}Выберите компонент:${NC}"
        echo -e "  ${CYAN}1)${NC} 🚀 Логи панели Remnawave"
        echo -e "  ${CYAN}2)${NC} 📄 Логи страницы подписки"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" log_choice

        case $log_choice in
            1) show_panel_logs ;;
            2) show_subscription_logs ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

show_panel_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}🚀 Логи панели Remnawave${NC}\n"
    
    if [ ! -d "/opt/remnawave" ]; then
        echo -e "${RED}❌ Папка /opt/remnawave не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    cd /opt/remnawave
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100
}

show_subscription_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}📄 Логи страницы подписки${NC}\n"
    
    if [ ! -d "/opt/remnawave/subscription" ]; then
        echo -e "${RED}❌ Папка /opt/remnawave/subscription не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    cd /opt/remnawave/subscription
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100
}

# ============================================
# ПОДМЕНЮ
# ============================================
show_remnawave_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🚀 Remnawave${NC}\n"
        echo -e "  ${CYAN}1)${NC} 🚀 Установить Панель + Страницу подписки"
        echo -e "  ${CYAN}2)${NC} 🖥️  Установить Ноду"
        echo -e "  ${CYAN}3)${NC} 🔄 Обновить компоненты"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

        case $choice in
            1) install_panel ;;
            2) install_node ;;
            3) update_components ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

show_warp_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🌐 Cloudflare WARP${NC}\n"
        echo -e "  ${CYAN}1)${NC} 🌐 Установить Cloudflare WARP"
        echo -e "  ${CYAN}2)${NC} 🗑️  Удалить Cloudflare WARP"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

        case $choice in
            1) install_warp ;;
            2) uninstall_warp ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

# ============================================
# ГЛАВНОЕ МЕНЮ
# ============================================
while true; do
    show_logo
    create_alias
    
    echo -e "${BOLD}Выберите раздел:${NC}"
    echo -e "  ${CYAN}1)${NC} 🚀 Remnawave"
    echo -e "  ${CYAN}2)${NC} 🌐 Cloudflare WARP"
    echo -e "  ${CYAN}3)${NC} 💾 Бэкапы"
    echo -e "  ${CYAN}4)${NC} 📋 Логи"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}0)${NC} 🚪 Выход"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" main_choice

    case $main_choice in
        1) show_remnawave_menu ;;
        2) show_warp_menu ;;
        3) run_backup ;;
        4) show_logs_menu ;;
        0) echo -e "${GREEN}👋 До свидания!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
    esac
done
