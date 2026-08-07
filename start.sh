#!/bin/bash
set -e

# =====================================================================
#  GUCCI v2 — 3x-ui + nginx reverse proxy روی Railway
#
#  متغیرهای محیطی قابل تنظیم (در Railway → Service → Variables):
#    INBOUND_COUNT     تعداد اینباندهای اضافه /in1..inN   (پیش‌فرض: 50)
#    INBOUND_BASE_PORT پورت پایه اینباندهای اضافه          (پیش‌فرض: 8080)
#    TCP_INBOUND_PORT  پورت اینباند TCP خام برای TCP Proxy (پیش‌فرض: 9090)
#    HOST_ROUTES       مسیریابی دامنه اختصاصی (اختیاری)
#                      مثال: "sub1.example.com:8081,sub2.example.com:8082"
# =====================================================================

INBOUND_COUNT="${INBOUND_COUNT:-50}"
INBOUND_BASE_PORT="${INBOUND_BASE_PORT:-8080}"
TCP_INBOUND_PORT="${TCP_INBOUND_PORT:-9090}"
HOST_ROUTES="${HOST_ROUTES:-}"

echo "🚀 Starting X-UI + nginx reverse proxy (GUCCI v2)..."
echo "   inbound paths  : /in1..in$INBOUND_COUNT -> ports $((INBOUND_BASE_PORT+1))..$((INBOUND_BASE_PORT+INBOUND_COUNT))"
echo "   raw TCP inbound: port $TCP_INBOUND_PORT (Railway TCP Proxy target)"
[ -n "$HOST_ROUTES" ] && echo "   host routes    : $HOST_ROUTES"

cd /usr/local/x-ui

echo "🔧 Applying panel settings via x-ui CLI (panel internal port = 2053, base path = /gucci/)..."
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
    echo "🔧 Configuring subscription service (internal 127.0.0.1:443, HTTP)..."
    set_sub_setting subEnable     true
    set_sub_setting subJsonEnable false
    set_sub_setting subListen     127.0.0.1
    set_sub_setting subPort       443
    set_sub_setting subPath       /sub/
    set_sub_setting subJsonPath   /json/
    set_sub_setting subClashPath  /clash/

    # مسیرهای cert به‌صورت «نشانگر TLS» ست می‌شوند تا 3x-ui لینک‌ها را با https:// و
    # بدون پورت بسازد:  https://{دامنه‌ی پنل}/sub/...
    # (فایل‌ها وجود ندارند؛ سرویس ساب خودش به HTTP روی 127.0.0.1:443 برمی‌گردد)
    set_sub_setting subCertFile   /etc/x-ui/sub-dummy-cert.pem
    set_sub_setting subKeyFile    /etc/x-ui/sub-dummy-key.pem

    # سه لینک ساب را خالی می‌گذاریم تا 3x-ui آن‌ها را به‌صورت داینامیک با همان دامنه‌ای که
    # پنل با آن باز شده بسازد — برای هر دامنه‌ای کار می‌کند
    set_sub_setting subURI        ""
    set_sub_setting subJsonURI    ""
    set_sub_setting subClashURI   ""
else
    echo "⚠️  DB not found at $DB (x-ui will create it) - skipping sub settings"
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

echo "▶️  Starting x-ui in background..."
./x-ui &
X_UI_PID=$!

sleep 3

echo "▶️  Pre-flight checks..."
curl -s -o /dev/null -w "  panel (x-ui)     http://127.0.0.1:2053/gucci/ -> HTTP %{http_code}\n" http://127.0.0.1:2053/gucci/ || echo "  panel not ready yet"
curl -s -o /dev/null -w "  sub server       http://127.0.0.1:443/sub/x  -> HTTP %{http_code}\n" "http://127.0.0.1:443/sub/x" || echo "  sub server not ready yet"
echo "  raw TCP inbound  : create it in the panel on port $TCP_INBOUND_PORT (TCP Proxy target)"

echo "▶️  Starting nginx in foreground on port 1..."
nginx -t
exec nginx -g "daemon off;"
