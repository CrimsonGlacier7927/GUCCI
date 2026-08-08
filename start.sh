#!/bin/bash
set -e

# =====================================================================
#  GUCCI (s-ui edition) — s-ui + nginx reverse proxy روی Railway
#
#  متغیرهای محیطی قابل تنظیم (در Railway → Service → Variables):
#    INBOUND_COUNT     تعداد اینباندهای اضافه /in1..inN   (پیش‌فرض: 50)
#    INBOUND_BASE_PORT پورت پایه اینباندهای اضافه          (پیش‌فرض: 8080)
#    TCP_INBOUND_PORT  پورت اینباند TCP خام (اختیاری - پیش‌فرض: 9090)
#    HOST_ROUTES       مسیریابی دامنه اختصاصی (اختیاری)
#                      مثال: "sub1.example.com:8081,sub2.example.com:8082"
# =====================================================================

INBOUND_COUNT="${INBOUND_COUNT:-50}"
INBOUND_BASE_PORT="${INBOUND_BASE_PORT:-8080}"
TCP_INBOUND_PORT="${TCP_INBOUND_PORT:-9090}"
HOST_ROUTES="${HOST_ROUTES:-}"

echo "🚀 Starting s-ui + nginx reverse proxy (GUCCI s-ui edition)..."
echo "   inbound paths  : /in1..in$INBOUND_COUNT -> ports $((INBOUND_BASE_PORT+1))..$((INBOUND_BASE_PORT+INBOUND_COUNT))"
echo "   raw TCP inbound: port $TCP_INBOUND_PORT (optional; design default = domain:443 only, no TCP Proxy)"
[ -n "$HOST_ROUTES" ] && echo "   host routes    : $HOST_ROUTES"

cd /app

# مایگریشن دیتابیس (مثل entrypoint رسمی)
if [ -f /app/db/s-ui.db ]; then
    echo "🔧 Migrating existing s-ui DB..."
    ./sui migrate || true
else
    # ساخت دیتابیس تازه با مقادیر پیش‌فرض تا تنظیمات ساب همین الان اعمال شوند
    echo "🔧 First run: creating fresh s-ui DB..."
    ./sui setting -show >/dev/null 2>&1 || true
fi

# مسیر وب پنل: فقط /gucci/ (مثل نسخه قبلی پروژه)
echo "🔧 Setting panel web path to /gucci/ ..."
./sui setting -path /gucci/ || true

# ---------------------------------------------------------------------
# گواهی خودامضا برای سرویس ساب:
# با ست شدن subCertFile/subKeyFile، سابسکریپشن روی 127.0.0.1:443 بالا می‌آید و
# لینک‌های ساب به‌صورت https://{دامنه‌ی درخواست}/sub/ (بدون پورت) ساخته می‌شوند.
# سرور ساب auto-https است و کانکشن HTTP ساده از nginx را هم می‌پذیرد.
# ---------------------------------------------------------------------
mkdir -p /app/cert
if [ ! -f /app/cert/sub-cert.pem ] || [ ! -f /app/cert/sub-key.pem ]; then
    echo "🔧 Generating self-signed cert for sub service..."
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout /app/cert/sub-key.pem -out /app/cert/sub-cert.pem \
        -subj "/CN=localhost" 2>/dev/null \
        && echo "  ✔ cert generated" || echo "  ⚠️ cert generation failed"
fi

DB=/app/db/s-ui.db

# تنظیم امن یک کلید در جدول settings (UPDATE + INSERT در صورت نبود ردیف)
set_sub_setting() {
    local key="$1" value="$2"
    sqlite3 "$DB" "UPDATE settings SET value='$value' WHERE key='$key';
INSERT INTO settings (key, value) SELECT '$key','$value' WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='$key');"
    echo "  ✔ sub setting [$key] = $(sqlite3 "$DB" "SELECT value FROM settings WHERE key='$key' LIMIT 1;")"
}

if [ -f "$DB" ]; then
    echo "🔧 Configuring subscription service (internal 127.0.0.1:443, dynamic https links)..."
    set_sub_setting subListen   127.0.0.1
    set_sub_setting subPort     443
    set_sub_setting subPath     /sub/
    set_sub_setting subCertFile /app/cert/sub-cert.pem
    set_sub_setting subKeyFile  /app/cert/sub-key.pem
    # خالی می‌گذاریم تا لینک ساب داینامیک با همان دامنه‌ای که پنل باز شده ساخته شود
    set_sub_setting subURI      ""
else
    echo "⚠️  DB not found at $DB (s-ui will create it on first run) - sub settings will apply on next boot"
