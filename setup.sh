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
# ОПЦИЯ 1.1: УСТАНОВКА ПАНЕЛИ + ПОДПИСКИ
# ============================================
install_panel() {
    show_logo
    echo -e "${BLUE}${BOLD}🚀 Установка Remnawave Panel + Subscription Page${NC}\n"

    # Запрос доменов
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

    # Создаём Caddyfile в новом формате с комментариями
    cat > Caddyfile <<EOF
# ==================
# Web panel
# ==================
https://$PANEL_DOMAIN {
        reverse_proxy * http://remnawave:3000
}
EOF

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
        cd /opt/remnawave/caddy
        
        # Проверяем, есть ли уже этот домен, чтобы не дублировать
        if ! grep -q "$SUB_DOMAIN" Caddyfile; then
            # Добавляем блок подписки в новом формате с комментариями
            cat >> Caddyfile <<EOF

# ==================
# Subscription Page
# ==================
https://$SUB_DOMAIN {
        reverse_proxy * http://remnawave-subscription-page:3010
}
EOF
            
            docker compose down && docker compose up -d
            echo -e "${GREEN}✅ Caddy обновлён.${NC}"
        fi
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
        1)
            update_panel
            ;;
        2)
            update_node
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор.${NC}"
            sleep 2
            ;;
    esac
}

