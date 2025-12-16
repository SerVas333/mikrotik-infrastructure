############################################################
# 01-container-nginx-certbot.rsc - Nginx & Certbot Containers
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
# REQUIRES: 08-containers.rsc must be applied first!
#
# Sets up:
#   - Nginx container (pinned version)
#   - Certbot container (pinned version)
#   - Cloudflare DNS challenge
#   - Resource limits
#   - Интеграция с bridge-containers
#
# ВАЖНО:
#   - Credentials хранятся в 00-secrets.rsc
#   - Интегрировано с firewall_complete.rsc
#   - NAT правила уже есть в 08-containers.rsc
############################################################

############################################################
# CONTAINER CONFIGURATION
############################################################

:local NGINX_CONTAINER "nginx"
:local CERTBOT_CONTAINER "certbot"
:local CONTAINER_BRIDGE $cfgBridgeContainers
:local NGINX_IP $cfgContainerNginxIP
:local CERTBOT_IP $cfgContainerCertbotIP
:local CONTAINER_GATEWAY [:pick $cfgContainerGateway 0 [:find $cfgContainerGateway "/"]]

# Let's Encrypt domain and email from secrets
:local DOMAIN $secLetsEncryptDomain
:local CF_EMAIL $secLetsEncryptEmail

# Pinned versions (НЕ используем :latest)
:local NGINX_VERSION $cfgDockerNginxImage
:local CERTBOT_VERSION $cfgDockerCertbotImage

# Resource limits
:local NGINX_MEMORY "150M"
:local CERTBOT_MEMORY "100M"

############################################################
# Mount points для persistent storage (на внешнем диске)
############################################################

# Используем пути из 00-config.rsc
:local DATA_ROOT $cfgContainerDataRoot

# Создаём каталоги на внешнем диске
/file
make-directory ($DATA_ROOT . "/nginx-conf")
make-directory ($DATA_ROOT . "/nginx-html")
make-directory ($DATA_ROOT . "/certbot-data")

:log info "Created mount directories on external storage: $DATA_ROOT"

############################################################
# Container registry configuration
############################################################

/container/config
set registry-url=https://registry-1.docker.io \
    tmpdir=$cfgContainerTmpDir

############################################################
# Nginx container
############################################################

# Создаём mount points с полными путями
/container/mounts
:if ([:len [find name=nginx-conf]] = 0) do={
    add name=nginx-conf src=($DATA_ROOT . "/nginx-conf") dst="/etc/nginx"
}
:if ([:len [find name=nginx-html]] = 0) do={
    add name=nginx-html src=($DATA_ROOT . "/nginx-html") dst="/usr/share/nginx/html"
}
:if ([:len [find name=certbot-certs]] = 0) do={
    add name=certbot-certs src=($DATA_ROOT . "/certbot-data") dst="/etc/letsencrypt"
}

/container
:if ([:len [find name=$NGINX_CONTAINER]] = 0) do={
    add remote-image=$NGINX_VERSION \
        interface=$CONTAINER_BRIDGE \
        envlist="" \
        root-dir=($cfgContainerImagesRoot . "/nginx") \
        mounts=nginx-conf,nginx-html,certbot-certs \
        dns=$CONTAINER_GATEWAY \
        hostname=$NGINX_CONTAINER \
        logging=yes \
        comment="Nginx reverse proxy (pinned version)" \
        name=$NGINX_CONTAINER
}

# Resource limits
/container
set $NGINX_CONTAINER memory-high=$NGINX_MEMORY

:log info "Nginx container configured with resource limits"

############################################################
# Certbot container
############################################################

# Создаём mount point для Certbot (работа с теми же сертификатами)
/container/mounts
:if ([:len [find name=certbot-work]] = 0) do={
    add name=certbot-work src=($DATA_ROOT . "/certbot-data") dst="/etc/letsencrypt"
}
:if ([:len [find name=certbot-config]] = 0) do={
    add name=certbot-config src=($DATA_ROOT . "/certbot-data") dst="/certbot-data"
}

/container
:if ([:len [find name=$CERTBOT_CONTAINER]] = 0) do={
    add remote-image=$CERTBOT_VERSION \
        interface=$CONTAINER_BRIDGE \
        envlist="" \
        root-dir=($cfgContainerImagesRoot . "/certbot") \
        mounts=certbot-work,certbot-config \
        dns=$CONTAINER_GATEWAY \
        hostname=$CERTBOT_CONTAINER \
        logging=yes \
        comment="Certbot with Cloudflare DNS (pinned version)" \
        name=$CERTBOT_CONTAINER
}

# Resource limits
/container
set $CERTBOT_CONTAINER memory-high=$CERTBOT_MEMORY

:log info "Certbot container configured with resource limits"

############################################################
# Cloudflare credentials file
############################################################

# ВАЖНО: Создайте файл вручную!
# После применения этого скрипта выполните:
#
# /file/edit ($DATA_ROOT . "/certbot-data/cloudflare.ini")
#
# Пример полного пути (зависит от cfgContainerDataRoot в 00-config.rsc):
# /file/edit /disk1/data/certbot-data/cloudflare.ini   # если cfgContainerDataRoot="/disk1/data"
# /file/edit /usb1/data/certbot-data/cloudflare.ini    # если cfgContainerDataRoot="/usb1/data"
#
# И добавьте:
# dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN_HERE
#
# Затем установите права:
# /file/set ($DATA_ROOT . "/certbot-data/cloudflare.ini") permissions=owner-read,owner-write

:log warning ("ВАЖНО: Создайте " . $DATA_ROOT . "/certbot-data/cloudflare.ini вручную с вашим Cloudflare API token!")
:log info ("Путь для cloudflare.ini: " . $DATA_ROOT . "/certbot-data/cloudflare.ini")

############################################################
# Automatic certificate renewal script
############################################################

/system script
:if ([:len [find name=renew-letsencrypt]] = 0) do={
    add name=renew-letsencrypt \
        policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive \
        source="
# Renew certificates using certbot
:log info \"Starting Let's Encrypt certificate renewal\"

:local certbotCmd \"certbot certonly --dns-cloudflare --dns-cloudflare-credentials /certbot-data/cloudflare.ini -d $DOMAIN --agree-tos -m $CF_EMAIL --non-interactive --keep-until-expiring\"

/container/exec number=[/container/get $CERTBOT_CONTAINER number] cmd=\$certbotCmd

# Reload nginx to apply new certificates
:delay 5s
/container/exec number=[/container/get $NGINX_CONTAINER number] cmd=\"nginx -s reload\"

:log info \"Certificate renewal completed\"
" \
        comment="Automatic Let's Encrypt certificate renewal"
}

:log info "Certificate renewal script created"

############################################################
# Scheduler для automatic renewal
############################################################

/system scheduler
:if ([:len [find name="letsencrypt-renew"]] = 0) do={
    add name="letsencrypt-renew" \
        interval=1d \
        start-time=03:00:00 \
        on-event=renew-letsencrypt \
        comment="Daily certificate check and renewal"
}

:log info "Certificate renewal scheduler configured (runs daily at 03:00)"

############################################################
# Container start
############################################################

/container start $NGINX_CONTAINER
/container start $CERTBOT_CONTAINER

:log info "Nginx and Certbot containers started"
:log info "Module nginx-certbot/01-container-nginx-certbot.rsc applied successfully"
:log info "Domain: $DOMAIN | Email: $CF_EMAIL"
:log info "Nginx IP: $NGINX_IP | Certbot IP: $CERTBOT_IP"
