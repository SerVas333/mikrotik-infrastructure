# ===================================================================
# 16-performance-optimizations.rsc
# Performance optimizations for RouterOS
# ===================================================================

# Fasttrack для established соединений
/ip firewall filter
add chain=forward action=fasttrack-connection \
    connection-state=established,related \
    hw-offload=yes \
    place-before=0 \
    comment="Fasttrack established (5-10x performance boost)"

add chain=forward connection-state=established,related \
    action=accept place-before=1 \
    comment="Accept established/related"

# TCP SYN cookies для защиты от SYN flood
/ip settings set tcp-syncookies=yes

# SSH strong crypto
/ip ssh set strong-crypto=yes host-key-size=4096

:log info "Performance optimizations applied"
