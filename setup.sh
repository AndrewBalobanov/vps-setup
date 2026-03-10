#!/bin/bash

# Прерывать выполнение при ошибках
set -e

# =============================================================================
# Скрипт настройки сервера для проекта aicopilot-presentation
# Ubuntu 24.04 LTS
# =============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода статуса
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
}

# Проверка запуска от root
if [[ $EUID -ne 0 ]]; then
   log_error "Скрипт должен быть запущен от root"
   exit 1
fi

# Выводить команды в лог при ошибке (трассировка)
trap 'log_error "Ошибка на строке $LINENO. Код выхода: $?"' ERR

# =============================================================================
# ПЕРЕМЕННЫЕ
# =============================================================================

# --- Интерактивный ввод параметров ---
log_section "Ввод параметров настройки"

# Функция для чтения непустого значения
read_required() {
    local prompt="$1"
    local varname="$2"
    local default="$3"
    local value=""

    while true; do
        if [ -n "${default}" ]; then
            read -r -p "${prompt} [${default}]: " value < /dev/tty
            value="${value:-${default}}"
        else
            read -r -p "${prompt}: " value < /dev/tty
        fi

        if [ -n "${value}" ]; then
            eval "${varname}='${value}'"
            break
        else
            echo -e "${RED}[ERROR]${NC} Значение не может быть пустым. Попробуйте снова."
        fi
    done
}

# Функция для чтения пароля (без отображения на экране)
read_password() {
    local prompt="$1"
    local varname="$2"
    local value=""
    local value2=""

    while true; do
        read -r -s -p "${prompt}: " value < /dev/tty
        echo ""
        read -r -s -p "Повторите пароль: " value2 < /dev/tty
        echo ""

        if [ -z "${value}" ]; then
            echo -e "${RED}[ERROR]${NC} Пароль не может быть пустым. Попробуйте снова."
            continue
        fi

        if [ "${value}" = "${value2}" ]; then
            eval "${varname}='${value}'"
            break
        else
            echo -e "${RED}[ERROR]${NC} Пароли не совпадают. Попробуйте снова."
        fi
    done
}

echo -e "${BLUE}Введите параметры для настройки сервера:${NC}\n"

# Запрос домена
read_required "Введите доменное имя (например: example.ru)" DOMAIN

# Директория проекта формируется из домена: убираем www. если есть,
# берём только первую часть до первой точки
DOMAIN_CLEAN="${DOMAIN#www.}"
PROJECT_NAME="${DOMAIN_CLEAN%%.*}"
WWW_DIR="/var/www/${PROJECT_NAME}"

echo -e "${GREEN}[INFO]${NC} Директория проекта: ${WWW_DIR}"

# Запрос параметров базы данных
echo ""
echo -e "${BLUE}Параметры базы данных:${NC}"
read_required "Имя базы данных" DB_NAME "rehab_db"
read_required "Имя пользователя БД" DB_USER "rehab_user"
read_password "Пароль пользователя БД" DB_PASS

# SSH порт и email
SSH_PORT=22
EMAIL="admin@${DOMAIN}"

# Подтверждение введённых параметров
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE} Проверьте введённые параметры:${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "  Домен:              ${GREEN}${DOMAIN}${NC}"
echo -e "  Директория:         ${GREEN}${WWW_DIR}${NC}"
echo -e "  База данных:        ${GREEN}${DB_NAME}${NC}"
echo -e "  Пользователь БД:    ${GREEN}${DB_USER}${NC}"
echo -e "  Пароль БД:          ${GREEN}(скрыт)${NC}"
echo -e "  SSH порт:           ${GREEN}${SSH_PORT}${NC}"
echo -e "  Email (certbot):    ${GREEN}${EMAIL}${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

read -r -p "Продолжить с этими параметрами? [yes/NO]: " CONFIRM < /dev/tty
if [[ "${CONFIRM}" != "yes" ]]; then
    log_error "Настройка отменена пользователем."
    exit 1
fi

NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}"

log_section "Начало настройки сервера"
log_info "Домен: ${DOMAIN}"
log_info "Директория проекта: ${WWW_DIR}"
log_info "База данных: ${DB_NAME}"
log_info "Пользователь БД: ${DB_USER}"
log_info "SSH порт: ${SSH_PORT}"

# =============================================================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ
# =============================================================================
log_section "1. Обновление системы"

log_info "Обновление списка пакетов и системы..."
apt-get update -y
apt-get upgrade -y

# Установка базовых утилит
log_info "Установка базовых утилит..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    net-tools \
    htop \
    nano \
    vim \
    cron \
    snapd

