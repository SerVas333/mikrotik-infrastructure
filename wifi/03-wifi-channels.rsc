############################################################
# 03-wifi-channels.rsc - WiFi Channel Optimization
# REQUIRES: 00-config.rsc must be imported first!
#
# Назначает оптимальные неперекрывающиеся каналы
# для 3 Access Points (R1, R2, R3) и избегает DFS
#
# ВАЖНО:
# - Применяйте ПОСЛЕ 01-wifi-capsman.rsc
# - Модифицирует существующие конфигурации
############################################################

############################################################
# LEGACY CAPSMAN - ОПТИМИЗАЦИЯ КАНАЛОВ
############################################################

# Main WiFi (5GHz) - избегаем DFS
# Используем non-DFS каналы: 36-48 (low band) или 149-165 (high band)
:if ([:len [/caps-man configuration find name=cfg-l-main]] > 0) do={
    /caps-man configuration
    set cfg-l-main \
        channel.frequency=[:tonum $cfgWiFi5GHzChannel] \
        channel.skip-dfs-channels=yes \
        channel.control-channel-width=20mhz \
        channel.band=5ghz-a/n/ac

    :log info "Legacy Main: set to 5GHz channel (freq: $cfgWiFi5GHzChannel), non-DFS"
}

# Guest WiFi (2.4GHz) - канал из конфигурации
:if ([:len [/caps-man configuration find name=cfg-l-guest]] > 0) do={
    /caps-man configuration
    set cfg-l-guest \
        channel.frequency=[:tonum $cfgWiFi24GHzChannel] \
        channel.skip-dfs-channels=yes \
        channel.control-channel-width=20mhz \
        channel.band=2ghz-b/g/n

    :log info "Legacy Guest: set to 2.4GHz (freq: $cfgWiFi24GHzChannel)"
}

############################################################
# WIFIWAVE2 - ОПТИМИЗАЦИЯ КАНАЛОВ
############################################################

# Main WiFi (wifiwave2) - 5GHz non-DFS
:if ([:len [/wifi configuration find name=cfg-w2-main]] > 0) do={
    /wifi configuration
    set cfg-w2-main \
        channel.frequency=[:tonum $cfgWiFi5GHzChannel] \
        channel.skip-dfs-channels=yes \
        channel.width=20mhz

    :log info "Wifiwave2 Main: set to 5GHz (freq: $cfgWiFi5GHzChannel), non-DFS"
}

# Guest WiFi (wifiwave2) - 2.4GHz
:if ([:len [/wifi configuration find name=cfg-w2-guest]] > 0) do={
    /wifi configuration
    set cfg-w2-guest \
        channel.frequency=[:tonum $cfgWiFi24GHzChannel] \
        channel.skip-dfs-channels=yes \
        channel.width=20mhz

    :log info "Wifiwave2 Guest: set to 2.4GHz (freq: $cfgWiFi24GHzChannel)"
}

############################################################
# FINALIZATION
############################################################

:log info "WiFi channel optimization completed from wifi/03-wifi-channels.rsc"
:log info "All APs configured for non-DFS channels"
:log info "5GHz: $cfgWiFi5GHzChannel MHz | 2.4GHz: $cfgWiFi24GHzChannel MHz"
