############################################################
# firewall_complete.rsc - Complete Firewall Configuration
# REQUIRES: 00-config.rsc must be imported first!
#
# IPv4 + IPv6 firewall / capsman / containers compatible
#
# УЛУЧШЕНИЯ:
# - Изоляция контейнеров (whitelist подход)
# - Rate limiting для nginx (DDoS защита)
# - Rate limiting для ICMP/ICMPv6
# - IPv6 Fasttrack
# - Логирование критических событий
# - Улучшенный SSH brute-force protection
# - Исправлена логика xRay routing
# - Использует централизованные переменные из 00-config.rsc
############################################################

############################################################
# КОНФИГУРАЦИЯ (из 00-config.rsc)
############################################################

# WAN интерфейс
:local WAN_IFACE $cfgWanPPPoE

# IPv4 подсети
:local LAN_MAIN_V4 $cfgLANNetwork
:local LAN_GUEST_V4 $cfgGuestNetwork
:local MGMT_SUBNET_V4 $cfgMgmtNetwork
:local CONTAINER_SUBNET $cfgContainerNetwork

# IPv4 адреса контейнеров
:local XRAY_IP $cfgContainerXRayIP
:local NGINX_IP $cfgContainerNginxIP

# IPv6 подсети
:local LAN_MAIN_V6 $cfgIPv6LANPrefix
:local LAN_GUEST_V6 $cfgIPv6GuestPrefix
:local MGMT_SUBNET_V6 $cfgIPv6MgmtPrefix

############################################################

###############################
# IPv4 FASTTRACK
###############################
/ip firewall filter

# Fasttrack для производительности (5-10x speedup)
add chain=forward action=fasttrack-connection \
    connection-state=established,related \
    hw-offload=yes \
    comment="FastTrack main traffic"

###############################
# BASIC IPv4 INPUT POLICY
###############################

# Accept established/related
add chain=input action=accept connection-state=established,related \
    comment="Allow established"

# Drop invalid
add chain=input action=drop connection-state=invalid \
    comment="Drop invalid packets"

# ICMP с rate limiting (защита от ICMP flood)
add chain=input protocol=icmp limit=50/5s,10:packet \
    action=accept comment="ICMP (rate limited)"
add chain=input protocol=icmp \
    action=drop comment="Drop ICMP flood"

# Allow LAN access to router
add chain=input action=accept src-address=$LAN_MAIN_V4 \
    comment="Allow mgmt from LAN main"
add chain=input action=accept src-address=$MGMT_SUBNET_V4 \
    comment="Allow mgmt from MGMT subnet"

############################################################
# CONTAINER SECURITY (WHITELIST APPROACH)
############################################################

# DNS для контейнеров (необходимо для резолвинга)
add chain=input src-address=$CONTAINER_SUBNET protocol=udp dst-port=53 \
    action=accept comment="Containers: DNS UDP"
add chain=input src-address=$CONTAINER_SUBNET protocol=tcp dst-port=53 \
    action=accept comment="Containers: DNS TCP"

# NTP для контейнеров (синхронизация времени)
add chain=input src-address=$CONTAINER_SUBNET protocol=udp dst-port=123 \
    action=accept comment="Containers: NTP"

# БЛОКИРОВАТЬ management порты от контейнеров
add chain=input src-address=$CONTAINER_SUBNET protocol=tcp \
    dst-port=22,8291,80,443,8728,8729,21,23 \
    action=drop comment="Block containers -> router management"

# БЛОКИРОВАТЬ всё остальное от контейнеров к роутеру (default deny)
add chain=input src-address=$CONTAINER_SUBNET \
    action=drop comment="Block containers -> router (default deny)"

############################################################

# Allow VPN SSTP + WireGuard
add chain=input action=accept protocol=tcp dst-port=443 \
    comment="SSTP Server"
add chain=input action=accept protocol=udp dst-port=$cfgWGListenPort \
    comment="WireGuard"

# Логирование перед drop WAN
add chain=input in-interface=$WAN_IFACE action=log \
    log-prefix="WAN-INPUT-DROP: " \
    comment="Log WAN drops"

# Drop everything else from WAN
add chain=input action=drop in-interface=$WAN_IFACE \
    comment="Drop WAN input"


###############################
# IPv4 FORWARD POLICY
###############################

# Allow established/related (после fasttrack)
add chain=forward action=accept connection-state=established,related \
    comment="Established (after fasttrack)"

# Drop invalid
add chain=forward action=drop connection-state=invalid \
    comment="Drop invalid"

# Allow LAN → WAN
add chain=forward action=accept src-address=$LAN_MAIN_V4 \
    out-interface=$WAN_IFACE \
    comment="LAN → WAN allowed"

# Guest network isolation
add chain=forward action=drop src-address=$LAN_GUEST_V4 \
    dst-address=$LAN_MAIN_V4 \
    comment="Guest → LAN block"
add chain=forward action=drop src-address=$LAN_GUEST_V4 \
    dst-address=$MGMT_SUBNET_V4 \
    comment="Guest → MGMT block"