log_info "Базовые утилиты установлены"

# =============================================================================
# 2. СОЗДАНИЕ ДИРЕКТОРИИ ПРОЕКТА
# =============================================================================
log_section "2. Создание директории проекта"

log_info "Создание директории проекта ${WWW_DIR}..."
mkdir -p ${WWW_DIR}

# Создание базовой структуры директорий
mkdir -p ${WWW_DIR}/public
mkdir -p ${WWW_DIR}/logs

# Создание тестовой страницы
cat > ${WWW_DIR}/public/index.html << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${DOMAIN}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: rgba(255,255,255,0.1);
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        h1 { font-size: 2.5em; margin-bottom: 10px; }
        p { font-size: 1.2em; opacity: 0.9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 ${DOMAIN}</h1>
        <p>Сервер успешно настроен и работает!</p>
        <p>Домен: ${DOMAIN}</p>
    </div>
</body>
</html>
EOF

# Установка правильных прав на директорию
chown -R www-data:www-data ${WWW_DIR}
chmod -R 755 ${WWW_DIR}

log_info "Директория проекта создана успешно"

# =============================================================================
# 3. УСТАНОВКА И НАСТРОЙКА NGINX
# =============================================================================
log_section "3. Установка и настройка Nginx"

log_info "Установка Nginx..."
apt-get install -y nginx

# Запуск и включение автозапуска Nginx
systemctl start nginx
systemctl enable nginx

# Создание конфигурации виртуального хоста для сайта
log_info "Создание конфигурации Nginx для домена ${DOMAIN}..."
cat > ${NGINX_CONF} << EOF
# Конфигурация для домена ${DOMAIN}
# HTTP сервер - перенаправление на HTTPS (будет активно после настройки certbot)
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    # Директория для верификации certbot (Let's Encrypt ACME challenge)
    location /.well-known/acme-challenge/ {
        root ${WWW_DIR}/public;
        allow all;
    }

    # Временно отдаем контент по HTTP (до получения SSL сертификата)
    root ${WWW_DIR}/public;
    index index.html index.htm;

    # Логи доступа и ошибок
    access_log ${WWW_DIR}/logs/access.log;
    error_log ${WWW_DIR}/logs/error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Скрываем версию Nginx (безопасность)
    server_tokens off;

    # Заголовки безопасности
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Ограничение размера загружаемых файлов (100MB)
    client_max_body_size 100M;

    # Настройки буферизации запросов
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;

    # Таймауты соединений
    send_timeout 60;
    keepalive_timeout 65;

    # Gzip сжатие для ускорения загрузки страниц
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript
               application/x-javascript application/xml application/json;
    gzip_disable "MSIE [1-6]\.";
}
EOF

# Активация конфигурации сайта (создание символической ссылки)
log_info "Активация конфигурации сайта..."
ln -sf ${NGINX_CONF} /etc/nginx/sites-enabled/${DOMAIN}

# Удаление дефолтной конфигурации Nginx (если существует)
if [ -f /etc/nginx/sites-enabled/default ]; then
    log_info "Удаление дефолтной конфигурации Nginx..."
    rm /etc/nginx/sites-enabled/default
fi

# Проверка конфигурации Nginx на синтаксические ошибки
log_info "Проверка конфигурации Nginx..."
if ! nginx -t; then
    log_error "Ошибка в конфигурации Nginx!"
    exit 1
fi

# Перезапуск Nginx для применения изменений
systemctl reload nginx
log_info "Nginx успешно настроен"

# =============================================================================
# 4. НАСТРОЙКА ФАЕРВОЛА (UFW)
# =============================================================================
log_section "4. Настройка фаервола UFW"

log_info "Установка UFW..."
apt-get install -y ufw

# Сброс текущих правил UFW до состояния по умолчанию
ufw --force reset

# Политики по умолчанию:
# Блокировать все входящие соединения (белый список)
ufw default deny incoming
# Разрешить все исходящие соединения
ufw default allow outgoing

# КРИТИЧЕСКИ ВАЖНО: Разрешаем SSH ДО включения фаервола!
# Иначе потеряем доступ к серверу!
log_warn "Разрешение SSH доступа (порт ${SSH_PORT}) - КРИТИЧНО!"
ufw allow ${SSH_PORT}/tcp comment 'SSH access - CRITICAL do not remove'

# Разрешаем HTTP (порт 80) для Nginx и прохождения ACME challenge certbot
ufw allow 80/tcp comment 'HTTP Nginx'