# Обновление панели и страницы подписки
update_panel() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Panel + Subscription Page${NC}\n"

    if [ ! -d "/opt/remnawave" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnawave не найдена. Сначала установите панель.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем основную панель...${NC}"
    cd /opt/remnawave
    docker compose pull
    docker compose down
    docker compose up -d
    echo -e "${GREEN}✅ Панель обновлена и запущена.${NC}"

    echo -e "\n${YELLOW}📄 Обновляем страницу подписки...${NC}"
    if [ -d "/opt/remnawave/subscription" ]; then
        cd /opt/remnawave/subscription
        docker compose pull
        docker compose down
        docker compose up -d
        echo -e "${GREEN}✅ Страница подписки обновлена и запущена.${NC}"
    else
        echo -e "${YELLOW}⚠️  Страница подписки не установлена. Пропускаем.${NC}"
    fi

    echo -e "\n${YELLOW}🧹 Очищаем неиспользуемые образы...${NC}"
    docker image prune -f
    echo -e "${GREEN}✅ Очистка завершена.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ ОБНОВЛЕНИЕ ПАНЕЛИ ЗАВЕРШЕНО! 🎉         ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# Обновление ноды
update_node() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Node${NC}\n"

    if [ ! -d "/opt/remnanode" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnanode не найдена. Сначала установите ноду.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем ноду...${NC}"
    cd /opt/remnanode
    docker compose pull
    docker compose down
    docker compose up -d
    echo -e "${GREEN}✅ Нода обновлена и запущена.${NC}"

    echo -e "\n${YELLOW}🧹 Очищаем неиспользуемые образы...${NC}"
    docker image prune -f
    echo -e "${GREEN}✅ Очистка завершена.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         ✅ ОБНОВЛЕНИЕ НОДЫ ЗАВЕРШЕНО! 🎉          ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 2.1: УСТАНОВКА CLOUDFLARE WARP
# ============================================
install_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🌐 Установка Cloudflare WARP${NC}\n"
    echo -e "${YELLOW}Начинаем установку и настройку Cloudflare WARP${NC}\n"

    # Проверка прав root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Этот скрипт должен быть запущен от имени root${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # Шаг 1: Установка WireGuard
    echo -e "${YELLOW}1. Установка WireGuard...${NC}"
    apt update -qq &>/dev/null || {
        echo -e "${RED}❌ Не удалось обновить список пакетов.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    apt install wireguard -y &>/dev/null || {
        echo -e "${RED}❌ Не удалось установить WireGuard.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ WireGuard установлен.${NC}\n"

    # Шаг 2: Настройка временных DNS
    echo -e "${YELLOW}2. Назначение временных DNS (1.1.1.1 + 8.8.8.8)...${NC}"
    cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null
    echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf || {
        echo -e "${RED}❌ Не удалось настроить временные DNS-серверы.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Временные DNS-серверы установлены.${NC}\n"

    # Шаг 3: Скачивание wgcf
    echo -e "${YELLOW}3. Скачивание и установка wgcf...${NC}"
    WGCF_RELEASE_URL="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
    WGCF_VERSION=$(curl -s "$WGCF_RELEASE_URL" | grep tag_name | cut -d '"' -f 4)
    if [ -z "$WGCF_VERSION" ]; then
        echo -e "${RED}❌ Не удалось получить последнюю версию wgcf${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64) WGCF_ARCH="amd64" ;;
        aarch64|arm64) WGCF_ARCH="arm64" ;;
        armv7l) WGCF_ARCH="armv7" ;;
        *) WGCF_ARCH="amd64" ;;
    esac
    echo -e "${GREEN}✅ Определена архитектура: $ARCH -> $WGCF_ARCH${NC}"

    WGCF_DOWNLOAD_URL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION#v}_linux_${WGCF_ARCH}"
    WGCF_BINARY_NAME="wgcf_${WGCF_VERSION#v}_linux_${WGCF_ARCH}"

    if command -v wget &>/dev/null; then
        wget -q "$WGCF_DOWNLOAD_URL" -O "$WGCF_BINARY_NAME" || {
            echo -e "${RED}❌ Не удалось скачать wgcf.${NC}"
            cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
            read -p "Нажмите Enter для возврата в меню..."
            return
        }
    elif command -v curl &>/dev/null; then
        curl -sL "$WGCF_DOWNLOAD_URL" -o "$WGCF_BINARY_NAME" || {
            echo -e "${RED}❌ Не удалось скачать wgcf.${NC}"
            cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
            read -p "Нажмите Enter для возврата в меню..."
            return
        }
    else
        echo -e "${RED}❌ Не найден wget или curl. Установите один из них и повторите.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    chmod +x "$WGCF_BINARY_NAME" || {
        echo -e "${RED}❌ Не удалось сделать wgcf исполняемым.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    mv "$WGCF_BINARY_NAME" /usr/local/bin/wgcf || {
        echo -e "${RED}❌ Не удалось переместить wgcf в /usr/local/bin.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ wgcf $WGCF_VERSION установлен в /usr/local/bin/wgcf.${NC}\n"

    # Шаг 4: Регистрация wgcf
    echo -e "${YELLOW}4. Регистрация и генерация конфигурации wgcf...${NC}\n"
    echo -e "${YELLOW}Если у вас есть WARP+ ключ, вы можете его применить.${NC}"
    read -p "Введите лицензионный ключ WARP+ (Enter - пропустить): " WARP_LICENSE

    # Если есть лицензия и старый аккаунт - пересоздаём
    if [[ -n "$WARP_LICENSE" && -f wgcf-account.toml ]]; then
        echo -e "${YELLOW}⚠️  Обнаружен старый аккаунт. Для активации WARP+ пересоздаём аккаунт...${NC}"
        rm -f wgcf-account.toml wgcf-profile.conf
        echo -e "${GREEN}✅ Старый аккаунт удалён.${NC}"
    fi

    if [[ -f wgcf-account.toml ]]; then
        echo -e "${GREEN}✅ Файл wgcf-account.toml уже существует. Пропускаем регистрацию.${NC}"
    else
        echo -e "${YELLOW}Выполняем регистрацию wgcf...${NC}"
        
        # Проверяем исполняемость
        if ! wgcf --help &>/dev/null; then
            echo -e "${YELLOW}⚠️  Бинарный файл wgcf не исполняется. Исправляем...${NC}"
            chmod +x /usr/local/bin/wgcf
            if ! wgcf --help &>/dev/null; then
                echo -e "${RED}❌ Бинарный файл wgcf не исполняется или имеет неправильную архитектуру.${NC}"
                cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
                read -p "Нажмите Enter для возврата в меню..."
                return
            fi
        fi

        # Регистрация с таймаутом
        output=$(timeout 60 bash -c 'yes | wgcf register' 2>&1)
        ret=$?

        if [[ $ret -ne 0 ]]; then
            echo -e "${YELLOW}⚠️  wgcf register завершился с кодом $ret.${NC}"
            if [[ $ret -eq 126 ]]; then
                echo -e "${YELLOW}⚠️  Бинарный файл wgcf не исполняется.${NC}"
            elif [[ $ret -eq 124 ]]; then
                echo -e "${YELLOW}⚠️  Регистрация прервана по таймауту (60 секунд).${NC}"
            elif [[ "$output" == *"500 Internal Server Error"* ]]; then
                echo -e "${YELLOW}⚠️  Cloudflare вернул ошибку 500 Internal Server Error.${NC}"
                echo -e "${YELLOW}ℹ️  Это известное поведение: продолжаем попытку регистрации.${NC}"
            elif [[ "$output" == *"429"* || "$output" == *"Too Many Requests"* ]]; then
                echo -e "${YELLOW}⚠️  Превышен лимит запросов к Cloudflare. Подождите и попробуйте позже.${NC}"
            elif [[ "$output" == *"403"* || "$output" == *"Forbidden"* ]]; then
                echo -e "${YELLOW}⚠️  Доступ запрещен Cloudflare.${NC}"
            elif [[ "$output" == *"network"* || "$output" == *"connection"* ]]; then
                echo -e "${YELLOW}⚠️  Проблемы с сетевым подключением.${NC}"
            fi
            
            echo -e "${YELLOW}Пробуем альтернативный метод регистрации...${NC}"
            timeout 60 bash -c 'yes | wgcf register' &>/dev/null || true
            sleep 2
        fi

        if [[ ! -f wgcf-account.toml ]]; then
            echo -e "${RED}❌ Регистрация не удалась: файл wgcf-account.toml не создан.${NC}"
            cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
            read -p "Нажмите Enter для возврата в меню..."
            return
        fi
        echo -e "${GREEN}✅ Файл wgcf-account.toml успешно создан. Продолжаем установку.${NC}"
    fi

    # Генерация конфигурации
    wgcf generate &>/dev/null || {
        echo -e "${RED}❌ Ошибка при генерации конфигурации wgcf.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Конфигурация wgcf успешно сгенерирована.${NC}\n"

    # Применение лицензии WARP+
    LICENSE_APPLIED=false
    if [[ -n "$WARP_LICENSE" ]]; then
        echo -e "${YELLOW}Применение WARP+ лицензии...${NC}"
        wgcf update --license-key "$WARP_LICENSE" &>/dev/null
        if [[ $? -eq 0 ]]; then
            LICENSE_APPLIED=true
            echo -e "${GREEN}✅ WARP+ лицензия успешно применена!${NC}"
            wgcf generate &>/dev/null || {
                echo -e "${RED}❌ Ошибка при генерации конфигурации wgcf.${NC}"
                cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
                read -p "Нажмите Enter для возврата в меню..."
                return
            }
            echo -e "${GREEN}✅ Конфигурация перегенерирована с WARP+.${NC}"
        else
            echo -e "${YELLOW}⚠️  Не удалось применить лицензию. Проверьте ключ.${NC}"
            echo -e "${YELLOW}⚠️  WARP+ ключ введён, но лицензия не была применена. Используется бесплатная версия.${NC}"
            echo -e "${YELLOW}ℹ️  Продолжаем с бесплатной версией WARP.${NC}"
        fi
    else
        echo -e "${YELLOW}ℹ️  Пропускаем применение WARP+ лицензии.${NC}"
    fi
    echo ""

    # Шаг 5: Редактирование конфигурации
    echo -e "${YELLOW}5. Редактирование конфигурации WARP...${NC}"
    WGCF_CONF_FILE="wgcf-profile.conf"
    if [ ! -f "$WGCF_CONF_FILE" ]; then
        echo -e "${RED}❌ Файл $WGCF_CONF_FILE не найден.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    sed -i '/^DNS =/d' "$WGCF_CONF_FILE" || {
        echo -e "${RED}❌ Не удалось удалить строку DNS из конфигурации.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }

    if ! grep -q "Table = off" "$WGCF_CONF_FILE"; then
        sed -i '/^MTU =/aTable = off' "$WGCF_CONF_FILE" || {
            echo -e "${RED}❌ Не удалось добавить Table = off.${NC}"
            cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
            read -p "Нажмите Enter для возврата в меню..."
            return
        }
    fi

    if ! grep -q "PersistentKeepalive = 25" "$WGCF_CONF_FILE"; then
        sed -i '/^Endpoint =/aPersistentKeepalive = 25' "$WGCF_CONF_FILE" || {
            echo -e "${RED}❌ Не удалось добавить PersistentKeepalive = 25.${NC}"
            cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
            read -p "Нажмите Enter для возврата в меню..."
            return
        }
    fi

    mkdir -p /etc/wireguard || {
        echo -e "${RED}❌ Не удалось создать директорию /etc/wireguard.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }

    mv "$WGCF_CONF_FILE" /etc/wireguard/warp.conf || {
        echo -e "${RED}❌ Не удалось переместить конфигурацию.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Конфигурация сохранена в /etc/wireguard/warp.conf.${NC}\n"

    # Шаг 6: Удаление IPv6
    echo -e "${YELLOW}6. Удаление IPv6 из конфигурации WARP (используется только IPv4)...${NC}"
    sed -i 's/,\s*[0-9a-fA-F:]\+\/128//' /etc/wireguard/warp.conf
    sed -i '/Address = [0-9a-fA-F:]\+\/128/d' /etc/wireguard/warp.conf
    echo -e "${GREEN}✅ IPv6 удалён из конфигурации WARP.${NC}\n"

    # Шаг 7: Подключение интерфейса
    echo -e "${YELLOW}7. Подключение интерфейса WARP...${NC}"
    systemctl start wg-quick@warp &>/dev/null || {
        echo -e "${RED}❌ Не удалось подключить интерфейс.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Интерфейс WARP успешно подключен.${NC}\n"

    # Шаг 8: Проверка статуса
    echo -e "${YELLOW}8. Проверка статуса подключения WARP...${NC}"
    if ! wg show warp &>/dev/null; then
        echo -e "${RED}❌ Интерфейс WARP не найден — туннель не работает.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # Проверка handshake
    handshake_ts=0
    for i in {1..10}; do
        handshake_ts=$(wg show warp latest-handshakes | awk '{print $2}')
        if [[ -n "$handshake_ts" && "$handshake_ts" -gt 0 ]]; then
            age=$(( $(date +%s) - handshake_ts ))
            echo -e "${GREEN}✅ Получен handshake → ${age} сек. назад${NC}"
            echo -e "${GREEN}✅ WARP подключён и активно обменивается трафиком.${NC}"
            break
        fi
        sleep 1
    done

    if [[ -z "$handshake_ts" || "$handshake_ts" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  Не удалось получить handshake в течение 10 секунд. Возможны проблемы с подключением.${NC}"
    fi

    # Проверка через Cloudflare
    curl_result=$(curl -s --interface warp --max-time 5 https://www.cloudflare.com/cdn-cgi/trace | grep "warp=" | cut -d= -f2)
    if [[ "$curl_result" == "plus" ]]; then
        echo -e "${GREEN}✅ Ответ от Cloudflare: warp=plus — WARP+ работает!${NC}"
    elif [[ "$curl_result" == "on" ]]; then
        echo -e "${GREEN}✅ Ответ от Cloudflare: warp=on${NC}"
    else
        echo -e "${YELLOW}⚠️  Cloudflare не подтвердил warp=on, но интерфейс работает. Это нормально.${NC}"
    fi

    # Проверка типа аккаунта
    wgcf_account_type=$(wgcf status 2>/dev/null | grep -i "Account type" | awk -F': ' '{print $2}' | xargs)
    if [[ "$wgcf_account_type" == "unlimited" ]]; then
        echo -e "${GREEN}✅ WARP+ активирован${NC}"
    elif [[ -n "$wgcf_account_type" ]]; then
        echo -e "${YELLOW}ℹ️  Используется бесплатная версия WARP${NC}"
    fi
    echo ""

    # Шаг 9: Автозапуск
    echo -e "${YELLOW}9. Включение автозапуска WARP при старте...${NC}"
    systemctl enable wg-quick@warp &>/dev/null || {
        echo -e "${RED}❌ Не удалось настроить автозапуск.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Автозапуск включен.${NC}\n"

    # Шаг 10: Watchdog
    echo -e "${YELLOW}10. Настройка WARP Watchdog...${NC}\n"
    echo -e "${BOLD}Выберите интервал проверки watchdog:${NC}"
    echo -e "${GREEN}1) Каждые 5 минут${NC}"
    echo -e "${GREEN}2) Каждые 10 минут (по умолчанию)${NC}"
    echo -e "${GREEN}3) Каждые 15 минут${NC}"
    echo -e "${GREEN}4) Каждые 30 минут${NC}"
    echo ""
    WATCHDOG_INTERVAL=10
    WATCHDOG_CRON_INTERVAL="*/10 * * * *"
    read -p "Ваш выбор [1-4, Enter = 2]: " wdog_choice
    case "$wdog_choice" in
        1) WATCHDOG_INTERVAL=5;  WATCHDOG_CRON_INTERVAL="*/5 * * * *" ;;
        2) WATCHDOG_INTERVAL=10; WATCHDOG_CRON_INTERVAL="*/10 * * * *" ;;
        3) WATCHDOG_INTERVAL=15; WATCHDOG_CRON_INTERVAL="*/15 * * * *" ;;
        4) WATCHDOG_INTERVAL=30; WATCHDOG_CRON_INTERVAL="*/30 * * * *" ;;
        *)  WATCHDOG_INTERVAL=10; WATCHDOG_CRON_INTERVAL="*/10 * * * *" ;;
    esac
    echo -e "${GREEN}✅ Интервал watchdog установлен: ${WATCHDOG_INTERVAL} мин${NC}\n"

    mkdir -p /opt/warp-native/logs || {
        echo -e "${RED}❌ Не удалось создать директорию /opt/warp-native.${NC}"
        cp /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null
        read -p "Нажмите Enter для возврата в меню..."
        return
    }

    # Создаём конфиг watchdog
    cat > /opt/warp-native/config.env <<EOF
# warp-native watchdog configuration
# Edited values take effect on next cron run
# Handshake threshold in seconds (default: 180)
HANDSHAKE_THRESHOLD=180
# Cooldown between restarts in seconds (default: 120)
RESTART_COOLDOWN=120
# Max log lines before rotation (default: 1000)
LOG_MAX_LINES=1000
EOF

    # Создаём скрипт watchdog
    cat > /opt/warp-native/warp-watchdog.sh <<'WATCHDOG_EOF'
#!/bin/bash
CONFIG="/opt/warp-native/config.env"
LOG="/opt/warp-native/logs/watchdog.log"
COOLDOWN_FILE="/opt/warp-native/logs/.last_restart"

# Загружаем конфиг
if [[ -f "$CONFIG" ]]; then
    source "$CONFIG"
fi

HANDSHAKE_THRESHOLD="${HANDSHAKE_THRESHOLD:-180}"
RESTART_COOLDOWN="${RESTART_COOLDOWN:-120}"
LOG_MAX_LINES="${LOG_MAX_LINES:-1000}"

log() {
    local level="$1"
    local message="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $message" >> "$LOG"
}

rotate_log() {
    if [[ -f "$LOG" ]]; then
        local lines
        lines=$(wc -l < "$LOG")
        if [[ $lines -gt $LOG_MAX_LINES ]]; then
            tail -n "$LOG_MAX_LINES" "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
        fi
    fi
}

do_restart() {
    local reason="$1"
    
    # Проверяем cooldown
    if [[ -f "$COOLDOWN_FILE" ]]; then
        local last_restart
        last_restart=$(cat "$COOLDOWN_FILE")
        local now
        now=$(date +%s)
        local diff=$(( now - last_restart ))
        if [[ $diff -lt $RESTART_COOLDOWN ]]; then
            log "SKIP" "Restart skipped (cooldown: ${diff}s < ${RESTART_COOLDOWN}s). Reason was: $reason"
            return
        fi
    fi
    
    log "RESTART" "Restarting wg-quick@warp. Reason: $reason"
    systemctl restart wg-quick@warp
    local ret=$?
    date +%s > "$COOLDOWN_FILE"
    
    if [[ $ret -eq 0 ]]; then
        log "OK" "wg-quick@warp restarted successfully"
    else
        log "ERROR" "Failed to restart wg-quick@warp (exit code: $ret)"
    fi
}

rotate_log

if ! systemctl is-active --quiet wg-quick@warp; then
    do_restart "systemd unit is not active"
    exit 0
fi

handshake_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
if [[ -z "$handshake_ts" || "$handshake_ts" -eq 0 ]]; then
    do_restart "no handshake data"
    exit 0
fi

now=$(date +%s)
age=$(( now - handshake_ts ))
if [[ $age -gt $HANDSHAKE_THRESHOLD ]]; then
    do_restart "handshake too old (${age}s > ${HANDSHAKE_THRESHOLD}s)"
    exit 0
fi

if ! ping -I warp -c 2 -W 3 1.1.1.1 &>/dev/null; then
    do_restart "ping via warp interface failed"
    exit 0
fi

log "OK" "WARP is healthy (handshake: ${age}s ago)"
WATCHDOG_EOF

    chmod +x /opt/warp-native/warp-watchdog.sh
    echo -e "${GREEN}✅ Watchdog скрипт создан: /opt/warp-native/warp-watchdog.sh${NC}"

    # Создаём cron задачу
    cat > /etc/cron.d/warp-native <<EOF
# warp-native watchdog — checks WARP tunnel health
${WATCHDOG_CRON_INTERVAL} root /opt/warp-native/warp-watchdog.sh
EOF
    chmod 644 /etc/cron.d/warp-native
    echo -e "${GREEN}✅ Cron задача создана: /etc/cron.d/warp-native${NC}\n"

    # Шаг 11: Создание команды warp
    echo -e "${YELLOW}11. Создание команды warp...${NC}"
    cat > /usr/local/bin/warp <<'WARP_CMD_EOF'
#!/bin/bash
function show_status {
    echo ""
    echo -e "\e[1;35m╭─────────────────────────────────────╮\e[0m"
    echo -e "\e[1;35m│\e[0m      \e[1;36m  W A R P - N A T I V E        \e[1;35m│\e[0m"
    echo -e "\e[1;35m│\e[0m     \e[2;37m       by distillium            \e[1;35m│\e[0m"
    echo -e "\e[1;35m╰─────────────────────────────────────╯\e[0m"
    echo ""
    
    if systemctl is-active --quiet wg-quick@warp; then
        status="\e[1;32mactive\e[0m"
    else
        status="\e[1;31minactive\e[0m"
    fi
    
    tunnel_ip=$(ip addr show warp 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    [ -z "$tunnel_ip" ] && tunnel_ip="—"
    
    hs_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
    if [[ -n "$hs_ts" && "$hs_ts" -gt 0 ]]; then
        age=$(( $(date +%s) - hs_ts ))
        handshake="${age}s ago"
    else
        handshake="—"
    fi
    
    account_type=$(wgcf status 2>/dev/null | grep -i "Account type" | awk -F': ' '{print $2}' | xargs)
    if [[ "$account_type" == "unlimited" ]]; then
        account="WARP+"
    elif [[ -n "$account_type" ]]; then
        account="Free"
    else
        account="—"
    fi
    
    echo -e "  \e[1;36mСтатус     :\e[0m $status"
    echo -e "  \e[1;36mIP туннеля :\e[0m $tunnel_ip"
    echo -e "  \e[1;36mHandshake  :\e[0m $handshake"
    echo -e "  \e[1;36mАккаунт    :\e[0m $account"
    echo ""
    echo -e "\e[1;35m──────────────────────────────────────\e[0m"
    echo -e "  \e[1;32mwarp start\e[0m    — запустить"
    echo -e "  \e[1;32mwarp stop\e[0m     — остановить"
    echo -e "  \e[1;32mwarp restart\e[0m  — перезапустить"
    echo -e "  \e[1;32mwarp log\e[0m      — лог watchdog"
    echo -e "\e[1;35m──────────────────────────────────────\e[0m"
    echo ""
}

case "$1" in
    start)   systemctl start wg-quick@warp ;;
    stop)    systemctl stop wg-quick@warp ;;
    restart) systemctl restart wg-quick@warp ;;
    log)
        if [[ ! -f /opt/warp-native/logs/watchdog.log ]]; then
            echo "Лог пока пуст — watchdog ещё не запускался."
        else
            tail -f /opt/warp-native/logs/watchdog.log
        fi
        ;;
    *)       show_status ;;
