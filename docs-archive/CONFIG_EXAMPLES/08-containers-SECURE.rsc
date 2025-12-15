# ===================================================================
# 08-containers-SECURE.rsc
# БЕЗОПАСНАЯ конфигурация контейнеров
# С изоляцией, rate limiting, resource limits
# ===================================================================

############################################################
# КОНФИГУРАЦИЯ ПЕРЕМЕННЫХ
############################################################

:local CONTAINER_BRIDGE "bridge-containers"
:local CONTAINER_NET "10.11.0.0/24"
:local CONTAINER_GW "10.11.0.1/24"
:local NGINX_IP "10.11.0.11"
:local XRAY_IP "10.11.0.10"

# Внутренние подсети для блокировки
:local LAN_MAIN "192.168.1.0/24"
:local MGMT_SUBNET "172.16.99.0/24"
:local LAN_GUEST "10.30.0.0/24"

############################################################

# === Container Security: Firewall Rules ===

# 1. DNS для контейнеров
/ip firewall filter
add chain=input src-address=$CONTAINER_NET protocol=udp dst-port=53 \
    action=accept comment="Containers: DNS UDP"
add chain=input src-address=$CONTAINER_NET protocol=tcp dst-port=53 \
    action=accept comment="Containers: DNS TCP"

# 2. NTP для контейнеров
add chain=input src-address=$CONTAINER_NET protocol=udp dst-port=123 \
    action=accept comment="Containers: NTP"

# 3. БЛОКИРОВАТЬ management порты
add chain=input src-address=$CONTAINER_NET protocol=tcp \
    dst-port=22,8291,80,443,8728,8729,21,23 \
    action=drop comment="Block containers -> router management"

# 4. БЛОКИРОВАТЬ всё остальное от контейнеров к роутеру
add chain=input src-address=$CONTAINER_NET \
    action=drop comment="Block containers -> router (default deny)"

# 5. Изоляция от внутренних сетей
add chain=forward src-address=$CONTAINER_NET dst-address=$LAN_MAIN \
    action=drop comment="Block containers -> LAN"
add chain=forward src-address=$CONTAINER_NET dst-address=$MGMT_SUBNET \
    action=drop comment="Block containers -> Management"
add chain=forward src-address=$CONTAINER_NET dst-address=$LAN_GUEST \
    action=drop comment="Block containers -> Guest"

# 6. Rate limiting для nginx
add chain=forward dst-address=$NGINX_IP protocol=tcp dst-port=80,443 \
    connection-state=new connection-limit=50,32 action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: connection limit per IP"

add chain=forward dst-address=$NGINX_IP protocol=tcp dst-port=80,443 \
    connection-state=new limit=20,5:packet action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: rate limit"

add chain=forward dst-address=$NGINX_IP protocol=tcp dst-port=80,443 \
    connection-state=new action=drop \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: drop flood"

# === Resource Limits ===
/container set xray memory-high=200M
/container set nginx memory-high=150M
/container set certbot memory-high=100M

# === Pinned Versions (не :latest) ===
/container set xray remote-image=teddysun/xray:1.8.4
/container set nginx remote-image=nginx:1.25.3-alpine
/container set certbot remote-image=certbot/certbot:v2.7.4

:log info "Container security applied: isolation + rate limiting + resource limits"