# Разрешаем HTTPS (порт 443) для Nginx с SSL сертификатом
ufw allow 443/tcp comment 'HTTPS Nginx SSL'

# Разрешаем PostgreSQL (порт 5432) для удаленного подключения через DBeaver
# ВНИМАНИЕ: Открыто для всех IP - только для тестового сервера!
ufw allow 5432/tcp comment 'PostgreSQL remote access for DBeaver'

# Включаем фаервол (--force чтобы не спрашивал подтверждение)
log_info "Включение фаервола UFW..."
ufw --force enable

# Показываем текущий статус правил фаервола
log_info "Текущий статус фаервола:"
ufw status verbose

log_info "Фаервол настроен"

# =============================================================================
# 5. УСТАНОВКА И НАСТРОЙКА АНТИВИРУСА (ClamAV)
# =============================================================================
log_section "5. Установка антивируса ClamAV"

log_info "Установка ClamAV..."
apt-get install -y clamav clamav-daemon

# Останавливаем freshclam перед обновлением баз,
# чтобы не было конфликта блокировки файлов
systemctl stop clamav-freshclam 2>/dev/null || true

# Ждем несколько секунд для корректной остановки сервиса
sleep 3

# Первоначальное обновление антивирусных баз данных
log_info "Обновление антивирусных баз данных (может занять несколько минут)..."
freshclam || log_warn "Не удалось обновить базы freshclam, продолжаем..."

# Запуск и включение freshclam для автоматического обновления баз
systemctl start clamav-freshclam
systemctl enable clamav-freshclam

# Запуск и включение ClamAV daemon для фонового сканирования
systemctl start clamav-daemon
systemctl enable clamav-daemon

# Создаем директорию для логов ClamAV если её нет
mkdir -p /var/log/clamav

# Создание скрипта для ежедневного автоматического сканирования
log_info "Создание скрипта автоматического сканирования..."
cat > /usr/local/bin/clamscan-daily.sh << 'EOF'
#!/bin/bash
# Ежедневное антивирусное сканирование директории /var/www
SCAN_DIR="/var/www"
LOG_FILE="/var/log/clamav/daily-scan.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Начало сканирования директории: $SCAN_DIR" >> $LOG_FILE

# -r рекурсивное сканирование
# --infected выводить только зараженные файлы
# --log записывать результаты в лог
clamscan -r --infected --log=$LOG_FILE $SCAN_DIR

RESULT=$?
if [ $RESULT -eq 0 ]; then
    echo "[$DATE] Сканирование завершено: угрозы не найдены" >> $LOG_FILE
elif [ $RESULT -eq 1 ]; then
    echo "[$DATE] ВНИМАНИЕ: Найдены зараженные файлы!" >> $LOG_FILE
else
    echo "[$DATE] Ошибка при сканировании (код: $RESULT)" >> $LOG_FILE
fi
EOF

chmod +x /usr/local/bin/clamscan-daily.sh

# Добавление задачи в cron: сканирование каждый день в 3:00 ночи
CRON_JOB="0 3 * * * /usr/local/bin/clamscan-daily.sh"
CRON_ESCAPED=$(echo "${CRON_JOB}" | sed 's/[\/.*]/\\&/g')
(crontab -l 2>/dev/null | grep -v "${CRON_ESCAPED}"; echo "${CRON_JOB}") | crontab -
log_info "Задача cron для ClamAV добавлена"

# =============================================================================
# 6. УСТАНОВКА И НАСТРОЙКА FAIL2BAN (Защита от брутфорса)
# =============================================================================
log_section "6. Установка Fail2Ban"

log_info "Установка Fail2Ban..."
apt-get install -y fail2ban

# Создаем локальный конфиг (jail.local имеет приоритет над jail.conf)
# Это предотвращает перезапись настроек при обновлении пакета
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Время блокировки IP в секундах (3600 = 1 час)
bantime = 3600
# Временной промежуток для подсчета неудачных попыток (600 = 10 минут)
findtime = 600
# Максимальное количество неудачных попыток до бана
maxretry = 5
# Backend для мониторинга - systemd для Ubuntu 24.04
backend = systemd
# Кодировка логов
encoding = utf-8

# Защита SSH от брутфорса
[sshd]
enabled = true
port = ${SSH_PORT}
logpath = %(sshd_log)s
# Для SSH уменьшаем количество попыток до 3
maxretry = 3
# Для SSH увеличиваем время бана до 24 часов
bantime = 86400

# Защита Nginx от HTTP аутентификации брутфорса
[nginx-http-auth]
enabled = true
port = http,https
logpath = %(nginx_error_log)s
maxretry = 5

