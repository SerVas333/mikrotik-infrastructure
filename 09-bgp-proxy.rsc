# 09-bgp-proxy.rsc - BGP Routing for Proxy via xRay
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!

############################################################
# BGP Configuration for xRay Proxy Routing
############################################################

# Create routing table for xRay
/routing table
:if ([:len [find name=$cfgBGPXRayTable]] = 0) do={
    add fib name=$cfgBGPXRayTable comment="xRay proxy routing table"
}

# Default route inside xray table -> forward everything to xRay container
/ip route
add routing-table=$cfgBGPXRayTable \
    dst-address=0.0.0.0/0 \
    gateway=$cfgBGPXRayNextHop \
    distance=1 \
    comment="xRay default route"

# Set BGP instance
/routing bgp instance
set default \
    as=$cfgBGPLocalAS \
    router-id=$cfgBGPRouterID

# Routing filter: IMPORT - place accepted prefixes into xray table
# This example accepts prefixes with community <REMOTE_AS:100>
/routing filter
add chain=bgp-in \
    rule="if (community ~ \"$cfgBGPRemoteAS:100\") { set routing-table=$cfgBGPXRayTable; accept } else { accept }" \
    comment="Route BGP community $cfgBGPRemoteAS:100 via xRay"

# Create BGP connection (eBGP)
/routing bgp connection
:if ([:len [find name=$cfgBGPConnectionName]] = 0) do={
    add name=$cfgBGPConnectionName \
        remote.address=$cfgBGPPeerIP \
        remote.as=$cfgBGPRemoteAS \
        address-families=ip \
        update-source=$cfgWanPPPoE \
        input.filter=bgp-in \
        .use-bfd=yes \
        comment="BGP connection to upstream (AS $cfgBGPRemoteAS)"
} else={
    set $cfgBGPConnectionName \
        remote.address=$cfgBGPPeerIP \
        remote.as=$cfgBGPRemoteAS \
        update-source=$cfgWanPPPoE
}

############################################################
# BGP MD5 Authentication (if configured)
############################################################

:if ([:len $secBGPMD5Key] > 0) do={
    /routing bgp connection
    set $cfgBGPConnectionName tcp-md5-key=$secBGPMD5Key
    :log info "BGP: MD5 authentication enabled"
}

############################################################
# END OF BGP CONFIGURATION
############################################################

:log info "BGP proxy routing configured from 09-bgp-proxy.rsc"
:log info "Local AS: $cfgBGPLocalAS | Remote AS: $cfgBGPRemoteAS"
:log info "BGP Peer: $cfgBGPPeerIP | xRay table: $cfgBGPXRayTable"
