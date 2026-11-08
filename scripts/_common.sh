#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================
#
# Layout of $install_dir:
#   app/        koreader-sync-server application (gin application root)
#   openresty/  OpenResty runtime (nginx + LuaJIT + resty.* libraries)
#   lua/        gin framework and its Lua dependencies
#
# All three are taken from upstream's prebuilt image (koreader/kosync) with
# YunoHost's `format = "docker"` source: ynh_setup_source downloads and
# unpacks the image layers with docker-image-extract. Docker itself is
# neither needed nor used, and nothing is compiled on the server.

_install_runtime() {
    local image_dir="$install_dir/build/image"

    ynh_script_progression "Fetching prebuilt KOReader sync server..."

    ynh_safe_rm "$install_dir/build"
    ynh_setup_source --dest_dir="$image_dir" --source_id="main"

    ynh_script_progression "Installing application files..."

    ynh_safe_rm "$install_dir/app"
    ynh_safe_rm "$install_dir/openresty"
    ynh_safe_rm "$install_dir/lua"

    # keep only what is needed from the image (it also holds a whole Debian base)
    mv "$image_dir/app/koreader-sync-server" "$install_dir/app"
    mv "$image_dir/opt/openresty" "$install_dir/openresty"
    mkdir -p "$install_dir/lua/bin" "$install_dir/lua/share/lua" "$install_dir/lua/lib/lua"
    mv "$image_dir/usr/local/share/lua/5.1" "$install_dir/lua/share/lua/5.1"
    mv "$image_dir/usr/local/lib/lua/5.1" "$install_dir/lua/lib/lua/5.1"
    # gin's CLI script (the image's /usr/local/bin/gin wrapper hardcodes /usr/local)
    cp "$image_dir/usr/local/lib/luarocks/rocks-5.1/gin/0.2.0-1/bin/gin" "$install_dir/lua/bin/gin"

    ynh_safe_rm "$install_dir/build"
}

# Adapt upstream config files to this instance
_configure_app() {
    ynh_script_progression "Configuring the application..."

    # gin runtime nginx config: plain HTTP on localhost, YunoHost nginx does TLS
    ynh_config_add --template="gin-nginx.conf" --destination="$install_dir/app/config/nginx.conf"

    # app port (production block)
    sed -i "/Settings.production/,/}/ s/port = [0-9]*/port = $port/" "$install_dir/app/config/settings.lua"

    # redis port (production block)
    sed -i "/production = {/,/}/ s/port = [0-9]*/port = $port_redis/" "$install_dir/app/db/redis.lua"

    # gin writes its compiled nginx config and pid into tmp/, logs into logs/
    mkdir -p "$install_dir/app/tmp" "/var/log/$app"
    ynh_safe_rm "$install_dir/app/logs"
    ln -s "/var/log/$app" "$install_dir/app/logs"

    # redis config
    mkdir -p "/etc/$app" "$data_dir/redis"
    ynh_config_add --template="redis.conf" --destination="/etc/$app/redis.conf"
}

_set_permissions() {
    # /var/log/$app is absent after restoring a pre-upgrade safety backup
    mkdir -p "/var/log/$app"
    chown -R "$app:$app" "$install_dir" "$data_dir" "/var/log/$app"
    chmod -R o-rwx "$install_dir" "$data_dir" "/var/log/$app"
    chown root:"$app" "/etc/$app" "/etc/$app/redis.conf"
    chmod 750 "/etc/$app"
    chmod 640 "/etc/$app/redis.conf"
}

_register_services() {
    yunohost service add "${app}-redis" \
        --description="Redis database for $app" \
        --test_status="redis-cli -p $port_redis ping | grep -q PONG"
    yunohost service add "$app" \
        --description="KOReader sync server" \
        --log="/var/log/$app/production-error.log" \
        --test_status="curl -fsS -H 'Accept: application/vnd.koreader.v1+json' http://127.0.0.1:$port/healthcheck | grep -q OK"
}

_unregister_services() {
    for service in "$app" "${app}-redis"; do
        if ynh_hide_warnings yunohost service status "$service" >/dev/null; then
            yunohost service remove "$service"
        fi
    done
}
