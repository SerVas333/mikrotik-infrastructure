############################################################
# 01-xray-integration.rsc - xRay VPN Container Integration
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
# REQUIRES: 08-containers.rsc must be applied first!
#
# xRay VPN container для маршрутизации трафика через прокси
# Режим: CLEAN BGP → ROUTING TABLE
#
# ОСОБЕННОСТИ:
# - Pinned версия контейнера
# - Resource limits
# - Интеграция с bridge-containers
# - Healthcheck и auto-restart
# - BGP маршруты → отдельная таблица маршрутизации
#
# ВАЖНО:
# - Firewall правила для xRay уже есть в firewall_complete.rsc
# - NAT masquerade для контейнеров есть в firewall_complete.rsc
############################################################

############################################################
# CONTAINER CONFIGURATION
############################################################

:local XRAY_CONTAINER "xray"
:local XRAY_IP $cfgContainerXRayIP
:local XRAY_SUBNET $cfgContainerNetwork
:local CONTAINER_BRIDGE $cfgBridgeContainers
:local CONTAINER_GATEWAY [:pick $cfgContainerGateway 0 [:find $cfgContainerGateway "/"]]

# xRay server settings (from secrets)
:local XRAY_REMOTE_SERVER $secXRayRemoteServer
:local XRAY_REMOTE_PORT $secXRayRemotePort
:local XRAY_UUID $secXRayUUID
:local XRAY_PROTOCOL $secXRayProtocol

# Routing table
:local TABLE_XRAY $cfgBGPXRayTable
:local WAN_IFACE $cfgWanPPPoE

# Container version (pinned)
:local XRAY_VERSION $cfgDockerXRayImage

# Resource limits
:local XRAY_MEMORY "200M"

############################################################
# Routing table для xRay трафика
############################################################

/routing table
:if ([:len [find name=$TABLE_XRAY]] = 0) do={
    add fib name=$TABLE_XRAY comment="Routing table for BGP-rerouted traffic via xRay"
}

:log info "xRay routing table created: $TABLE_XRAY"

############################################################
# Mount points для конфигурации и логов (на внешнем диске)
############################################################

# Используем путь из 00-config.rsc
:local XRAY_ROOT ($cfgContainerImagesRoot . "/xray")

# Создаём каталоги на внешнем диске
/file
make-directory ($XRAY_ROOT . "/config")
make-directory ($XRAY_ROOT . "/logs")

:log info ("xRay mount directories created on external storage: " . $XRAY_ROOT)

############################################################
# Container registry configuration
############################################################

/container/config
set registry-url=https://registry-1.docker.io \
    tmpdir=$cfgContainerTmpDir

############################################################
# xRay container deployment
############################################################

# Создаём mount points с полными путями
/container/mounts
:if ([:len [find name=xray-config]] = 0) do={
    add name=xray-config src=($XRAY_ROOT . "/config") dst="/etc/xray"
}
:if ([:len [find name=xray-logs]] = 0) do={
    add name=xray-logs src=($XRAY_ROOT . "/logs") dst="/var/log/xray"
}

/container
:if ([:len [find name=$XRAY_CONTAINER]] = 0) do={
    add remote-image=$XRAY_VERSION \
        interface=$CONTAINER_BRIDGE \
        envlist="" \
        root-dir=$XRAY_ROOT \
        mounts=xray-config,xray-logs \
        dns=$CONTAINER_GATEWAY \
        hostname=$XRAY_CONTAINER \
        logging=yes \
        comment="xRay VPN proxy (pinned version)" \
        name=$XRAY_CONTAINER
}

# Resource limits
/container
set $XRAY_CONTAINER memory-high=$XRAY_MEMORY

:log info "xRay container configured with resource limits"

############################################################
# Default route в xRay routing table
############################################################

/ip route
add dst-address=0.0.0.0/0 \
    gateway=$XRAY_IP \
    routing-table=$TABLE_XRAY \
    comment="Default route через xRay container"

:log info "Default route via xRay configured in $TABLE_XRAY"

############################################################
# Healthcheck и auto-restart
############################################################

/system script
:if ([:len [find name=xray-healthcheck]] = 0) do={
    add name=xray-healthcheck \
        policy=read,write,test \
        source="
:local containerName \"$XRAY_CONTAINER\"

# Проверить статус контейнера
:local status [/container/get [find name=\$containerName] value-name=status]

:if (\$status != \"running\") do={
    :log warning \"[xRay] Container stopped, restarting...\"
    /container/start \$containerName
    :delay 5s

    # Проверить после перезапуска
    :local newStatus [/container/get [find name=\$containerName] value-name=status]
    :if (\$newStatus = \"running\") do={
        :log info \"[xRay] Container successfully restarted\"
    } else={
        :log error \"[xRay] Failed to restart container\"
    }
}
" \
        comment="xRay container healthcheck and auto-restart"
}

/system scheduler
:if ([:len [find name=xray-healthcheck-scheduler]] = 0) do={
    add name=xray-healthcheck-scheduler \
        interval=1m \
        start-time=startup \
        on-event=xray-healthcheck \
        comment="Check xRay container every 1 minute"
}

:log info "xRay healthcheck configured"

############################################################
# Container start
############################################################

/container start $XRAY_CONTAINER

:log info "xRay container started"
:log info "Module xray/01-xray-integration.rsc applied successfully"
:log info "xRay IP: $XRAY_IP | Routing table: $TABLE_XRAY"
:log info "Remote server: $XRAY_REMOTE_SERVER:$XRAY_REMOTE_PORT"
:log info "Protocol: $XRAY_PROTOCOL"
