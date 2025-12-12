# ===================================================================
# 15-brute-force-protection.rsc
# Brute-Force Protection for SSH, Winbox, API
# Progressive blocking algorithm
# ===================================================================

/ip firewall filter

# SSH Protection (port 22)
add chain=input protocol=tcp dst-port=22 src-address-list=ssh_blacklist \
    action=drop comment="SSH: blacklist (1 day)"

add chain=input protocol=tcp dst-port=22 connection-state=new \
    src-address-list=ssh_stage3 \
    action=add-src-to-address-list address-list=ssh_blacklist address-list-timeout=1d \
    comment="SSH: stage3 -> blacklist"

add chain=input protocol=tcp dst-port=22 connection-state=new \
    src-address-list=ssh_stage2 \
    action=add-src-to-address-list address-list=ssh_stage3 address-list-timeout=1m \
    comment="SSH: stage2 -> stage3"

add chain=input protocol=tcp dst-port=22 connection-state=new \
    src-address-list=ssh_stage1 \
    action=add-src-to-address-list address-list=ssh_stage2 address-list-timeout=1m \
    comment="SSH: stage1 -> stage2"

add chain=input protocol=tcp dst-port=22 connection-state=new \
    action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m \
    comment="SSH: track new connections"

# Winbox Protection (port 8291)
add chain=input protocol=tcp dst-port=8291 src-address-list=winbox_blacklist \
    action=drop comment="Winbox: blacklist"

add chain=input protocol=tcp dst-port=8291 connection-state=new \
    src-address-list=winbox_stage3 \
    action=add-src-to-address-list address-list=winbox_blacklist address-list-timeout=1d

add chain=input protocol=tcp dst-port=8291 connection-state=new \
    src-address-list=winbox_stage2 \
    action=add-src-to-address-list address-list=winbox_stage3 address-list-timeout=1m

add chain=input protocol=tcp dst-port=8291 connection-state=new \
    src-address-list=winbox_stage1 \
    action=add-src-to-address-list address-list=winbox_stage2 address-list-timeout=1m

add chain=input protocol=tcp dst-port=8291 connection-state=new \
    action=add-src-to-address-list address-list=winbox_stage1 address-list-timeout=1m

:log info "Brute-force protection configured"
