#!/bin/bash
set -e

echo "🚀 Starting X-UI + nginx reverse proxy (nginx owns port 1, panel on 2053)..."

# nginx همیشه روی پورت ثابت 3000 گوش می‌دهد
export NGINX_PORT=3000

cd /usr/local/x-ui

echo "🔧 Applying panel settings via x-ui CLI (panel port = 1, base path = /gucci/)..."
./x-ui setting -port 2053 -webBasePath /gucci/ || true

DB=/etc/x-ui/x-ui.db

# تنظیم امن یک کلید در جدول settings:
# در دیتابیس تازه این جدول خالی است (UPDATE به تنهایی هیچ ردیفی را تغییر نمی‌دهد)،
# پس اول UPDATE و در صورت نبود ردیف INSERT می‌کنیم.
set_sub_setting() {
    local key="$1" value="$2"
    sqlite3 "$DB" "UPDATE settings SET value='$value' WHERE key='$key';
INSERT INTO settings (key, value) SELECT '$key','$value' WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='$key');"
    echo "  ✔ sub setting [$key] = $(sqlite3 "$DB" "SELECT value FROM settings WHERE key='$key' LIMIT 1;")"
}

if [ -f "$DB" ]; then
    echo "🔧 Configuring subscription service (internal: 127.0.0.1:443, HTTP)..."
    set_sub_setting subEnable     true
    set_sub_setting subJsonEnable true
    set_sub_setting subListen     127.0.0.1
    set_sub_setting subPort       443
    set_sub_setting subPath       /sub/
    set_sub_setting subJsonPath   /json/
    set_sub_setting subClashPath  /clash/

    # مسیرهای cert به‌صورت «نشانگر TLS» ست می‌شوند تا 3x-ui لینک‌ها را با https:// بسازد.
    # (فایل‌ها وجود ندارند؛ سرویس ساب خودش به HTTP روی 127.0.0.1:443 برمی‌گردد)
    set_sub_setting subCertFile   /etc/x-ui/sub-dummy-cert.pem
    set_sub_setting subKeyFile    /etc/x-ui/sub-dummy-key.pem

    # سه لینک ساب را خالی می‌گذاریم تا 3x-ui آن‌ها را به‌صورت داینامیک با همان دامنه‌ای که
    # پنل با آن باز شده بسازد:  https://{دامنه‌ی پنل}/sub/...  (برای هر دامنه‌ای کار می‌کند)
    set_sub_setting subURI        ""
    set_sub_setting subJsonURI    ""
    set_sub_setting subClashURI   ""
else
    echo "⚠️  DB not found at $DB (x-ui will create it) - skipping sub settings"
fi

echo "🔧 Building nginx.conf for port $NGINX_PORT (+ sub port 2096)..."
envsubst '${NGINX_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "▶️  Starting x-ui in background..."
./x-ui &
X_UI_PID=$!

sleep 3

echo "▶️  Pre-flight checks..."
curl -s -o /dev/null -w "  panel direct  http://127.0.0.1:2053/gucci/ -> HTTP %{http_code}\n" http://127.0.0.1:2053/gucci/ || echo "  panel not ready yet (nginx will retry)"
curl -s -o /dev/null -w "  sub server   http://127.0.0.1:443/sub/x -> HTTP %{http_code}\n" "http://127.0.0.1:443/sub/x" || echo "  sub server not ready yet (nginx will retry)"

echo "▶️  Starting nginx in foreground on port $NGINX_PORT (+ sub port 2096)..."
nginx -t
exec nginx -g "daemon off;"
