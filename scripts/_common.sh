#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

pkg_dependencies="ca-certificates curl patch build-essential libreadline-dev libncurses5-dev libpcre2-dev libssl-dev zlib1g-dev luarocks redis-server openssl"

openresty_prefix="${install_dir}/openresty"
luarocks_tree="${install_dir}/rocks"

build_openresty() {
    if [ -x "${openresty_prefix}/nginx/sbin/nginx" ]; then
        return
    fi

    ynh_script_progression "Building OpenResty runtime..."

    ynh_setup_source --source_id="openresty" --dest_dir="${install_dir}/.build/openresty" --full_replace

    pushd "${install_dir}/.build/openresty" >/dev/null
    ./util/configure --prefix="${openresty_prefix}"
    make -j"$(nproc)"
    make install
    popd >/dev/null
}

build_luarocks_stack() {
    if [ -x "${luarocks_tree}/bin/gin" ]; then
        return
    fi

    ynh_script_progression "Installing Gin and Lua dependencies..."

    export PATH="${openresty_prefix}/luajit/bin:${PATH}"

    ynh_setup_source --source_id="gin" --dest_dir="${install_dir}/.build/gin" --full_replace

    pushd "${install_dir}/.build/gin" >/dev/null
    patch -N -p1 < "${install_dir}/gin.patch"
    luarocks --lua-version=5.1 --lua-dir="${openresty_prefix}/luajit" --tree="${luarocks_tree}" make
    popd >/dev/null

    luarocks --lua-version=5.1 --lua-dir="${openresty_prefix}/luajit" --tree="${luarocks_tree}" install luasocket
    luarocks --lua-version=5.1 --lua-dir="${openresty_prefix}/luajit" --tree="${luarocks_tree}" install luasec
    luarocks --lua-version=5.1 --lua-dir="${openresty_prefix}/luajit" --tree="${luarocks_tree}" install redis-lua
}

configure_app_files() {
    ynh_script_progression "Configuring application files..."

    mkdir -p "${install_dir}/logs" "${install_dir}/tmp"
    mkdir -p "${data_dir}/redis"

    ynh_replace --match='port = 7200,' --replace="port = ${port}," --file="${install_dir}/config/settings.lua"

    ynh_config_add --template="upstream_nginx.conf" --destination="${install_dir}/config/nginx.conf"
    ynh_config_add --template="redis.lua" --destination="${install_dir}/db/redis.lua"

    chown -R "$app:$app" "${install_dir}" "${data_dir}"
    chmod -R u=rwX,g=rX,o= "${install_dir}" "${data_dir}"
}

set_registration_setting() {
    if [ "${enable_user_registration}" = "1" ] || [ "${enable_user_registration}" = "true" ]; then
        enable_user_registration="true"
    else
        enable_user_registration="false"
    fi
    ynh_app_setting_set --key=enable_user_registration --value="${enable_user_registration}"
}

setup_system_configs() {
    ynh_script_progression "Installing system configuration..."

    mkdir -p "/etc/${app}" "/var/log/${app}"
    ynh_config_add --template="redis.conf" --destination="/etc/${app}/redis.conf"
    ynh_config_add --template="redis.service" --destination="/etc/systemd/system/${app}-redis.service"
    ynh_config_add_systemd
    ynh_config_add_nginx
    ynh_systemctl --service="${app}-redis" --action="enable"
    ynh_systemctl --service="${app}-redis" --action="restart"
    ynh_systemctl --service="$app" --action="enable"

    yunohost service add "${app}-redis" --description="Redis for ${app}" --test_status="redis-cli -p ${port_redis} ping | grep -q PONG"
    yunohost service add "$app" --description="KOReader Sync Server" --log="/var/log/${app}/${app}.log" --test_status="curl -fsS -H 'Accept: application/vnd.koreader.v1+json' http://127.0.0.1:${port}/healthcheck | grep -q '\"state\":\"OK\"'"

    chown -R "$app:$app" "/var/log/${app}" "${data_dir}/redis"
}