fi

# ---------------------------------------------------------------------
# 🧼 پاکسازی flow=xtls-rprx-vision از کانفیگ‌ها:
# Vision روی WebSocket باعث کرش sing-box می‌شود (باگ بالادستی).
# لینک‌ها و کانفیگ‌های ذخیره‌شده بدون vision بازتولید می‌شوند تا پنل پایدار بماند.
# ---------------------------------------------------------------------
if [ -f "$DB" ] && sqlite3 "$DB" "SELECT count(*) FROM clients;" 2>/dev/null | grep -qE "[1-9]"; then
    echo "🧼 Sanitizing stored client configs (removing xtls-rprx-vision)..."
    sqlite3 "$DB" "UPDATE clients SET links = replace(links, '&flow=xtls-rprx-vision', '') WHERE links LIKE '%xtls-rprx-vision%';"
    sqlite3 "$DB" "UPDATE clients SET links = replace(links, '%26flow%3Dxtls-rprx-vision', '') WHERE links LIKE '%xtls-rprx-vision%';"
    sqlite3 "$DB" "UPDATE clients SET config = replace(config, '\"flow\":\"xtls-rprx-vision\"', '\"flow\":\"\"') WHERE config LIKE '%xtls-rprx-vision%';"
    echo "  ✔ vision removed from stored clients (re-import links in your client app)"
fi

# ---------------------------------------------------------------------
# تولید کانفیگ nginx (داینامیک)
# ---------------------------------------------------------------------
GEN_DIR=$(mktemp -d)

# ۱) لوکیشن‌های اینباند اضافه:  /in{i} -> پورت (BASE+i)
gen_inbound_locations() {
    local i port
    for i in $(seq 1 "$INBOUND_COUNT"); do
        port=$((INBOUND_BASE_PORT + i))
        cat <<EOF
        # اینباند $i -> پورت داخلی $port
        location /in$i {
            proxy_pass http://127.0.0.1:$port;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$real_scheme;
        }

EOF
    done
}

# ۲) سرورهای دامنه اختصاصی: هر دامنه -> پورت اینباند خودش (ClawCloud-style)
gen_host_route_servers() {
    [ -z "$HOST_ROUTES" ] && return 0
    local r host port
    IFS=',' read -ra ROUTES <<< "$HOST_ROUTES"
    for r in "${ROUTES[@]}"; do
        r="${r// /}"
        [ -z "$r" ] && continue
        host="${r%%:*}"
        port="${r##*:}"
        case "$port" in (*[!0-9]*|'') echo "  ⚠️  HOST_ROUTES entry '$r' invalid, skipped" >&2; continue;; esac
        cat <<EOF
    # دامنه اختصاصی $host -> پورت داخلی $port
    server {
        listen 1;
        server_name $host;
        absolute_redirect off;

        location / {
            proxy_pass http://127.0.0.1:$port;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$real_scheme;
        }
    }

EOF
        echo "  ✔ host route: $host -> 127.0.0.1:$port" >&2
    done
}

echo "🔧 Generating nginx config ($INBOUND_COUNT inbound paths + host routes)..."
gen_inbound_locations  > "$GEN_DIR/inbounds.conf"
gen_host_route_servers > "$GEN_DIR/hostroutes.conf"

awk -v inc="$GEN_DIR/inbounds.conf" -v hst="$GEN_DIR/hostroutes.conf" '
    /__INBOUND_LOCATIONS__/   { while ((getline line < inc) > 0) print line; close(inc); next }
    /__HOST_ROUTE_SERVERS__/  { while ((getline line < hst) > 0) print line; close(hst); next }
    { print }
' /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

rm -rf "$GEN_DIR"

echo "▶️  Starting s-ui in background..."
./sui &
S_UI_PID=$!

sleep 4

echo "▶️  Pre-flight checks..."
curl -s -o /dev/null -w "  panel (s-ui)     http://127.0.0.1:2095/gucci/ -> HTTP %{http_code}\n" http://127.0.0.1:2095/gucci/ || echo "  panel not ready yet"
curl -s -k -o /dev/null -w "  sub server       https://127.0.0.1:443/sub/x -> HTTP %{http_code}\n" "https://127.0.0.1:443/sub/x" || echo "  sub server not ready yet"
echo "  raw TCP inbound  : optional port $TCP_INBOUND_PORT (default design: domain:443 only, no TCP Proxy)"

echo "▶️  Starting nginx in foreground on port 1..."
nginx -t
exec nginx -g "daemon off;"