# Защита Nginx от превышения лимита запросов
[nginx-limit-req]
enabled = true
port = http,https
logpath = %(nginx_error_log)s
maxretry = 10

# Защита PostgreSQL от брутфорса
[postgresql]
enabled = true
port = 5432
logpath = /var/log/postgresql/postgresql-*.log
maxretry = 5
bantime = 3600
EOF

# Запуск и включение Fail2Ban в автозагрузку
systemctl start fail2ban
systemctl enable fail2ban

log_info "Fail2Ban настроен"

# =============================================================================
# 7. УСТАНОВКА И НАСТРОЙКА POSTGRESQL
# =============================================================================
log_section "7. Установка PostgreSQL"

log_info "Установка PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

# Запуск и включение PostgreSQL
systemctl start postgresql
systemctl enable postgresql

# Ждем пока PostgreSQL полностью запустится
sleep 3

# Определение версии PostgreSQL для нахождения директории конфигурации
PG_VERSION=$(pg_lsclusters -h 2>/dev/null | awk 'NR==1{print $1}')
if [ -z "${PG_VERSION}" ]; then
    # Резервный способ через pg_config
    PG_VERSION=$(pg_config --version 2>/dev/null | grep -oP '\d+' | head -1)
fi
if [ -z "${PG_VERSION}" ]; then
    log_error "Не удалось определить версию PostgreSQL!"
    exit 1
fi
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
log_info "Версия PostgreSQL: ${PG_VERSION}"
log_info "Директория конфигурации: ${PG_CONF_DIR}"

# Создание пользователя и базы данных через psql от имени postgres
log_info "Создание пользователя ${DB_USER} и базы данных ${DB_NAME}..."

# Создание пользователя
sudo -u postgres psql -v ON_ERROR_STOP=1 <<PSQL_EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
        RAISE NOTICE 'Пользователь ${DB_USER} создан';
    ELSE
        ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
        RAISE NOTICE 'Пользователь ${DB_USER} уже существует, пароль обновлен';
    END IF;
END
\$\$;
PSQL_EOF

# Создание базы данных (отдельная команда — IF NOT EXISTS не поддерживается в старых версиях)
DB_EXISTS=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null)
if [ "${DB_EXISTS}" != "1" ]; then
    sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
    log_info "База данных ${DB_NAME} создана"
else
    log_info "База данных ${DB_NAME} уже существует"
fi

# Настройка привилегий
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "${DB_NAME}" <<PSQL_EOF
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
\du
\l
PSQL_EOF

log_info "База данных и пользователь созданы"

# =============================================================================
# 8. НАСТРОЙКА УДАЛЕННОГО ДОСТУПА К POSTGRESQL
# =============================================================================
log_section "8. Настройка удаленного доступа PostgreSQL"

log_info "Настройка удаленного доступа к PostgreSQL..."

# --- Настройка postgresql.conf ---
# Разрешаем PostgreSQL слушать на всех сетевых интерфейсах (не только localhost)
log_info "Настройка listen_addresses в postgresql.conf..."

# Заменяем строку с закомментированным listen_addresses
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" ${PG_CONF_DIR}/postgresql.conf

# На случай если строка уже была без комментария
sed -i "s/^listen_addresses = 'localhost'/listen_addresses = '*'/" ${PG_CONF_DIR}/postgresql.conf

# Проверяем что изменение применилось
if grep -q "listen_addresses = '\*'" ${PG_CONF_DIR}/postgresql.conf; then
    log_info "listen_addresses успешно настроен на '*'"
else
    # Если строка не найдена - добавляем явно
    echo "listen_addresses = '*'" >> ${PG_CONF_DIR}/postgresql.conf
    log_info "listen_addresses добавлен в конец postgresql.conf"
fi

# --- Настройка pg_hba.conf ---
# Файл pg_hba.conf управляет аутентификацией клиентов
log_info "Настройка pg_hba.conf для разрешения удаленных подключений..."

# Добавляем правила в конец файла pg_hba.conf
cat >> ${PG_CONF_DIR}/pg_hba.conf << PGHBA_EOF

# ============================================================
# Удаленный доступ для тестирования через DBeaver и др. клиенты
# ВНИМАНИЕ: Разрешено для ВСЕХ хостов - ТОЛЬКО для тестового сервера!
# В продакшене замените 0.0.0.0/0 на конкретный IP или подсеть
# Например: host rehab_db rehab_user 192.168.1.0/24 scram-sha-256
# ============================================================

