local Gin = require 'gin.core.gin'

local DbSettings = {
    development = {
        host = "127.0.0.1",
        port = 6379,
        database = 3,
        pool = 5
    },

    test = {
        host = "127.0.0.1",
        port = 6379,
        database = 2,
        pool = 5
    },

    production = {
        host = os.getenv("KOSYNC_REDIS_HOST") or "127.0.0.1",
        port = tonumber(os.getenv("KOSYNC_REDIS_PORT")) or 6379,
        database = tonumber(os.getenv("KOSYNC_REDIS_DATABASE")) or 1,
        pool = 5
    }
}

local Redis = {
    options = {},
}

function Redis:new()
    local redis = require("resty.redis")
    local option = DbSettings[Gin.env]
    local red = redis:new()
    red:set_timeout(1000)
    local ok, err = red:connect(option.host, option.port)
    if ok then
        red:select(option.database)
        return red
    end
end

return Redis
