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

# Инициализация системы блоков
init_caddy_blocks() {
    mkdir -p /opt/remnawave/caddy/blocks
}

# Добавление/обновление блока Caddy для домена
# Параметры: $1 - домен, $2 - содержимое блока
add_caddy_block() {
    local domain="$1"
    local block_content="$2"
    local blocks_dir="/opt/remnawave/caddy/blocks"
    
    init_caddy_blocks
    
    # Сохраняем блок в отдельный файл
    echo "$block_content" > "$blocks_dir/$domain"
    echo -e "${GREEN}✅ Блок для $domain сохранён.${NC}"
    
    # Пересобираем Caddyfile
    rebuild_caddyfile
}

# Удаление блока Caddy для домена
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

# Пересборка Caddyfile из всех блоков
rebuild_caddyfile() {
    local blocks_dir="/opt/remnawave/caddy/blocks"
    local caddyfile="/opt/remnawave/caddy/Caddyfile"
    
    # Очищаем Caddyfile
    echo "# Remnawave Caddy Configuration" > "$caddyfile"
    echo "# Auto-generated - do not edit manually" >> "$caddyfile"
    echo "" >> "$caddyfile"
    
    # Добавляем все блоки из папки blocks/
    if [ -d "$blocks_dir" ]; then
        for block_file in "$blocks_dir"/*; do
            if [ -f "$block_file" ]; then
                cat "$block_file" >> "$caddyfile"
                echo "" >> "$caddyfile"
            fi
        done
    fi
    
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
    sleep 15

    echo -e "\n${YELLOW}🔧 Шаг 5. Настраиваем Caddy (HTTPS)...${NC}"
    mkdir -p /opt/remnawave/caddy && cd /opt/remnawave/caddy
    init_caddy_blocks

    # Создаём блок для панели И СОХРАНЯЕМ В blocks/
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
        
        # Создаём блок для подписки И СОХРАНЯЕМ В blocks/
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
# ОПЦИЯ 2.1: УСТАНОВКА CLOUDFLARE WARP
# ============================================
install_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Установка Cloudflare WARP${NC}\n"

    install_docker

    echo -e "${YELLOW}1. Установка WireGuard...${NC}"
    apt update -qq &>/dev/null
    apt install wireguard -y &>/dev/null
    echo -e "${GREEN}✅ WireGuard установлен.${NC}\n"

    echo -e "${YELLOW}2. Настройка временных DNS...${NC}"
    cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
    echo -e "${GREEN}✅ DNS настроены.${NC}\n"

    echo -e "${YELLOW}3. Скачивание wgcf...${NC}"
    WGCF_VERSION=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep tag_name | cut -d '"' -f 4)
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) WGCF_ARCH="amd64" ;;
        aarch64|arm64) WGCF_ARCH="arm64" ;;
        *) WGCF_ARCH="amd64" ;;
    esac
    
    curl -sL "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION#v}_linux_${WGCF_ARCH}" -o wgcf
    chmod +x wgcf
    mv wgcf /usr/local/bin/wgcf
    echo -e "${GREEN}✅ wgcf установлен.${NC}\n"

    echo -e "${YELLOW}4. Регистрация wgcf...${NC}"
    read -p "Введите WARP+ ключ (Enter - пропустить): " WARP_LICENSE
    
    if [[ -n "$WARP_LICENSE" && -f wgcf-account.toml ]]; then
        rm -f wgcf-account.toml wgcf-profile.conf
    fi
    
    if [ ! -f wgcf-account.toml ]; then
        yes | wgcf register
    fi
    
    wgcf generate
    
    if [[ -n "$WARP_LICENSE" ]]; then
        wgcf update --license-key "$WARP_LICENSE"
        wgcf generate
    fi

    echo -e "${YELLOW}5. Настройка конфигурации...${NC}"
    sed -i '/^DNS =/d' wgcf-profile.conf
    sed -i '/^MTU =/aTable = off' wgcf-profile.conf
    sed -i '/^Endpoint =/aPersistentKeepalive = 25' wgcf-profile.conf
    
    mkdir -p /etc/wireguard
    mv wgcf-profile.conf /etc/wireguard/warp.conf
    
    sed -i 's/,\s*[0-9a-fA-F:]\+\/128//' /etc/wireguard/warp.conf
    sed -i '/Address = [0-9a-fA-F:]\+\/128/d' /etc/wireguard/warp.conf

    systemctl start wg-quick@warp
    systemctl enable wg-quick@warp
    
    cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
    
    echo -e "${GREEN}✅ WARP установлен и запущен!${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

uninstall_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🗑️  Удаление Cloudflare WARP${NC}\n"

    wg-quick down warp &>/dev/null || true
    systemctl disable wg-quick@warp &>/dev/null || true
    rm -f /etc/wireguard/warp.conf
    rm -rf /etc/wireguard
    rm -f /usr/local/bin/wgcf
    rm -rf /opt/warp-native
    rm -f /etc/cron.d/warp-native
    rm -f /usr/local/bin/warp
    
    apt remove --purge -y wireguard &>/dev/null || true
    apt autoremove -y &>/dev/null || true
    
    echo -e "${GREEN}✅ WARP удалён.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 3.1: УСТАНОВКА REMNAWAVE ADMIN
# ============================================
install_admin_bot() {
    show_logo
    echo -e "${BLUE}${BOLD}🤖 Установка Remnawave Admin Web + Bot${NC}\n"

    install_docker

    echo -e "${YELLOW}Где устанавливается бот?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" server_location

    if [[ "$server_location" == "1" ]]; then
        API_BASE_URL="http://remnawave:3000"
        SAME_SERVER=true
    else
        read -p "🌐 Введите домен панели: " PANEL_URL
        API_BASE_URL="https://$PANEL_URL"
        SAME_SERVER=false
    fi

    read -p "🤖 BOT_TOKEN (от @BotFather): " BOT_TOKEN
    read -p "🔑 API_TOKEN (из панели): " API_TOKEN
    read -p "👤 ADMINS (Telegram ID через запятую): " ADMINS
    read -p "📱 TELEGRAM_BOT_USERNAME (без @): " TELEGRAM_BOT_USERNAME
    read -p "🌐 Домен для админ-панели: " ADMIN_DOMAIN

    WEBHOOK_SECRET=$(openssl rand -hex 64)
    WEB_SECRET_KEY=$(openssl rand -hex 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 24)

    mkdir -p /opt/remnawave-admin && cd /opt/remnawave-admin
    git clone https://github.com/Case211/remnawave-admin.git .

    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
API_BASE_URL=$API_BASE_URL
API_TOKEN=$API_TOKEN
ADMINS=$ADMINS
DEFAULT_LOCALE=ru
LOG_LEVEL=INFO
WEBHOOK_PORT=9090
WEBHOOK_SECRET=$WEBHOOK_SECRET
POSTGRES_USER=remnawave
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=remnawave_bot
DATABASE_URL=postgresql://remnawave:$POSTGRES_PASSWORD@remnawave-admin-db:5432/remnawave_bot
DB_POOL_MIN_SIZE=2
DB_POOL_MAX_SIZE=10
SYNC_INTERVAL_SECONDS=300
WEB_SECRET_KEY=$WEB_SECRET_KEY
WEB_JWT_EXPIRE_MINUTES=30
WEB_JWT_REFRESH_HOURS=6
WEB_BACKEND_PORT=9091
WEB_FRONTEND_PORT=13000
WEB_CORS_ORIGINS=https://$ADMIN_DOMAIN
EXTERNAL_API_ENABLED=false
EXTERNAL_API_DOCS=false
TELEGRAM_BOT_USERNAME=$TELEGRAM_BOT_USERNAME
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=30d
EOF

    docker network create remnawave-network 2>/dev/null || true
    docker compose up -d

    if [[ "$SAME_SERVER" == true ]]; then
        # Создаём блок для RWA И СОХРАНЯЕМ В blocks/
        RWA_BLOCK="https://$ADMIN_DOMAIN {
    handle {
        reverse_proxy web-frontend:80
    }
    handle /api/* {
        reverse_proxy web-backend:9091 {
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    handle /ws/* {
        reverse_proxy web-backend:9091
    }
}"
        add_caddy_block "$ADMIN_DOMAIN" "$RWA_BLOCK"
        
        cd /opt/remnawave/caddy
        docker compose down && docker compose up -d
    fi

    echo -e "${GREEN}✅ Remnawave Admin установлен!${NC}"
    echo -e "🌐 Админка: https://$ADMIN_DOMAIN\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_rwa() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Admin${NC}\n"

    if [ ! -d "/opt/remnawave-admin" ]; then
        echo -e "${RED}❌ Папка не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    cd /opt/remnawave-admin
    git pull origin main
    docker compose down
    docker compose up -d
    docker image prune -f
    
    echo -e "${GREEN}✅ Обновление завершено!${NC}\n"
    read -p "Нажмите Enter..."
}

# ============================================
# ОПЦИЯ 3.2: УДАЛЕНИЕ REMNAWAVE ADMIN
# ============================================
uninstall_rwa() {
    show_logo
    echo -e "${BLUE}${BOLD}🗑️  Удаление Remnawave Admin Web + Bot${NC}\n"

    if [ ! -d "/opt/remnawave-admin" ]; then
        echo -e "${RED}❌ Папка /opt/remnawave-admin не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo -e "${YELLOW}⚠️  Вы собираетесь удалить Remnawave Admin Web + Bot${NC}"
    echo -e "${YELLOW}   Все данные будут удалены без возможности восстановления!${NC}\n"
    read -p "Подтвердите удаление (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${GREEN}❌ Удаление отменено.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo -e "\n${YELLOW}🛑 Останавливаем контейнеры...${NC}"
    cd /opt/remnawave-admin
    docker compose down
    echo -e "${GREEN}✅ Контейнеры остановлены.${NC}"

    # Получаем домен из .env для удаления блока Caddy
    if [ -f ".env" ]; then
        ADMIN_DOMAIN=$(grep "WEB_CORS_ORIGINS" .env | cut -d'=' -f2 | sed 's|https://||')
        if [ -n "$ADMIN_DOMAIN" ]; then
            echo -e "${YELLOW}🗑️  Удаляем блок Caddy для $ADMIN_DOMAIN...${NC}"
            remove_caddy_block "$ADMIN_DOMAIN"
            cd /opt/remnawave/caddy
            docker compose down && docker compose up -d
        fi
    fi

    echo -e "${YELLOW}🗑️  Удаляем директорию /opt/remnawave-admin...${NC}"
    rm -rf /opt/remnawave-admin
    echo -e "${GREEN}✅ Директория удалена.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✅ REMNAWAVE ADMIN УДАЛЁН! 🎉                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 4.1: УСТАНОВКА BEDOLAGA BOT
# ============================================
install_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}💰 Установка Bedolaga Bot${NC}\n"

    install_docker

    echo -e "${YELLOW}Где устанавливается бот?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" server_location

    # Всегда спрашиваем домен панели
    read -p "🌐 Введите домен панели Remnawave (например panel.myvpn.com): " PANEL_DOMAIN
    REMNAWAVE_API_URL="https://$PANEL_DOMAIN"

    read -p "🤖 BOT_TOKEN (от @BotFather): " BOT_TOKEN
    read -p "👤 ADMIN_IDS (Telegram ID через запятую): " ADMIN_IDS
    read -p "🔑 REMNAWAVE_API_KEY (API ключ из панели): " REMNAWAVE_API_KEY
    read -p "🌐 Домен для бота (например bedolaga.myvpn.com): " BEDOLAGA_DOMAIN

    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    WEBHOOK_SECRET_TOKEN=$(openssl rand -hex 32)
    WEB_API_DEFAULT_TOKEN=$(openssl rand -hex 32)

    mkdir -p /opt/bedolaga-bot && cd /opt/bedolaga-bot
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git .

    cat > .env <<EOF
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
REMNAWAVE_API_URL=$REMNAWAVE_API_URL
REMNAWAVE_API_KEY=$REMNAWAVE_API_KEY
REMNAWAVE_AUTH_TYPE=api_key
POSTGRES_DB=remnawave_bot
POSTGRES_USER=remnawave_user
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
BOT_RUN_MODE=webhook
WEBHOOK_URL=https://$BEDOLAGA_DOMAIN
WEBHOOK_PATH=/webhook
WEBHOOK_SECRET_TOKEN=$WEBHOOK_SECRET_TOKEN
WEBHOOK_DROP_PENDING_UPDATES=true
WEBHOOK_MAX_QUEUE_SIZE=1024
WEBHOOK_WORKERS=4
WEBHOOK_ENQUEUE_TIMEOUT=0.1
WEBHOOK_WORKER_SHUTDOWN_TIMEOUT=30.0
WEB_API_DEFAULT_TOKEN=$WEB_API_DEFAULT_TOKEN
WEB_API_ENABLED=true
WEB_API_HOST=0.0.0.0
WEB_API_PORT=8080
WEB_API_ALLOWED_ORIGINS=*
EOF

    mkdir -p ./logs ./data ./data/backups ./data/referral_qr
    chmod -R 755 ./logs ./data
    chown -R 1000:1000 ./logs ./data

    docker network create remnawave-network 2>/dev/null || true
    docker network create remnawave_bot_network 2>/dev/null || true

    # Если на том же сервере - используем docker-compose.local.yml
    if [[ "$server_location" == "1" ]]; then
        echo -e "${YELLOW}📥 Используем docker-compose.local.yml...${NC}"
        if [ -f "docker-compose.local.yml" ]; then
            rm -f docker-compose.yml
            mv docker-compose.local.yml docker-compose.yml
            echo -e "${GREEN}✅ docker-compose.local.yml переименован в docker-compose.yml${NC}"
        else
            echo -e "${YELLOW}⚠️  docker-compose.local.yml не найден, используем стандартный${NC}"
        fi
    fi

    docker compose up -d

    # Настройка Caddy
    if [[ "$server_location" == "1" ]]; then
        # Создаём блок для Bedolaga И СОХРАНЯЕМ В blocks/
        BEDOLAGA_BLOCK="https://$BEDOLAGA_DOMAIN {
    encode gzip zstd
    handle {
        reverse_proxy remnawave_bot:8080 {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            transport http {
                read_buffer 0
            }
        }
    }
}"
        add_caddy_block "$BEDOLAGA_DOMAIN" "$BEDOLAGA_BLOCK"
        
        cd /opt/remnawave/caddy
        docker compose down && docker compose up -d
    fi

    echo -e "${GREEN}✅ Bedolaga Bot установлен!${NC}"
    echo -e "🤖 Бот: https://$BEDOLAGA_DOMAIN\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Bedolaga Bot${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Папка не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    cd /opt/bedolaga-bot
    git pull origin main
    docker compose down
    docker compose up -d --build
    docker image prune -f
    
    echo -e "${GREEN}✅ Обновление завершено!${NC}\n"
    read -p "Нажмите Enter..."
}

# ============================================
# ОПЦИЯ 4.2: УСТАНОВКА CABINET
# ============================================
install_cabinet() {
    show_logo
    echo -e "${BLUE}${BOLD}🗄️  Установка Bedolaga Cabinet${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Сначала установите Bedolaga Bot!${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    read -p "🌐 Домен для Cabinet (например cabinet.myvpn.com): " CABINET_DOMAIN

    CABINET_JWT_SECRET=$(openssl rand -hex 32)

    # Добавляем Cabinet в .env бота
    cd /opt/bedolaga-bot
    if ! grep -q "CABINET_ENABLED=true" .env; then
        cat >> .env <<EOF

# Bedolaga Cabinet
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
CABINET_URL=https://$CABINET_DOMAIN
EOF
        echo -e "${GREEN}✅ Cabinet настройки добавлены в .env${NC}"
    fi

    # Получаем frontend файлы
    echo -e "${YELLOW}📥 Получаем frontend файлы...${NC}"
    docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    rm -rf ./cabinet-dist
    docker cp tmp_cabinet:/usr/share/nginx/html ./cabinet-dist
    docker rm tmp_cabinet

    mkdir -p /srv/cabinet
    cp -r ./cabinet-dist/* /srv/cabinet/

    # Перезапускаем бота
    docker compose down
    docker compose up -d

    # Подключаем caddy к сети бота для доступа к cabinet_frontend
    echo -e "${YELLOW}🔗 Подключаем Caddy к сети Bedolaga...${NC}"
    BOT_NETWORK=$(docker inspect remnawave_bot -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null | tr -d ' ')
    if [ -n "$BOT_NETWORK" ]; then
        docker network connect "$BOT_NETWORK" caddy 2>/dev/null || true
        echo -e "${GREEN}✅ Caddy подключён к сети $BOT_NETWORK${NC}"
    else
        echo -e "${YELLOW}⚠️  Не удалось определить сеть бота. Попробуйте вручную:${NC}"
        echo -e "${CYAN}   docker network connect <network_name> caddy${NC}"
    fi

    # Создаём блок для Cabinet И СОХРАНЯЕМ В blocks/
    CABINET_BLOCK="https://$CABINET_DOMAIN {
    encode gzip zstd
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }
    handle {
        reverse_proxy cabinet_frontend:80
    }
}"
    add_caddy_block "$CABINET_DOMAIN" "$CABINET_BLOCK"
    
    cd /opt/remnawave/caddy
    docker compose down && docker compose up -d

    echo -e "${GREEN}✅ Cabinet установлен!${NC}"
    echo -e "🗄️  Cabinet: https://$CABINET_DOMAIN\n"
    read -p "Нажмите Enter для возврата в меню..."
}

update_cabinet() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Bedolaga Cabinet${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Папка не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    cd /opt/bedolaga-bot
    docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    rm -rf ./cabinet-dist
    docker cp tmp_cabinet:/usr/share/nginx/html ./cabinet-dist
    docker rm tmp_cabinet
    rm -rf /srv/cabinet/*
    cp -r ./cabinet-dist/* /srv/cabinet/
    
    if docker ps -a | grep -q cabinet_frontend; then
        docker restart cabinet_frontend
    fi
    
    echo -e "${GREEN}✅ Cabinet обновлён!${NC}\n"
    read -p "Нажмите Enter..."
}

# ============================================
# ОПЦИЯ 4.3: УДАЛЕНИЕ BEDOLAGA
# ============================================
uninstall_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🗑️  Удаление Bedolaga Bot + Cabinet${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Папка /opt/bedolaga-bot не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo -e "${YELLOW}⚠️  Вы собираетесь удалить Bedolaga Bot и Cabinet${NC}"
    echo -e "${YELLOW}   Все данные будут удалены без возможности восстановления!${NC}\n"
    read -p "Подтвердите удаление (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${GREEN}❌ Удаление отменено.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo -e "\n${YELLOW}🛑 Останавливаем контейнеры...${NC}"
    cd /opt/bedolaga-bot
    docker compose down
    echo -e "${GREEN}✅ Контейнеры остановлены.${NC}"

    # Получаем домены из .env для удаления блоков Caddy
    if [ -f ".env" ]; then
        BEDOLAGA_DOMAIN=$(grep "WEBHOOK_URL" .env | cut -d'=' -f2 | sed 's|https://||')
        CABINET_DOMAIN=$(grep "CABINET_URL" .env | cut -d'=' -f2 | sed 's|https://||')
        
        if [ -n "$BEDOLAGA_DOMAIN" ]; then
            echo -e "${YELLOW}🗑️  Удаляем блок Caddy для $BEDOLAGA_DOMAIN...${NC}"
            remove_caddy_block "$BEDOLAGA_DOMAIN"
        fi
        
        if [ -n "$CABINET_DOMAIN" ]; then
            echo -e "${YELLOW}🗑️  Удаляем блок Caddy для $CABINET_DOMAIN...${NC}"
            remove_caddy_block "$CABINET_DOMAIN"
        fi
        
        if [ -n "$BEDOLAGA_DOMAIN" ] || [ -n "$CABINET_DOMAIN" ]; then
            cd /opt/remnawave/caddy
            docker compose down && docker compose up -d
        fi
    fi

    echo -e "${YELLOW}🗑️  Удаляем директорию /opt/bedolaga-bot...${NC}"
    rm -rf /opt/bedolaga-bot
    echo -e "${GREEN}✅ Директория удалена.${NC}"

    echo -e "${YELLOW}🗑️  Удаляем файлы Cabinet...${NC}"
    rm -rf /srv/cabinet
    echo -e "${GREEN}✅ Файлы Cabinet удалены.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✅ BEDOLAGA BOT УДАЛЁН! 🎉                      ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 5: БЭКАПЫ
# ============================================
run_backup() {
    show_logo
    echo -e "${BLUE}${BOLD}💾 Запуск скрипта бэкапов${NC}\n"

    # Скачиваем скрипт если его нет
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
# ОПЦИЯ 6: ЛОГИ
# ============================================
show_logs_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}📋 Просмотр логов${NC}\n"
        echo -e "${BOLD}Выберите компонент:${NC}"
        echo -e "  ${CYAN}1)${NC} 🚀 Логи панели Remnawave"
        echo -e "  ${CYAN}2)${NC} 📄 Логи страницы подписки"
        echo -e "  ${CYAN}3)${NC} 🤖 Логи RWA (Admin Web + Bot)"
        echo -e "  ${CYAN}4)${NC} 💰 Логи Bedolaga Bot"
        echo -e "  ${CYAN}5)${NC} 🗄️  Логи Cabinet"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" log_choice

        case $log_choice in
            1) show_panel_logs ;;
            2) show_subscription_logs ;;
            3) show_rwa_logs ;;
            4) show_bedolaga_logs ;;
            5) show_cabinet_logs ;;
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

show_rwa_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}🤖 Логи RWA (Admin Web + Bot)${NC}\n"
    
    if [ ! -d "/opt/remnawave-admin" ]; then
        echo -e "${RED}❌ Папка /opt/remnawave-admin не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    cd /opt/remnawave-admin
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100
}

show_bedolaga_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}💰 Логи Bedolaga Bot${NC}\n"
    
    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Папка /opt/bedolaga-bot не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    cd /opt/bedolaga-bot
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100 remnawave_bot
}

show_cabinet_logs() {
    show_logo
    echo -e "${BLUE}${BOLD}🗄️  Логи Cabinet${NC}\n"
    
    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Папка /opt/bedolaga-bot не найдена.${NC}"
        read -p "Нажмите Enter..."
        return
    fi
    
    cd /opt/bedolaga-bot
    echo -e "${YELLOW}Нажмите Ctrl+C для выхода из логов${NC}\n"
    docker compose logs -f --tail=100 cabinet_frontend
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

show_admin_bot_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🤖 Remnawave Admin Web + Bot${NC}\n"
        echo -e "  ${CYAN}1)${NC} 🤖 Установить Admin Web + Bot"
        echo -e "  ${CYAN}2)${NC} 🔄 Обновить Admin Web + Bot"
        echo -e "  ${CYAN}3)${NC} 🗑️  Удалить Admin Web + Bot"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

        case $choice in
            1) install_admin_bot ;;
            2) update_rwa ;;
            3) uninstall_rwa ;;
            0) break ;;
            *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
        esac
    done
}

show_bedolaga_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}💰 Bedolaga${NC}\n"
        echo -e "  ${CYAN}1)${NC} 💰 Установить Bedolaga Bot"
        echo -e "  ${CYAN}2)${NC} 🗄️  Установить Cabinet"
        echo -e "  ${CYAN}3)${NC} 🔄 Обновить Bedolaga Bot"
        echo -e "  ${CYAN}4)${NC} 🔄 Обновить Cabinet"
        echo -e "  ${CYAN}5)${NC} 🗑️  Удалить Bedolaga Bot + Cabinet"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад"
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" choice

        case $choice in
            1) install_bedolaga ;;
            2) install_cabinet ;;
            3) update_bedolaga ;;
            4) update_cabinet ;;
            5) uninstall_bedolaga ;;
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
    echo -e "  ${CYAN}3)${NC} 🤖 Remnawave Admin Web + Bot"
    echo -e "  ${CYAN}4)${NC} 💰 Bedolaga"
    echo -e "  ${CYAN}5)${NC} 💾 Бэкапы"
    echo -e "  ${CYAN}6)${NC} 📋 Логи"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}0)${NC} 🚪 Выход"
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" main_choice

    case $main_choice in
        1) show_remnawave_menu ;;
        2) show_warp_menu ;;
        3) show_admin_bot_menu ;;
        4) show_bedolaga_menu ;;
        5) run_backup ;;
        6) show_logs_menu ;;
        0) echo -e "${GREEN}👋 До свидания!${NC}"; exit 0 ;;
        *) echo -e "${RED}❌ Неверный выбор.${NC}"; sleep 2 ;;
    esac
done