# Доступ к конкретной БД для конкретного пользователя с любого IP
host    ${DB_NAME}    ${DB_USER}    0.0.0.0/0    scram-sha-256

# Доступ для всех пользователей ко всем БД с любого IP (для удобства тестов)
# Метод scram-sha-256 - более безопасный чем md5 (используется в PostgreSQL 14+)
host    all           all           0.0.0.0/0    scram-sha-256

# Аналогичные правила для IPv6
host    ${DB_NAME}    ${DB_USER}    ::/0         scram-sha-256
host    all           all           ::/0         scram-sha-256
PGHBA_EOF

# Перезапуск PostgreSQL для применения всех изменений конфигурации
log_info "Перезапуск PostgreSQL для применения изменений..."
systemctl restart postgresql

# Проверка статуса PostgreSQL после перезапуска
if systemctl is-active --quiet postgresql; then
    log_info "PostgreSQL успешно перезапущен и работает"
else
    log_error "PostgreSQL не запустился! Проверьте конфигурацию."
    systemctl status postgresql
    exit 1
fi

# Проверка что PostgreSQL слушает на нужном порту
log_info "Проверка прослушиваемых портов PostgreSQL..."
ss -tlnp | grep 5432 || log_warn "PostgreSQL не слушает порт 5432!"

log_info "Удаленный доступ к PostgreSQL настроен"

# =============================================================================
# 9. УСТАНОВКА И НАСТРОЙКА CERTBOT (SSL/TLS сертификаты Let's Encrypt)
# =============================================================================
log_section "9. Установка Certbot для SSL сертификатов"

log_info "Установка Certbot через snap..."
snap install --classic certbot

# Создаём символическую ссылку для удобного вызова из командной строки
if [ ! -f /usr/bin/certbot ]; then
    ln -s /snap/bin/certbot /usr/bin/certbot
    log_info "Символическая ссылка certbot создана"
else
    log_info "Файл /usr/bin/certbot уже существует, пропускаем"
fi

# Проверяем установку certbot
if command -v certbot &> /dev/null; then
    log_info "Certbot успешно установлен: $(certbot --version)"
else
    log_error "Certbot не установлен! Проверьте установку."
    exit 1
fi

# Получаем внешний IP для информирования пользователя
CURRENT_IP=$(curl -s ifconfig.me 2>/dev/null \
    || curl -s api.ipify.org 2>/dev/null \
    || echo "unknown")
log_info "Текущий внешний IP сервера: ${CURRENT_IP}"

# --- Интерактивный запрос на получение SSL сертификата ---
log_warn "Лимиты Let's Encrypt: не более 5 одинаковых сертификатов за 168 часов!"
log_warn "Домен ${DOMAIN} должен указывать на IP ${CURRENT_IP}"
echo ""
echo -e "${YELLOW}Хотите получить SSL сертификат сейчас?${NC}"
echo -e "${YELLOW}Введите 'yes' только если:${NC}"
echo -e "${YELLOW}  - Домен ${DOMAIN} уже указывает на ${CURRENT_IP}${NC}"
echo -e "${YELLOW}  - Вы не превысили лимит запросов Let's Encrypt${NC}"
echo -e "${YELLOW}  - Порт 80 доступен извне${NC}"
echo ""
read -r -p "Получить SSL сертификат сейчас? [yes/NO]: " SSL_CONFIRM < /dev/tty
log_info "Введено значение: '${SSL_CONFIRM}'"  # можно убрать после отладки

if [[ "${SSL_CONFIRM}" == "yes" ]]; then
    log_info "Запрос SSL сертификата для домена ${DOMAIN}..."

    certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "${EMAIL}" \
        --redirect \
        -d "${DOMAIN}" \
        -d "www.${DOMAIN}" && SSL_SUCCESS=true || SSL_SUCCESS=false

    if [ "${SSL_SUCCESS}" = true ]; then
        log_info "SSL сертификат успешно получен!"
        log_info "Nginx перенастроен для работы по HTTPS"
        nginx -t && systemctl reload nginx
        log_info "Nginx перезагружен с SSL конфигурацией"
    else
        log_warn "Не удалось получить SSL сертификат."
        log_warn "Проверьте причину в логе: /var/log/letsencrypt/letsencrypt.log"
        log_warn "После устранения причины выполните вручную:"
        log_warn "  certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
    fi
else
    log_info "Получение SSL сертификата пропущено."
    log_info "Для получения сертификата выполните вручную:"
    log_info "  certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
fi