esac
WARP_CMD_EOF

    chmod +x /usr/local/bin/warp
    echo -e "${GREEN}✅ Команда \e[1;32mwarp\e[0m создана: введите \e[1;32mwarp\e[0m для просмотра статуса.${NC}\n"

    # Восстанавливаем DNS
    if [ -f /etc/resolv.conf.backup ]; then
        cp /etc/resolv.conf.backup /etc/resolv.conf
        echo -e "${GREEN}✅ DNS возвращены к заводскому состоянию (восстановлены из резервной копии)${NC}\n"
    fi

    # Итоговая сводка
    tunnel_ip=$(ip addr show warp 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    [[ -z "$tunnel_ip" ]] && tunnel_ip="—"
    
    final_handshake_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
    if [[ -n "$final_handshake_ts" && "$final_handshake_ts" -gt 0 ]]; then
        final_age=$(( $(date +%s) - final_handshake_ts ))
        handshake_display="${final_age} сек. назад"
    else
        handshake_display="—"
    fi
    
    if [[ "$wgcf_account_type" == "unlimited" ]]; then
        account_display="WARP+"
    elif [[ -n "$wgcf_account_type" ]]; then
        account_display="Free"
    else
        account_display="—"
    fi

    echo -e "${GREEN}✅ Установка и настройка Cloudflare WARP завершены!${NC}\n"
    echo -e "${CYAN}═══════════════ ИТОГ ═══════════════${NC}"
    echo -e "${CYAN}  Тип аккаунта :${NC} ${account_display}"
    echo -e "${CYAN}  IP туннеля   :${NC} ${tunnel_ip}"
    echo -e "${CYAN}  Handshake    :${NC} ${handshake_display}"
    echo -e "${CYAN}════════════════════════════════════${NC}\n"
    
    echo -e "${GREEN}➤ warp${NC} — статус туннеля и управление\n"
    echo -e "${CYAN}➤ Отключить автозапуск:${NC} systemctl disable wg-quick@warp"
    echo -e "${CYAN}➤ Включить автозапуск:${NC} systemctl enable wg-quick@warp"
    echo -e "${CYAN}➤ Настройки watchdog:${NC} nano /opt/warp-native/config.env\n"
    
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 2.2: УДАЛЕНИЕ CLOUDFLARE WARP
# ============================================
uninstall_warp() {
    show_logo
    echo -e "${BLUE}${BOLD}🗑️  Удаление Cloudflare WARP${NC}\n"

    # Проверка прав root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Скрипт должен быть запущен от root.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # Остановка интерфейса
    if ip link show warp &>/dev/null; then
        echo -e "${YELLOW}Отключаем интерфейс warp...${NC}"
        wg-quick down warp &>/dev/null || true
    fi

    systemctl disable wg-quick@warp &>/dev/null || true
    rm -f /etc/wireguard/warp.conf &>/dev/null
    rm -rf /etc/wireguard &>/dev/null
    rm -f /usr/local/bin/wgcf &>/dev/null
    rm -f wgcf-account.toml wgcf-profile.conf &>/dev/null

    # Удаление watchdog
    echo -e "${YELLOW}Удаляем watchdog и cron задачу...${NC}"
    rm -f /etc/cron.d/warp-native &>/dev/null
    rm -rf /opt/warp-native &>/dev/null

    # Удаление пакетов
    echo -e "${YELLOW}Удаляем пакеты wireguard...${NC}"
    DEBIAN_FRONTEND=noninteractive apt remove --purge -y wireguard &>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt autoremove -y &>/dev/null || true

    # Удаление команды warp
    rm -f /usr/local/bin/warp &>/dev/null

    echo -e "\n${GREEN}✅ Удаление завершено.${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 3.1: УСТАНОВКА REMNAWAVE ADMIN WEB + BOT
# ============================================
install_admin_bot() {
    show_logo
    echo -e "${BLUE}${BOLD}🤖 Установка Remnawave Admin Web + Bot${NC}\n"

    install_docker

    # Вопрос о месте установки
    echo -e "${YELLOW}Где устанавливается бот?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель Remnawave"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" server_location

    if [[ "$server_location" == "1" ]]; then
        API_BASE_URL="http://remnawave:3000"
        SAME_SERVER=true
    else
        read -p "🌐 Введите домен панели Remnawave (например panel.myvpn.com): " PANEL_URL
        API_BASE_URL="https://$PANEL_URL"
        SAME_SERVER=false
    fi

    # Запрос обязательных данных
    echo -e "\n${YELLOW}📥 Введите данные для настройки:${NC}\n"
    
    read -p "🤖 BOT_TOKEN (от @BotFather): " BOT_TOKEN
    if [ -z "$BOT_TOKEN" ]; then
        echo -e "${RED}❌ Ошибка: BOT_TOKEN не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "🔑 API_TOKEN (отдельный токен для бота, как для страницы подписки): " API_TOKEN
    if [ -z "$API_TOKEN" ]; then
        echo -e "${RED}❌ Ошибка: API_TOKEN не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "👤 ADMINS (Telegram ID через запятую): " ADMINS
    if [ -z "$ADMINS" ]; then
        echo -e "${RED}❌ Ошибка: ADMINS не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "📱 TELEGRAM_BOT_USERNAME (без @): " TELEGRAM_BOT_USERNAME
    if [ -z "$TELEGRAM_BOT_USERNAME" ]; then
        echo -e "${RED}❌ Ошибка: TELEGRAM_BOT_USERNAME не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "🌐 Домен для админ-панели (например admin.myvpn.com): " ADMIN_DOMAIN
    if [ -z "$ADMIN_DOMAIN" ]; then
        echo -e "${RED}❌ Ошибка: Домен не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # Вопрос о Bedolaga Bot
    echo -e "\n${YELLOW}🔗 Подключить Bedolaga Bot?${NC}"
    echo -e "  ${CYAN}1)${NC} Да"
    echo -e "  ${CYAN}2)${NC} Нет (по умолчанию)"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор [1-2, Enter = 2]: )" bedolaga_choice

    BEDOLAGA_API_URL=""
    BEDOLAGA_API_TOKEN=""
    if [[ "$bedolaga_choice" == "1" ]]; then
        read -p "🌐 Домен Bedolaga Bot: " BEDOLAGA_API_URL
        read -p "🔑 BEDOLAGA_API_TOKEN: " BEDOLAGA_API_TOKEN
    fi

    # Генерация секретных ключей
    echo -e "\n${YELLOW}🔐 Генерируем секретные ключи...${NC}"
    WEBHOOK_SECRET=$(openssl rand -hex 64)
    WEB_SECRET_KEY=$(openssl rand -hex 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    echo -e "${GREEN}✅ Секретные ключи сгенерированы.${NC}\n"

    # Создание директории
    echo -e "${YELLOW}📁 Создаём директорию...${NC}"
    mkdir -p /opt/remnawave-admin && cd /opt/remnawave-admin

    # Клонирование репозитория
    echo -e "${YELLOW}📥 Клонируем репозиторий...${NC}"
    git clone https://github.com/Case211/remnawave-admin.git . || {
        echo -e "${RED}❌ Не удалось клонировать репозиторий.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }

    # Создание .env файла
    echo -e "${YELLOW}⚙️  Создаём .env файл...${NC}"
    cat > .env <<EOF
# 🤖 Токен бота (из @BotFather)
BOT_TOKEN=$BOT_TOKEN

# 🌐 Адрес API Remnawave
API_BASE_URL=$API_BASE_URL

# 🔑 API-токен из панели Remnawave
API_TOKEN=$API_TOKEN

# 👤 Telegram ID администраторов (через запятую)
ADMINS=$ADMINS
DEFAULT_LOCALE=ru
LOG_LEVEL=INFO

# 🔔 Webhook
WEBHOOK_PORT=9090
WEBHOOK_SECRET=$WEBHOOK_SECRET

# 🗄 PostgreSQL
POSTGRES_USER=remnawave
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=remnawave_bot
DATABASE_URL=postgresql://remnawave:$POSTGRES_PASSWORD@remnawave-admin-db:5432/remnawave_bot
DB_POOL_MIN_SIZE=2
DB_POOL_MAX_SIZE=10
SYNC_INTERVAL_SECONDS=300

# 🌐 Веб-панель
WEB_SECRET_KEY=$WEB_SECRET_KEY
WEB_JWT_EXPIRE_MINUTES=30
WEB_JWT_REFRESH_HOURS=6
WEB_BACKEND_PORT=9091
WEB_FRONTEND_PORT=13000
WEB_CORS_ORIGINS=https://$ADMIN_DOMAIN
EXTERNAL_API_ENABLED=false
EXTERNAL_API_DOCS=false
TELEGRAM_BOT_USERNAME=$TELEGRAM_BOT_USERNAME

# 📊 Prometheus
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=30d
EOF

    # Добавление Bedolaga Bot
    if [[ "$bedolaga_choice" == "1" ]]; then
        cat >> .env <<EOF

# 💰 Интеграция Bedolaga Bot
BEDOLAGA_API_URL=$BEDOLAGA_API_URL
BEDOLAGA_API_TOKEN=$BEDOLAGA_API_TOKEN
EOF
    else
        cat >> .env <<EOF

# 💰 Интеграция Bedolaga Bot
# BEDOLAGA_API_URL=
# BEDOLAGA_API_TOKEN=
EOF
    fi

    echo -e "${GREEN}✅ .env файл создан.${NC}\n"

    # Создание Docker-сети
    echo -e "${YELLOW}🌐 Создаём Docker-сеть...${NC}"
    docker network create remnawave-network 2>/dev/null || true

    # Запуск контейнеров
    echo -e "${YELLOW}🚀 Запускаем контейнеры...${NC}"
    docker compose up -d || {
        echo -e "${RED}❌ Не удалось запустить контейнеры.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Контейнеры запущены.${NC}\n"

    # Настройка Caddy
    if [[ "$SAME_SERVER" == true ]]; then
        echo -e "${YELLOW}🔧 Настраиваем Caddy...${NC}"
        cd /opt/remnawave/caddy
        
        # Проверяем, есть ли уже этот домен
        if ! grep -q "$ADMIN_DOMAIN" Caddyfile; then
            cat >> Caddyfile <<EOF

# ======================
# Remnawave Admin + Bot
# =====================
https://$ADMIN_DOMAIN {
    # Frontend
    handle {
        reverse_proxy web-frontend:80
    }

    # Backend API
    handle /api/* {
        reverse_proxy web-backend:9091 {
            header_up X-Real-IP {remote_host}
            header_up X-Forwarded-For {remote_host}
            header_up X-Forwarded-Proto {scheme}
        }
    }

    # WebSocket (браузер + node-agent)
    handle /ws/* {
        reverse_proxy web-backend:9091
    }
}
EOF
            
            docker compose down && docker compose up -d
            echo -e "${GREEN}✅ Caddy обновлён.${NC}"
        fi
    else
        echo -e "\n${YELLOW}⚠️  ВАЖНО: Настройка Caddy на отдельном сервере${NC}"
        echo -e "1. Установите Caddy на сервере с ботом"
        echo -e "2. Добавьте в Caddyfile:"
        echo -e "${CYAN}https://$ADMIN_DOMAIN {${NC}"
        echo -e "${CYAN}    handle {${NC}"
        echo -e "${CYAN}        reverse_proxy localhost:80${NC}"
        echo -e "${CYAN}    }${NC}"
        echo -e "${CYAN}    handle /api/* {${NC}"
        echo -e "${CYAN}        reverse_proxy localhost:9091${NC}"
        echo -e "${CYAN}    }${NC}"
        echo -e "${CYAN}    handle /ws/* {${NC}"
        echo -e "${CYAN}        reverse_proxy localhost:9091${NC}"
        echo -e "${CYAN}    }${NC}"
        echo -e "${CYAN}}${NC}\n"
        
        echo -e "3. В панели Remnawave добавьте webhook:"
        echo -e "${CYAN}WEBHOOK_URL=https://$ADMIN_DOMAIN:9090/webhook${NC}"
        echo -e "${CYAN}WEBHOOK_SECRET_HEADER=$WEBHOOK_SECRET${NC}\n"
    fi

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✅ REMNAWAVE ADMIN WEB + BOT УСТАНОВЛЕН! 🎉     ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}🌐 Админ-панель: ${BOLD}https://$ADMIN_DOMAIN${NC}"
    echo -e "${CYAN}🤖 Бот:          ${BOLD}@$TELEGRAM_BOT_USERNAME${NC}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}⚠️  Следующие шаги:${NC}"
    echo -e "1. Откройте бота в Telegram и отправьте /start"
    echo -e "2. Перейдите в веб-панель и создайте аккаунт администратора"
    if [[ "$SAME_SERVER" == true ]]; then
        echo -e "3. В панели Remnawave добавьте webhook:"
        echo -e "${CYAN}   WEBHOOK_URL=http://bot:9090/webhook${NC}"
        echo -e "${CYAN}   WEBHOOK_SECRET_HEADER=$WEBHOOK_SECRET${NC}"
    fi
    echo ""
    
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 3.2: ОБНОВЛЕНИЕ REMNAWAVE ADMIN
# ============================================
update_rwa() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Remnawave Admin Web + Bot${NC}\n"

    if [ ! -d "/opt/remnawave-admin" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/remnawave-admin не найдена. Сначала установите бота.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем Remnawave Admin...${NC}"
    cd /opt/remnawave-admin
    git pull origin main
    docker compose down
    docker compose up -d
    echo -e "${GREEN}✅ Remnawave Admin обновлён и запущен.${NC}"

    echo -e "\n${YELLOW}🧹 Очищаем неиспользуемые образы...${NC}"
    docker image prune -f
    echo -e "${GREEN}✅ Очистка завершена.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║   ✅ ОБНОВЛЕНИЕ REMNAWAVE ADMIN ЗАВЕРШЕНО! 🎉     ║${NC}"
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

    # Вопрос о месте установки
    echo -e "${YELLOW}Где устанавливается бот?${NC}"
    echo -e "  ${CYAN}1)${NC} На том же сервере, где и панель Remnawave"
    echo -e "  ${CYAN}2)${NC} На отдельном сервере"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" server_location

    if [[ "$server_location" == "1" ]]; then
        REMNAWAVE_API_URL="http://remnawave:3000"
        SAME_SERVER=true
    else
        read -p "🌐 Введите домен панели Remnawave (например panel.myvpn.com): " PANEL_URL
        REMNAWAVE_API_URL="https://$PANEL_URL"
        SAME_SERVER=false
    fi

    # Запрос обязательных данных
    echo -e "\n${YELLOW}📥 Введите данные для настройки:${NC}\n"
    
    read -p "🤖 BOT_TOKEN (от @BotFather): " BOT_TOKEN
    if [ -z "$BOT_TOKEN" ]; then
        echo -e "${RED}❌ Ошибка: BOT_TOKEN не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "👤 ADMIN_IDS (Telegram ID через запятую): " ADMIN_IDS
    if [ -z "$ADMIN_IDS" ]; then
        echo -e "${RED}❌ Ошибка: ADMIN_IDS не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "🔑 REMNAWAVE_API_KEY (API ключ из панели): " REMNAWAVE_API_KEY
    if [ -z "$REMNAWAVE_API_KEY" ]; then
        echo -e "${RED}❌ Ошибка: REMNAWAVE_API_KEY не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    read -p "🌐 Домен для бота (например bedolaga.myvpn.com): " BEDOLAGA_DOMAIN
    if [ -z "$BEDOLAGA_DOMAIN" ]; then
        echo -e "${RED}❌ Ошибка: Домен не может быть пустым!${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    # Вопрос о Cabinet
    echo -e "\n${YELLOW}🗄️  Установить Bedolaga Cabinet?${NC}"
    echo -e "  ${CYAN}1)${NC} Да"
    echo -e "  ${CYAN}2)${NC} Нет (по умолчанию)"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор [1-2, Enter = 2]: )" cabinet_choice

    CABINET_DOMAIN=""
    if [[ "$cabinet_choice" == "1" ]]; then
        read -p "🌐 Домен для Cabinet (например cabinet.myvpn.com): " CABINET_DOMAIN
        if [ -z "$CABINET_DOMAIN" ]; then
            echo -e "${RED}❌ Ошибка: Домен Cabinet не может быть пустым!${NC}"
            read -p "Нажмите Enter для возврата в меню..."
            return
        fi
    fi

    # Генерация секретных ключей
    echo -e "\n${YELLOW}🔐 Генерируем секретные ключи...${NC}"
    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    WEBHOOK_SECRET_TOKEN=$(openssl rand -hex 32)
    WEB_API_DEFAULT_TOKEN=$(openssl rand -hex 32)
    CABINET_JWT_SECRET=""
    if [[ -n "$CABINET_DOMAIN" ]]; then
        CABINET_JWT_SECRET=$(openssl rand -hex 32)
    fi
    echo -e "${GREEN}✅ Секретные ключи сгенерированы.${NC}\n"

    # Создание директории
    echo -e "${YELLOW}📁 Создаём директорию...${NC}"
    mkdir -p /opt/bedolaga-bot && cd /opt/bedolaga-bot

    # Клонирование репозитория
    echo -e "${YELLOW}📥 Клонируем репозиторий...${NC}"
    git clone https://github.com/BEDOLAGA-DEV/remnawave-bedolaga-telegram-bot.git . || {
        echo -e "${RED}❌ Не удалось клонировать репозиторий.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }

    # Создание .env файла
    echo -e "${YELLOW}⚙️  Создаём .env файл...${NC}"
    cat > .env <<EOF
# Bot token and admin-id
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS

# Remnawave
REMNAWAVE_API_URL=$REMNAWAVE_API_URL
REMNAWAVE_API_KEY=$REMNAWAVE_API_KEY
REMNAWAVE_AUTH_TYPE=api_key

# DataBase
POSTGRES_DB=remnawave_bot
POSTGRES_USER=remnawave_user
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Bot Webhook
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

    # Добавление Cabinet
    if [[ -n "$CABINET_DOMAIN" ]]; then
        cat >> .env <<EOF

# Bedolaga Cabinet
CABINET_ENABLED=true
CABINET_JWT_SECRET=$CABINET_JWT_SECRET
CABINET_ALLOWED_ORIGINS=https://$CABINET_DOMAIN
CABINET_URL=https://$CABINET_DOMAIN
EOF
    else
        cat >> .env <<EOF

# Bedolaga Cabinet
# CABINET_ENABLED=true
# CABINET_JWT_SECRET=
# CABINET_ALLOWED_ORIGINS=
# CABINET_URL=
EOF
    fi

    echo -e "${GREEN}✅ .env файл создан.${NC}\n"

    # Создание директорий
    echo -e "${YELLOW}📂 Создаём директории...${NC}"
    mkdir -p ./logs ./data ./data/backups ./data/referral_qr
    chmod -R 755 ./logs ./data
    chown -R 1000:1000 ./logs ./data
    echo -e "${GREEN}✅ Директории созданы.${NC}\n"

    # Создание Docker-сети
    echo -e "${YELLOW}🌐 Создаём Docker-сеть...${NC}"
    docker network create remnawave-network 2>/dev/null || true
    docker network create remnawave_bot_network 2>/dev/null || true

    # Запуск контейнеров
    echo -e "${YELLOW}🚀 Запускаем контейнеры...${NC}"
    docker compose up -d || {
        echo -e "${RED}❌ Не удалось запустить контейнеры.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    }
    echo -e "${GREEN}✅ Контейнеры запущены.${NC}\n"

    # Установка Cabinet если выбран
    if [[ -n "$CABINET_DOMAIN" ]]; then
        echo -e "${YELLOW}🗄️  Устанавливаем Bedolaga Cabinet...${NC}"
        
        # Получение frontend файлов
        echo -e "${YELLOW}📥 Получаем frontend файлы...${NC}"
        docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
        docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
        docker cp tmp_cabinet:/usr/share/nginx/html ./cabinet-dist
        docker rm tmp_cabinet
        
        # Размещение файлов
        mkdir -p /srv/cabinet
        cp -r ./cabinet-dist/* /srv/cabinet/
        echo -e "${GREEN}✅ Cabinet файлы размещены.${NC}\n"
    fi

    # Настройка Caddy
    if [[ "$SAME_SERVER" == true ]]; then
        echo -e "${YELLOW}🔧 Настраиваем Caddy...${NC}"
        cd /opt/remnawave/caddy
        
        # Проверяем, есть ли уже этот домен
        if ! grep -q "$BEDOLAGA_DOMAIN" Caddyfile; then
            cat >> Caddyfile <<EOF

# ===============================
# Bedolaga Bot
# ===============================
https://$BEDOLAGA_DOMAIN {
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
}
EOF
            
            # Добавление Cabinet если установлен
            if [[ -n "$CABINET_DOMAIN" ]] && ! grep -q "$CABINET_DOMAIN" Caddyfile; then
                cat >> Caddyfile <<EOF

# =============================
# Bedolaga Cabinet
# ============================
https://$CABINET_DOMAIN {
    encode gzip zstd

    # API запросы → backend бота
    handle /api/* {
        uri strip_prefix /api
        reverse_proxy remnawave_bot:8080
    }

    # Frontend → nginx контейнер (порт 80 внутри Docker сети)
    handle {
        reverse_proxy cabinet_frontend:80
    }
}
EOF
            fi
            
            docker compose down && docker compose up -d
            echo -e "${GREEN}✅ Caddy обновлён.${NC}"
        fi
    else
        echo -e "\n${YELLOW}⚠️  ВАЖНО: Настройка Caddy на отдельном сервере${NC}"
        echo -e "1. Установите Caddy на сервере с ботом"
        echo -e "2. Добавьте в Caddyfile:"
        echo -e "${CYAN}https://$BEDOLAGA_DOMAIN {${NC}"
        echo -e "${CYAN}    encode gzip zstd${NC}"
        echo -e "${CYAN}    handle {${NC}"
        echo -e "${CYAN}        reverse_proxy remnawave_bot:8080 {${NC}"
        echo -e "${CYAN}            header_up Host {host}${NC}"
        echo -e "${CYAN}            header_up X-Real-IP {remote_host}${NC}"
        echo -e "${CYAN}            transport http {${NC}"
        echo -e "${CYAN}                read_buffer 0${NC}"
        echo -e "${CYAN}            }${NC}"
        echo -e "${CYAN}        }${NC}"
        echo -e "${CYAN}    }${NC}"
        echo -e "${CYAN}}${NC}\n"
        
        if [[ -n "$CABINET_DOMAIN" ]]; then
            echo -e "3. Для Cabinet добавьте:"
            echo -e "${CYAN}https://$CABINET_DOMAIN {${NC}"
            echo -e "${CYAN}    encode gzip zstd${NC}"
            echo -e "${CYAN}    handle /api/* {${NC}"
            echo -e "${CYAN}        uri strip_prefix /api${NC}"
            echo -e "${CYAN}        reverse_proxy remnawave_bot:8080${NC}"
            echo -e "${CYAN}    }${NC}"
            echo -e "${CYAN}    handle {${NC}"
            echo -e "${CYAN}        reverse_proxy cabinet_frontend:80${NC}"
            echo -e "${CYAN}    }${NC}"
            echo -e "${CYAN}}${NC}\n"
        fi
    fi

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ BEDOLAGA BOT УСТАНОВЛЕН! 🎉             ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}🤖 Бот:     ${BOLD}https://$BEDOLAGA_DOMAIN${NC}"
    if [[ -n "$CABINET_DOMAIN" ]]; then
        echo -e "${CYAN}🗄️  Cabinet: ${BOLD}https://$CABINET_DOMAIN${NC}"
    fi
    echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}⚠️  Следующие шаги:${NC}"
    echo -e "1. Откройте бота в Telegram и отправьте /start"
    if [[ -n "$CABINET_DOMAIN" ]]; then
        echo -e "2. Откройте Cabinet и авторизуйтесь через Telegram"
    fi
    echo ""
    
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 4.2: ОБНОВЛЕНИЕ BEDOLAGA BOT
# ============================================
update_bedolaga() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Bedolaga Bot${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/bedolaga-bot не найдена. Сначала установите бота.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем Bedolaga Bot...${NC}"
    cd /opt/bedolaga-bot
    git pull origin main
    docker compose down
    docker compose up -d --build
    echo -e "${GREEN}✅ Bedolaga Bot обновлён и запущен.${NC}"

    echo -e "\n${YELLOW}🧹 Очищаем неиспользуемые образы...${NC}"
    docker image prune -f
    echo -e "${GREEN}✅ Очистка завершена.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║      ✅ ОБНОВЛЕНИЕ BEDOLAGA BOT ЗАВЕРШЕНО! 🎉     ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 4.3: ОБНОВЛЕНИЕ CABINET
# ============================================
update_cabinet() {
    show_logo
    echo -e "${BLUE}${BOLD}🔄 Обновление Bedolaga Cabinet${NC}\n"

    if [ ! -d "/opt/bedolaga-bot" ]; then
        echo -e "${RED}❌ Ошибка: Папка /opt/bedolaga-bot не найдена. Сначала установите бота.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return
    fi

    echo -e "${YELLOW}📥 Обновляем Bedolaga Cabinet...${NC}"
    cd /opt/bedolaga-bot
    
    # Обновление frontend
    docker pull ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    docker create --name tmp_cabinet ghcr.io/bedolaga-dev/bedolaga-cabinet:latest
    rm -rf ./cabinet-dist
    docker cp tmp_cabinet:/usr/share/nginx/html ./cabinet-dist
    docker rm tmp_cabinet
    
    # Размещение файлов
    rm -rf /srv/cabinet/*
    cp -r ./cabinet-dist/* /srv/cabinet/
    
    # Перезапуск cabinet контейнера если есть
    if docker ps -a | grep -q cabinet_frontend; then
        docker restart cabinet_frontend
    fi
    
    echo -e "${GREEN}✅ Bedolaga Cabinet обновлён.${NC}"

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║     ✅ ОБНОВЛЕНИЕ CABINET ЗАВЕРШЕНО! 🎉           ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 5.1: СОЗДАНИЕ БЭКАПА
# ============================================
create_backup() {
    show_logo
    echo -e "${BLUE}${BOLD}💾 Создание бэкапа панели${NC}\n"

    if [ ! -f "/usr/local/bin/rw-backup" ]; then
        echo -e "${YELLOW}📥 Устанавливаем скрипт бэкапов...${NC}"
        curl -Ls https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh -o /tmp/backup-restore.sh
        chmod +x /tmp/backup-restore.sh
        bash /tmp/backup-restore.sh backup
    else
        rw-backup backup
    fi

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ БЭКАП СОЗДАН! 🎉                        ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ОПЦИЯ 5.2: ВОССТАНОВЛЕНИЕ ИЗ БЭКАПА
# ============================================
restore_backup() {
    show_logo
    echo -e "${BLUE}${BOLD}💾 Восстановление из бэкапа${NC}\n"

    if [ ! -f "/usr/local/bin/rw-backup" ]; then
        echo -e "${YELLOW}📥 Устанавливаем скрипт бэкапов...${NC}"
        curl -Ls https://raw.githubusercontent.com/distillium/remnawave-backup-restore/main/backup-restore.sh -o /tmp/backup-restore.sh
        chmod +x /tmp/backup-restore.sh
        bash /tmp/backup-restore.sh restore
    else
        rw-backup restore
    fi

    echo -e "\n${GREEN}${BOLD}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║        ✅ ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО! 🎉            ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════╝${NC}\n"
    read -p "Нажмите Enter для возврата в меню..."
}

# ============================================
# ПОДМЕНЮ: REMNAWAVE
# ============================================
show_remnawave_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🚀 Remnawave${NC}\n"
        echo -e "${BOLD}Выберите действие:${NC}"
        echo -e "  ${CYAN}1)${NC} 🚀 Установить Панель + Страницу подписки"
        echo -e "  ${CYAN}2)${NC} 🖥️  Установить Ноду"
        echo -e "  ${CYAN}3)${NC} 🔄 Обновить компоненты"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" remnawave_choice

        case $remnawave_choice in
            1) install_panel ;;
            2) install_node ;;
            3) update_components ;;
            0) break ;;
            *)
                echo -e "${RED}❌ Неверный выбор.${NC}"
                sleep 2
                ;;
        esac
    done
}

# ============================================
# ПОДМЕНЮ: CLOUDFLARE WARP
# ============================================
show_warp_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🌐 Cloudflare WARP${NC}\n"
        echo -e "${BOLD}Выберите действие:${NC}"
        echo -e "  ${CYAN}1)${NC} 🌐 Установить Cloudflare WARP"
        echo -e "  ${CYAN}2)${NC} 🗑️  Удалить Cloudflare WARP"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" warp_choice

        case $warp_choice in
            1) install_warp ;;
            2) uninstall_warp ;;
            0) break ;;
            *)
                echo -e "${RED}❌ Неверный выбор.${NC}"
                sleep 2
                ;;
        esac
    done
}

# ============================================
# ПОДМЕНЮ: REMNAWAVE ADMIN WEB + BOT
# ============================================
show_admin_bot_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}🤖 Remnawave Admin Web + Bot${NC}\n"
        echo -e "${BOLD}Выберите действие:${NC}"
        echo -e "  ${CYAN}1)${NC} 🤖 Установить Admin Web + Bot"
        echo -e "  ${CYAN}2)${NC} 🔄 Обновить Admin Web + Bot"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" admin_bot_choice

        case $admin_bot_choice in
            1) install_admin_bot ;;
            2) update_rwa ;;
            0) break ;;
            *)
                echo -e "${RED}❌ Неверный выбор.${NC}"
                sleep 2
                ;;
        esac
    done
}

# ============================================
# ПОДМЕНЮ: BEDOLAGA BOT
# ============================================
show_bedolaga_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}💰 Bedolaga Bot${NC}\n"
        echo -e "${BOLD}Выберите действие:${NC}"
        echo -e "  ${CYAN}1)${NC} 💰 Установить Bedolaga Bot"
        echo -e "  ${CYAN}2)${NC} 🔄 Обновить Bedolaga Bot"
        echo -e "  ${CYAN}3)${NC} 🗄️  Обновить Cabinet"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" bedolaga_choice

        case $bedolaga_choice in
            1) install_bedolaga ;;
            2) update_bedolaga ;;
            3) update_cabinet ;;
            0) break ;;
            *)
                echo -e "${RED}❌ Неверный выбор.${NC}"
                sleep 2
                ;;
        esac
    done
}

# ============================================
# ПОДМЕНЮ: БЭКАПЫ
# ============================================
show_backup_menu() {
    while true; do
        show_logo
        echo -e "${BLUE}${BOLD}💾 Бэкапы панели${NC}\n"
        echo -e "${BOLD}Выберите действие:${NC}"
        echo -e "  ${CYAN}1)${NC} 💾 Создать бэкап"
        echo -e "  ${CYAN}2)${NC} 📥 Восстановить из бэкапа"
        echo -e "  ${CYAN}0)${NC} 🔙 Назад в главное меню"
        echo ""
        read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" backup_choice

        case $backup_choice in
            1) create_backup ;;
            2) restore_backup ;;
            0) break ;;
            *)
                echo -e "${RED}❌ Неверный выбор.${NC}"
                sleep 2
                ;;
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
    echo -e "  ${CYAN}4)${NC} 💰 Bedolaga Bot"
    echo -e "  ${CYAN}5)${NC} 💾 Бэкапы"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}0)${NC} 🚪 Выход"
    echo ""
    read -p "$(echo -e ${CYAN}▶${NC} Ваш выбор: )" main_choice

    case $main_choice in
        1) show_remnawave_menu ;;
        2) show_warp_menu ;;
        3) show_admin_bot_menu ;;
        4) show_bedolaga_menu ;;
        5) show_backup_menu ;;
        0)
            echo -e "${GREEN}👋 До свидания!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Неверный выбор.${NC}"
            sleep 2
            ;;
    esac
done