add chain=forward action=drop src-address=$LAN_GUEST_V4 \
    dst-address=$CONTAINER_SUBNET \
    comment="Guest → Containers block"

# Allow guest network ONLY to Internet
add chain=forward action=accept src-address=$LAN_GUEST_V4 \
    out-interface=$WAN_IFACE \
    comment="Guest → WAN allowed"

############################################################
# CONTAINER NETWORK ISOLATION (FORWARD)
############################################################

# Блокировать контейнеры -> внутренние сети
add chain=forward src-address=$CONTAINER_SUBNET \
    dst-address=$LAN_MAIN_V4 \
    action=drop comment="Block containers -> LAN"
add chain=forward src-address=$CONTAINER_SUBNET \
    dst-address=$MGMT_SUBNET_V4 \
    action=drop comment="Block containers -> Management"
add chain=forward src-address=$CONTAINER_SUBNET \
    dst-address=$LAN_GUEST_V4 \
    action=drop comment="Block containers -> Guest"

# Allow containers to WAN (всё что не заблокировано выше)
add chain=forward action=accept src-address=$CONTAINER_SUBNET \
    out-interface=$WAN_IFACE \
    comment="Containers → Internet"

############################################################

############################################################
# XRAY TRAFFIC HANDLING (исправленная логика)
############################################################

# Разрешить LAN и MGMT клиентам подключаться к xRay proxy
# (для SOCKS/HTTP proxy или BGP routed трафика)
add chain=forward action=accept \
    src-address=$LAN_MAIN_V4,$MGMT_SUBNET_V4 \
    dst-address=$XRAY_IP \
    comment="Allow trusted networks → xRay proxy"

# Разрешить обратный трафик от xRay в интернет
add chain=forward action=accept \
    src-address=$XRAY_IP \
    out-interface=$WAN_IFACE \
    comment="Allow xRay → Internet"

############################################################

############################################################
# NGINX CONTAINER - RATE LIMITING (DDoS защита)
############################################################

# Connection limit: максимум 50 соединений с одного IP
add chain=forward dst-address=$NGINX_IP protocol=tcp \
    dst-port=80,443 connection-state=new \
    connection-limit=50,32 \
    action=accept \
    comment="Nginx: connection limit per IP"

# Rate limit: максимум 20 новых соединений за 5 секунд
add chain=forward dst-address=$NGINX_IP protocol=tcp \
    dst-port=80,443 connection-state=new \
    limit=20,5:packet \
    action=accept \
    comment="Nginx: rate limit new connections"

# Drop превышение лимитов (flood protection)
add chain=forward dst-address=$NGINX_IP protocol=tcp \
    dst-port=80,443 connection-state=new \
    action=drop \
    comment="Nginx: drop flood"

############################################################

# Логирование перед drop WAN forward
add chain=forward in-interface=$WAN_IFACE action=log \
    log-prefix="WAN-FORWARD-DROP: " \
    comment="Log WAN forward drops"

# Drop WAN → LAN (после всех разрешающих правил)
add chain=forward action=drop in-interface=$WAN_IFACE \
    comment="Block incoming WAN traffic"


############################################################
# PROTECTION RULES (IPv4)
############################################################

# Port scanning protection
add chain=input protocol=tcp psd=21,3s,3,1 action=drop \
    comment="Drop PSD scan"

# SYN flood protection
add chain=input protocol=tcp tcp-flags=syn limit=200,5:packet \
    action=accept comment="SYN flood limit"
add chain=input protocol=tcp tcp-flags=syn action=drop \
    comment="Drop excessive SYN"

############################################################
# SSH BRUTE-FORCE PROTECTION (progressive blocking)
############################################################

# Permanent blacklist (1 неделя)
add chain=input protocol=tcp dst-port=22,23 \
    src-address-list=ssh_blacklist \
    action=drop \
    comment="SSH: blacklist (1 week)"

# Stage 3: 3 попытки -> blacklist
add chain=input protocol=tcp dst-port=22,23 \
    connection-state=new \
    src-address-list=ssh_stage3 \
    action=add-src-to-address-list \
    address-list=ssh_blacklist \
    address-list-timeout=1w \
    comment="SSH: stage3 -> blacklist"

# Stage 2: 2 попытки -> stage3
add chain=input protocol=tcp dst-port=22,23 \
    connection-state=new \
    src-address-list=ssh_stage2 \
    action=add-src-to-address-list \
    address-list=ssh_stage3 \
    address-list-timeout=1m \
    comment="SSH: stage2 -> stage3"

# Stage 1: 1 попытка -> stage2
add chain=input protocol=tcp dst-port=22,23 \
    connection-state=new \
    src-address-list=ssh_stage1 \
    action=add-src-to-address-list \
    address-list=ssh_stage2 \
    address-list-timeout=1m \
    comment="SSH: stage1 -> stage2"

