<div align="center">

# ⚡ Just Remnawave Auto Installer

### 🚀 Быстрая установка панели Remnawave в один клик

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](https://github.com/tneange1/Just-Remnawave-Auto-Installer/releases)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-orange.svg)](https://www.gnu.org/software/bash/)
[![Docker](https://img.shields.io/badge/docker-required-blue.svg)](https://www.docker.com/)

[🚀 Быстрый старт](#-быстрый-старт) • [📖 Документация](#-использование) • [💖 Поддержать](#-поддержать-проект) • [💬 Сообщество](#-сообщество-и-контакты)

</div>

---

## 📖 О проекте

**Just Remnawave Auto Installer** — это bash-скрипт с интерактивным меню для моментальной установки панели управления [Remnawave](https://github.com/remnawave). Забудьте о ручном копировании команд — скрипт сам всё скачает, настроит и запустит.

> 💡 **Идеально для YouTube-гайдов и Telegram-каналов** — все команды уже встроены в скрипт!

## ✨ Возможности

- 🎯 **Интерактивное меню** — выбирай, что устанавливать
- 🔐 **Автоматическая генерация** всех JWT-секретов и паролей БД
- 🌐 **Настройка HTTPS** через Caddy из коробки
- 📄 **Страница подписки** устанавливается вместе с панелью
- 🖥️ **Отдельная установка ноды** на другой сервер
- 🐳 **Docker** ставится автоматически, если его нет
- 🎨 **Красивый цветной вывод** с логотипом

## 📋 Требования

- 🖥️ Чистый сервер на **Ubuntu / Debian**
- 🔑 Root-доступ (sudo)
- 🌐 Домен(ы), направленные на IP сервера (A-запись)

## 🚀 Быстрый старт

Просто выполни одну команду на сервере:

```bash
curl -Ls https://raw.githubusercontent.com/tneange1/Just-Remnawave-Auto-Installer/main/setup.sh -o setup.sh
sudo bash setup.sh
