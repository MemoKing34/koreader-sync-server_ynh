#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================
#
# Layout of $install_dir:
#   app/        upstream koreader-sync-server source (gin application root)
#   openresty/  OpenResty built from source (provides nginx + LuaJIT + resty.*)
#   lua/        LuaRocks tree holding gin and its Lua dependencies
#
# Everything is built natively on the host; no container is involved.

_luarocks() {
    luarocks --lua-version=5.1 --tree="$install_dir/lua" "$@"
}

# Build OpenResty into $install_dir/openresty
_build_openresty() {
    local build_dir="$install_dir/build/openresty"

    ynh_script_progression "Building OpenResty (this may take a while)..."

    ynh_safe_rm "$install_dir/openresty"
    ynh_setup_source --dest_dir="$build_dir" --source_id="openresty"

    pushd "$build_dir" >/dev/null
        ynh_hide_warnings ./configure --prefix="$install_dir/openresty" -j"$(nproc)"
        ynh_hide_warnings make -j"$(nproc)"
        ynh_hide_warnings make install
    popd >/dev/null
}

# Install the gin framework and Lua dependencies into $install_dir/lua
# (mirrors what upstream's Dockerfile does, but in a dedicated tree)
_build_lua_deps() {
    local build_dir="$install_dir/build/gin"

    ynh_script_progression "Installing gin framework and Lua dependencies..."

    ynh_safe_rm "$install_dir/lua"
    ynh_setup_source --dest_dir="$build_dir" --source_id="gin"

    pushd "$build_dir" >/dev/null
        # upstream patch adding https support to gin's test runner
        patch --forward -p1 < "$install_dir/app/gin.patch"
        ynh_hide_warnings _luarocks make
    popd >/dev/null

    # replace gin's pinned, outdated luasocket with current versions
    ynh_hide_warnings _luarocks remove --force luasocket
    ynh_hide_warnings _luarocks install luasocket
    ynh_hide_warnings _luarocks install luasec
    ynh_hide_warnings _luarocks install redis-lua
}

_build_runtime() {
    mkdir -p "$install_dir/build"
    _build_openresty
    _build_lua_deps
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
