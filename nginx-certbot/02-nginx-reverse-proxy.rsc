############################################################
# 02-nginx-reverse-proxy.rsc - Nginx Reverse Proxy Configuration
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
# REQUIRES: 01-container-nginx-certbot.rsc must be applied first!
#
# Создает конфигурацию nginx reverse proxy
# Интегрировано с централизованной конфигурацией
############################################################

############################################################
# CONFIGURATION
############################################################

# Domain from secrets
:local DOMAIN $secLetsEncryptDomain

# Service 1 (example: Grafana)
:local SERVICE1_SUBDOMAIN "grafana"
:local SERVICE1_IP "192.168.1.10"
:local SERVICE1_PORT "3000"

# Service 2 (example: Portainer)
:local SERVICE2_SUBDOMAIN "portainer"
:local SERVICE2_IP "192.168.1.20"
:local SERVICE2_PORT "9000"

# Service 3 (example: Home Assistant)
:local SERVICE3_SUBDOMAIN "home"
:local SERVICE3_IP "192.168.1.30"
:local SERVICE3_PORT "8123"

# Nginx container name
:local NGINX_CONTAINER "nginx"

############################################################
# Nginx configuration
############################################################

:local nginxConfig "
# HTTP redirect to HTTPS
server {
    listen 80;
    server_name $SERVICE1_SUBDOMAIN.$DOMAIN $SERVICE2_SUBDOMAIN.$DOMAIN $SERVICE3_SUBDOMAIN.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

# Service 1: $SERVICE1_SUBDOMAIN.$DOMAIN
server {
    listen 443 ssl http2;
    server_name $SERVICE1_SUBDOMAIN.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL security headers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
    add_header X-Frame-Options \"SAMEORIGIN\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;

    location / {
        proxy_pass http://$SERVICE1_IP:$SERVICE1_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }
}

# Service 2: $SERVICE2_SUBDOMAIN.$DOMAIN
server {
    listen 443 ssl http2;
    server_name $SERVICE2_SUBDOMAIN.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
    add_header X-Frame-Options \"SAMEORIGIN\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;

    location / {
        proxy_pass http://$SERVICE2_IP:$SERVICE2_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }
}

# Service 3: $SERVICE3_SUBDOMAIN.$DOMAIN
server {
    listen 443 ssl http2;
    server_name $SERVICE3_SUBDOMAIN.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
    add_header X-Frame-Options \"SAMEORIGIN\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;

    location / {
        proxy_pass http://$SERVICE3_IP:$SERVICE3_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }
}
"

############################################################
# Создание конфигурационного файла
############################################################

/file
set nginx-conf/default.conf contents=$nginxConfig

:log info "Nginx reverse proxy configuration created"

############################################################
# Копирование конфига в контейнер и reload
############################################################

:log info "Копирование конфига в nginx контейнер..."

# Тест конфигурации и перезапуск nginx
:delay 2s
/container/exec number=[/container/get $NGINX_CONTAINER number] cmd="nginx -t"
:delay 1s
/container/exec number=[/container/get $NGINX_CONTAINER number] cmd="nginx -s reload"

:log info "Nginx configuration applied and reloaded"
:log info "Module nginx-certbot/02-nginx-reverse-proxy.rsc applied successfully"
:log info "Domain: $DOMAIN"
:log info "Services: $SERVICE1_SUBDOMAIN, $SERVICE2_SUBDOMAIN, $SERVICE3_SUBDOMAIN"
