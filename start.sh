#!/bin/bash
set -e

echo "🚀 Starting X-UI + nginx reverse proxy (panel on port 1)..."

# nginx همیشه روی پورت ثابت 3000 گوش می‌دهد
export NGINX_PORT=3000

cd /usr/local/x-ui

# ===== پنل روی پورت 1 و مسیر /gucci/ =====
echo "🔧 Applying panel settings via x-ui CLI (panel port = 1, base path = /gucci/)..."
./x-ui setting -port 1 -webBasePath /gucci/ || true

# ===== تنظیم سرویس سابسکریپشن =====
# سرویس ساب روی پورت داخلی 2097 و فقط روی loopback اجرا می‌شود تا با پورت عمومی 2096 (که nginx روی آن
# گوش می‌دهد) تداخل نداشته باشد. nginx مسیرهای /sub/ ، /json/ و /clash/ را هم روی پورت 443 و هم روی
# پورت 2096 به این سرویس وصل می‌کند؛ بنابراین لینک ساب برای تمامی نسخه‌های پنل یکسان و پایدار است.
if [ -f /etc/x-ui/x-ui.db ]; then
    echo "🔧 Configuring subscription service (internal port 2097)..."
    sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='true'       WHERE key='subEnable';"   2>/dev/null || true
    sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='127.0.0.1'  WHERE key='subListen';"   2>/dev/null || true
    sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='2097'       WHERE key='subPort';"     2>/dev/null || true
    sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/sub/'      WHERE key='subPath';"     2>/dev/null || true
    sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/json/'     WHERE key='subJsonPath';" 2>/dev/null || true
    sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='/clash/'    WHERE key='subClashPath';" 2>/dev/null || true

    # اگر دامنه عمومی Railway در دسترس باشد، لینک‌های ساب داخل پنل هم مستقیم و قابل‌استفاده می‌شوند
    DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-}"
    if [ -z "$DOMAIN" ]; then
        DOMAIN="${RAILWAY_TCP_PROXY_DOMAIN:-}"
    fi
    if [ -n "$DOMAIN" ]; then
        echo "🔧 Setting subscription base URL to https://${DOMAIN}/ ..."
        sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='https://${DOMAIN}/sub/'   WHERE key='subURI';"    2>/dev/null || true
        sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='https://${DOMAIN}/json/'  WHERE key='subJsonURI';" 2>/dev/null || true
        sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value='https://${DOMAIN}/clash/' WHERE key='subClashURI';" 2>/dev/null || true
    fi
fi

echo "🔧 Building nginx.conf for port $NGINX_PORT (+ sub port 2096)..."
envsubst '${NGINX_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "▶️  Starting x-ui in background..."
./x-ui &
X_UI_PID=$!

sleep 2

echo "▶️  Starting nginx in foreground on port $NGINX_PORT (+ sub port 2096)..."
nginx -t
exec nginx -g "daemon off;"
