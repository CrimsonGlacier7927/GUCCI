# GUCCI (s-ui edition) — s-ui + nginx reverse proxy روی Railway
FROM ghcr.io/alireza0/s-ui:v1.5.4

USER root

RUN apk add --no-cache \
    nginx \
    sqlite \
    openssl \
    curl \
    tzdata \
    && ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Railway پورت رو از طریق متغیر $PORT تزریق می‌کند؛ nginx روی پورت 1 گوش می‌دهد
CMD ["/start.sh"]