# Проверка автоматического обновления сертификата
log_info "Проверка автообновления сертификатов..."
if systemctl is-enabled snap.certbot.renew.timer &>/dev/null; then
    log_info "Таймер автообновления certbot активен (через snap)"
else
    (crontab -l 2>/dev/null; \
     echo "0 3 * * * /usr/bin/certbot renew --quiet \
     --post-hook 'systemctl reload nginx'") | crontab -
    log_info "Добавлена cron задача для автообновления сертификата"
fi

log_info "Certbot настроен"

# =============================================================================
# 10. НАСТРОЙКА ЛОГИРОВАНИЯ И РОТАЦИИ ЛОГОВ
# =============================================================================
log_section "10. Настройка ротации логов"

log_info "Настройка ротации логов для проекта..."

# Создаем конфигурацию logrotate для логов сайта
cat > /etc/logrotate.d/aicopilot-presentation << EOF
# Ротация логов Nginx для проекта aicopilot-presentation
${WWW_DIR}/logs/*.log {
    # Выполнять ежедневно
    daily
    # Хранить последние 30 файлов лога
    rotate 30
    # Сжимать старые логи с помощью gzip
    compress
    # Не сжимать самый последний архивный файл (для удобства чтения)
    delaycompress
    # Не выдавать ошибку если файл лога отсутствует
    missingok
    # Не ротировать если файл пустой
    notifempty
    # Создавать новый файл лога после ротации с правами www-data
    create 0640 www-data adm
    # Общий скрипт postrotate для всех файлов в блоке
    sharedscripts
    postrotate
        # Отправляем сигнал nginx для переоткрытия файлов логов
        [ -f /var/run/nginx.pid ] && kill -USR1 \$(cat /var/run/nginx.pid)
    endscript
}
EOF

# Ротация логов ClamAV
cat > /etc/logrotate.d/clamav-scan << EOF
# Ротация логов антивирусного сканирования ClamAV
/var/log/clamav/daily-scan.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

log_info "Ротация логов настроена"

# =============================================================================
# 11. ДОПОЛНИТЕЛЬНЫЕ НАСТРОЙКИ БЕЗОПАСНОСТИ СИСТЕМЫ
# =============================================================================
log_section "11. Дополнительные настройки безопасности"

# --- Генерация случайного пароля для пользователя deploy ---
generate_password() {
    # Генерируем 16-символьный пароль: буквы, цифры, спецсимволы
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 16
}

# --- Создание пользователя user ---
log_info "Создание системного пользователя user..."

if id "user" &>/dev/null; then
    log_warn "Пользователь user уже существует, обновляем пароль..."
    USER_PASSWORD=$(generate_password)
    echo "user:${USER_PASSWORD}" | chpasswd
    log_info "Пароль для пользователя user обновлён"
else
    USER_PASSWORD=$(generate_password)

    # --gecos ""          - пропускает интерактивные вопросы
    # --disabled-password - создаёт без пароля (зададим ниже через chpasswd)
    adduser --disabled-password --gecos "" user

    # Устанавливаем сгенерированный пароль
    echo "user:${USER_PASSWORD}" | chpasswd

    # Добавляем в группу sudo
    usermod -aG sudo user

    log_info "Пользователь user создан и добавлен в группу sudo"
fi

log_info "Сгенерированный пароль пользователя user: ${USER_PASSWORD}"

# --- Отключение лишних модулей Nginx ---
log_info "Настройка дополнительных параметров безопасности Nginx..."

# Создаем файл с глобальными настройками безопасности для Nginx
cat > /etc/nginx/conf.d/security.conf << 'EOF'
# Глобальные настройки безопасности Nginx
# Скрыть версию Nginx в заголовках ответов
server_tokens off;

# Ограничение на размер буфера для защиты от переполнения буфера
client_body_buffer_size 1K;
client_header_buffer_size 1k;
client_max_body_size 100M;
large_client_header_buffers 2 1k;

# Таймауты для защиты от медленных атак (Slowloris)
client_body_timeout 10;
client_header_timeout 10;
keepalive_timeout 5 5;
send_timeout 10;
EOF

# Проверяем конфигурацию nginx после изменений
nginx -t && systemctl reload nginx || log_warn "Не удалось перезагрузить Nginx после настроек безопасности"

# --- Настройки безопасности SSH ---
log_info "Настройка дополнительных параметров безопасности SSH..."

# Резервная копия оригинального конфига SSH
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d%H%M%S)

# Применяем дополнительные настройки безопасности SSH
# Используем файл в директории sshd_config.d чтобы не модифицировать основной файл
cat > /etc/ssh/sshd_config.d/99-security.conf << EOF
# Дополнительные настройки безопасности SSH
# Созданы скриптом настройки сервера $(date '+%Y-%m-%d')

# Максимальное время на аутентификацию (60 секунд)
LoginGraceTime 60

# Максимальное количество попыток аутентификации за сессию
MaxAuthTries 4

# Максимальное количество одновременных сессий на одно соединение
MaxSessions 10

# Отключить пустые пароли
PermitEmptyPasswords no

# Запретить root login по паролю (разрешить только по ключу)
# Изменить на 'no' после настройки SSH ключей
PermitRootLogin prohibit-password

# Разрешить вход пользователям из группы sudo (если нужно ограничить)
AllowGroups sudo

# Таймаут неактивного соединения: отключить через 30 минут неактивности
ClientAliveInterval 1800
ClientAliveCountMax 2

# Отключить X11 forwarding если не нужен
X11Forwarding no

# Запись всех действий при входе
LogLevel VERBOSE
EOF

# Проверка конфигурации SSH перед применением
if sshd -t -f /etc/ssh/sshd_config; then
    systemctl restart ssh
    log_info "SSH успешно перенастроен с дополнительными параметрами безопасности"
    log_warn "ВАЖНО: SSH доступ сохранен на порту ${SSH_PORT}"
else
    log_error "Ошибка в конфигурации SSH! Изменения не применены."
    log_warn "SSH конфигурация не изменена, доступ сохранен."
fi

# --- Настройки ядра системы (sysctl) ---
log_info "Настройка параметров ядра для безопасности..."

cat > /etc/sysctl.d/99-security.conf << 'EOF'
# Настройки безопасности ядра Linux
# Созданы скриптом настройки сервера

# Защита от IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Отключить принятие ICMP редиректов (защита от MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Отключить отправку ICMP редиректов
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Защита от SYN flood атак
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Игнорировать ping broadcast запросы
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Игнорировать ошибочные ICMP ответы
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Логирование подозрительных пакетов
net.ipv4.conf.all.log_martians = 1

# Отключить IP forwarding (сервер не является маршрутизатором)
net.ipv4.ip_forward = 0
EOF

# Применяем настройки ядра без перезагрузки
sysctl -p /etc/sysctl.d/99-security.conf
log_info "Параметры ядра применены"

# =============================================================================
# 12. НАСТРОЙКА АВТОМАТИЧЕСКИХ ОБНОВЛЕНИЙ БЕЗОПАСНОСТИ
# =============================================================================
log_section "12. Настройка автоматических обновлений безопасности"

log_info "Установка unattended-upgrades..."
apt-get install -y unattended-upgrades apt-listchanges

# Настройка автоматических обновлений безопасности
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
// Конфигурация автоматических обновлений безопасности
Unattended-Upgrade::Allowed-Origins {
    // Только обновления безопасности Ubuntu
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Удалять неиспользуемые зависимости автоматически
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Автоматически перезагружать сервер если обновления этого требуют
// Перезагрузка будет произведена в 3:30 ночи
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";

// Отправлять email отчеты об ошибках
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
EOF

# Включаем автоматические обновления
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
// Периодичность автоматических действий apt (в днях)
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades
log_info "Автоматические обновления безопасности настроены"

# =============================================================================
# 13. ФИНАЛЬНАЯ ПРОВЕРКА ВСЕХ СЕРВИСОВ
# =============================================================================
log_section "13. Финальная проверка сервисов"
log_info "Проверка статуса всех сервисов..."

check_service() {
    local service_name=$1
    local display_name=$2
    if systemctl is-active --quiet "${service_name}"; then
        log_info "✓ ${display_name} - работает"
    else
        log_warn "✗ ${display_name} - НЕ работает!"
        systemctl status "${service_name}" --no-pager -l 2>/dev/null | tail -5 || true
    fi
}

check_service "nginx"               "Nginx"
check_service "postgresql"          "PostgreSQL"
check_service "ufw"                 "UFW Фаервол"
check_service "fail2ban"            "Fail2Ban"
check_service "clamav-daemon"       "ClamAV Daemon"
check_service "clamav-freshclam"    "ClamAV FreshClam"
check_service "ssh"                 "SSH"
check_service "unattended-upgrades" "Auto Updates"

# ИСПРАВЛЕНО — set +e вынесен перед всеми потенциально падающими командами
set +e

log_info "Открытые порты:"
ss -tlnp | grep -E ':22|:80|:443|:5432' || log_warn "Порты не найдены через ss"

log_info "Правила фаервола:"
ufw status numbered

log_info "Проверка подключения к PostgreSQL..."
if sudo -u postgres psql -tAc "SELECT version();" &>/dev/null; then
    log_info "✓ Подключение к PostgreSQL работает"
    sudo -u postgres psql -tAc "\l" 2>/dev/null | grep -E "${DB_NAME}|Name" || true
else
    log_warn "✗ Не удалось подключиться к PostgreSQL"
fi

set -e
# =============================================================================
# 14. ВЫВОД ИТОГОВОЙ ИНФОРМАЦИИ
# =============================================================================
log_section "Настройка сервера завершена!"

# Получаем текущий IP для отображения в итоге
CURRENT_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s api.ipify.org 2>/dev/null || echo "N/A")

echo -e "${GREEN}"

printf '╔══════════════════════════════════════════════════════════════╗\n'
printf '║          ИТОГОВАЯ ИНФОРМАЦИЯ О СЕРВЕРЕ                       ║\n'
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  %-20s %-39s ║\n' "IP сервера:"   "${CURRENT_IP}"
printf '║  %-20s %-39s ║\n' "Домен:"        "${DOMAIN}"
printf '║  %-20s %-39s ║\n' "Директория:"   "${WWW_DIR}"
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  БАЗА ДАННЫХ                                                 ║\n'
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  %-20s %-39s ║\n' "Хост:"         "${CURRENT_IP}"
printf '║  %-20s %-39s ║\n' "Порт:"         "5432"
printf '║  %-20s %-39s ║\n' "База данных:"  "${DB_NAME}"
printf '║  %-20s %-39s ║\n' "Пользователь:" "${DB_USER}"
printf '║  %-20s %-39s ║\n' "Пароль:"       "${DB_PASS}"
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  СИСТЕМНЫЙ ПОЛЬЗОВАТЕЛЬ                                      ║\n'
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  %-20s %-39s ║\n' "Пользователь:" "user"
printf '║  %-20s %-39s ║\n' "Пароль:"       "${USER_PASSWORD}"
printf '║  %-20s %-39s ║\n' "Группы:"       "sudo"
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  СЕРВИСЫ                                                     ║\n'
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  %-20s %-39s ║\n' "Nginx:"        "активен"
printf '║  %-20s %-39s ║\n' "PostgreSQL:"   "активен (удалённый доступ открыт)"
printf '║  %-20s %-39s ║\n' "UFW Фаервол:"  "активен"
printf '║  %-20s %-39s ║\n' "Fail2Ban:"     "активен"
printf '║  %-20s %-39s ║\n' "ClamAV:"       "активен"
printf '║  %-20s %-39s ║\n' "Certbot:"      "установлен"
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  ОТКРЫТЫЕ ПОРТЫ                                              ║\n'
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  %-20s %-39s ║\n' "22"            "SSH"
printf '║  %-20s %-39s ║\n' "80"            "HTTP"
printf '║  %-20s %-39s ║\n' "443"           "HTTPS"
printf '║  %-20s %-39s ║\n' "5432"          "PostgreSQL"
printf '╚══════════════════════════════════════════════════════════════╝\n'

echo -e "${NC}"

log_warn "ВАЖНЫЕ НАПОМИНАНИЯ:"
log_warn "1. Смените пароль БД: ALTER USER ${DB_USER} WITH PASSWORD 'новый_пароль';"
log_warn "2. После настройки DNS получите SSL: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
log_warn "3. Настройте SSH ключи и отключите вход по паролю для большей безопасности"
log_warn "4. Закройте порт 5432 в фаерволе когда закончите тестирование:"
log_warn "   ufw delete allow 5432/tcp"
log_warn "5. Для подключения DBeaver используйте:"
log_warn "   Хост: ${CURRENT_IP}  Порт: 5432  БД: ${DB_NAME}"
log_warn "6. Сохраните пароль пользователя user: ${USER_PASSWORD}"

log_info "Файлы конфигурации:"
log_info "  Nginx:       ${NGINX_CONF}"
log_info "  PostgreSQL:  ${PG_CONF_DIR}/postgresql.conf"
log_info "  pg_hba:      ${PG_CONF_DIR}/pg_hba.conf"
log_info "  Fail2Ban:    /etc/fail2ban/jail.local"
log_info "  SSH:         /etc/ssh/sshd_config.d/99-security.conf"
log_info "  Логи сайта:  ${WWW_DIR}/logs/"
log_info "  Логи ClamAV: /var/log/clamav/daily-scan.log"

log_section "Настройка завершена успешно!"


