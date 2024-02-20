---@class RecaffinatedConfig
---@field backend string|BackendConfig The name of an acceptable backend. You can also specify the params for a backend config instead. See :h recaffinated.backends for details
---@field log_level string|nil The level to limit logs to. If not provided, defaults to WARN. Must be one of the following {"CRITICAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"}
local config = {
    backend = "fernflower",
    log_level = "WARN"
}

local function validate_config(in_config)
    return {}, {}
end

function config.merge(in_config)
    local new_config = vim.tbl_deep_extend("keep", in_config or {}, config)
    new_config.merge = nil
    local config_warnings, config_errors = validate_config(in_config)
    if #config_errors > 0 then
        -- Complain about the errors and die
        error("I can't believe you've done this", vim.log.levels.ERROR)
    end
    for _, warning in ipairs(config_warnings) do
        vim.notify(warning, vim.log.levels.WARN, {})
    end
    return new_config
end

return config
