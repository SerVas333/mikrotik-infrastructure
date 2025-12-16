# 08-containers.rsc - Docker Container Configuration
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# Container Networking
############################################################

# Create veth interface
/interface veth
add name=$cfgVethContainers

# Add veth to container bridge
/interface bridge port
add bridge=$cfgBridgeContainers interface=$cfgVethContainers

# Container gateway IP
/ip address
add address=$cfgContainerGateway \
    interface=$cfgBridgeContainers \
    comment="Container gateway"

############################################################
# Container System Configuration
############################################################

/container config
set tmpdir=$cfgContainerTmpDir \
    registry-url=https://registry-1.docker.io

############################################################
# Container Mounts
############################################################

/container mount
add name=mount-data \
    src=$cfgContainerDataRoot \
    dst=/data

add name=mount-nginx-conf \
    src=($cfgContainerImagesRoot . "/nginx/conf") \
    dst=/etc/nginx/conf.d

add name=mount-xray-conf \
    src=($cfgContainerImagesRoot . "/xray/conf") \
    dst=/etc/xray

############################################################
# Container Network
############################################################

:if ([:len [/container network find name=containers]] = 0) do={
    /container network
    add name=containers \
        subnet=$cfgContainerNetwork \
        gateway=[:pick $cfgContainerGateway 0 [:find $cfgContainerGateway "/"]]
}

############################################################
# Container Definitions
############################################################

# xRay Container
/container
add name=xray \
    interface=containers \
    root-dir=($cfgContainerImagesRoot . "/xray") \
    mounts=mount-xray-conf \
    start-on-boot=yes \
    remote-image=$cfgDockerXRayImage \
    comment="xRay proxy container"

# Nginx Container
add name=nginx \
    interface=containers \
    root-dir=($cfgContainerImagesRoot . "/nginx") \
    mounts=mount-nginx-conf,mount-lets \
    start-on-boot=yes \
    remote-image=$cfgDockerNginxImage \
    comment="Nginx reverse proxy"

# Certbot Container (on-demand)
add name=certbot \
    interface=containers \
    root-dir=($cfgContainerImagesRoot . "/certbot") \
    mounts=mount-lets \
    start-on-boot=no \
    remote-image=$cfgDockerCertbotImage \
    comment="Let's Encrypt certbot"

############################################################
# Start Containers
############################################################

/container start xray
/container start nginx
# certbot starts on-demand via renewal script

############################################################
# Port Forwarding (NAT)
############################################################

/ip firewall nat
add chain=dstnat \
    in-interface=$cfgWanPPPoE \
    protocol=tcp dst-port=80 \
    action=dst-nat \
    to-addresses=$cfgContainerNginxIP \
    to-ports=80 \
    comment="HTTP -> nginx"

add chain=dstnat \
    in-interface=$cfgWanPPPoE \
    protocol=tcp dst-port=443 \
    action=dst-nat \
    to-addresses=$cfgContainerNginxIP \
    to-ports=443 \
    comment="HTTPS -> nginx"

############################################################
# Container Isolation (Use firewall_complete.rsc instead!)
############################################################

# NOTE: Container firewall rules are in firewall_complete.rsc
# This provides:
# - DNS/NTP whitelist access
# - Block management ports
# - Rate limiting for nginx
# Use firewall_complete.rsc for production!

############################################################
# END OF CONTAINER CONFIGURATION
############################################################

:log info "Container configuration applied from 08-containers.rsc"
:log info "xRay: $cfgContainerXRayIP | Nginx: $cfgContainerNginxIP"
:log info "Images: xRay=$cfgDockerXRayImage | Nginx=$cfgDockerNginxImage"