# Track new connections
add chain=input protocol=tcp dst-port=22,23 \
    connection-state=new \
    action=add-src-to-address-list \
    address-list=ssh_stage1 \
    address-list-timeout=1m \
    comment="SSH: track new connections"

############################################################

############################################################
# NAT
############################################################

/ip firewall nat

# Default masquerade for LAN and containers
add chain=srcnat action=masquerade out-interface=$WAN_IFACE \
    comment="Default masquerade for LAN and containers"

# NAT for incoming https → nginx container
# (rate limiting уже применён выше в filter)
add chain=dstnat action=dst-nat protocol=tcp dst-port=80,443 \
    in-interface=$WAN_IFACE \
    to-addresses=$NGINX_IP \
    comment="Forward HTTP/HTTPS to nginx container"


############################################################
# IPv6 FIREWALL
############################################################

/ipv6 firewall filter

###############################
# IPv6 FASTTRACK (производительность)
###############################

add chain=forward action=fasttrack-connection \
    connection-state=established,related \
    hw-offload=yes \
    comment="IPv6 FastTrack"

###############################
# IPv6 INPUT
###############################

# Allow established
add chain=input action=accept connection-state=established,related \
    comment="IPv6 established"

# Drop invalid
add chain=input action=drop connection-state=invalid \
    comment="Drop invalid IPv6"

# ICMPv6 с rate limiting (защита от flood)
add chain=input protocol=icmpv6 limit=50/5s,10:packet \
    action=accept comment="ICMPv6 (rate limited)"
add chain=input protocol=icmpv6 \
    action=drop comment="Drop ICMPv6 flood"

# Allow LAN management
add chain=input action=accept src-address=$LAN_MAIN_V6 \
    comment="LAN → router mgmt IPv6"

# Allow MGMT management
add chain=input action=accept src-address=$MGMT_SUBNET_V6 \
    comment="MGMT → router IPv6"

# Allow VPN IPv6 if needed
add chain=input action=accept protocol=tcp dst-port=443 \
    comment="SSTP IPv6"

# Логирование IPv6 WAN drops
add chain=input in-interface=$WAN_IFACE action=log \
    log-prefix="IPv6-WAN-INPUT-DROP: " \
    comment="Log IPv6 WAN drops"

# Drop all WAN input
add chain=input action=drop in-interface=$WAN_IFACE \
    comment="Drop IPv6 WAN → router"


###############################
# IPv6 FORWARD
###############################

# Allow established (после fasttrack)
add chain=forward action=accept connection-state=established,related \
    comment="IPv6 established (after fasttrack)"

# Drop invalid
add chain=forward action=drop connection-state=invalid \
    comment="Invalid IPv6"

# Guest isolation (IPv6)
add chain=forward action=drop src-address=$LAN_GUEST_V6 \
    dst-address=$LAN_MAIN_V6 \
    comment="IPv6 guest → LAN block"
add chain=forward action=drop src-address=$LAN_GUEST_V6 \
    dst-address=$MGMT_SUBNET_V6 \
    comment="IPv6 guest → MGMT block"

# Allow LAN → WAN
add chain=forward action=accept src-address=$LAN_MAIN_V6 \
    out-interface=$WAN_IFACE \
    comment="IPv6 LAN → WAN"

# Allow MGMT → WAN
add chain=forward action=accept src-address=$MGMT_SUBNET_V6 \
    out-interface=$WAN_IFACE \
    comment="IPv6 MGMT → WAN"

# Allow guest → WAN only
add chain=forward action=accept src-address=$LAN_GUEST_V6 \
    out-interface=$WAN_IFACE \
    comment="IPv6 Guest → WAN"

# Логирование IPv6 WAN forward drops
add chain=forward in-interface=$WAN_IFACE action=log \
    log-prefix="IPv6-WAN-FORWARD-DROP: " \
    comment="Log IPv6 WAN forward drops"

# Drop other WAN input
add chain=forward action=drop in-interface=$WAN_IFACE \
    comment="Drop IPv6 WAN → LAN"


############################################################
# IPv6 ND / RA Security
############################################################

/ipv6 nd
set [ find interface=$WAN_IFACE ] ra-interval=0s ra-lifetime=0s \
    advertise=no comment="Disable RA on WAN"


############################################################
# ADDITIONAL SECURITY SETTINGS
############################################################

# TCP SYN cookies (защита от SYN flood)
/ip settings set tcp-syncookies=yes

# SSH hardening (если ещё не настроено)
/ip ssh set strong-crypto=yes

############################################################
# LOGGING
############################################################

:log info "Firewall complete configuration loaded from firewall_complete.rsc"
:log info "WAN: $WAN_IFACE | LAN: $LAN_MAIN_V4 | Guest: $LAN_GUEST_V4"
:log info "Containers: $CONTAINER_SUBNET | xRay: $XRAY_IP | Nginx: $NGINX_IP"
:log info "Security features: Container isolation, Rate limiting, Brute-force protection"

############################################################
# END OF FIREWALL CONFIGURATION
############################################################
