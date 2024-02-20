local base_config = require("recaffinated.config")
local logger = require("recaffinated.log")

---@class Recaffinated
---@field backend RecaffinatedBackend|nil
---@field config RecaffinatedConfig
---@field __state string The state that we are in currently.
local M = {
    backend = nil,
    __state = "",
}

---@param dry_run boolean|nil If provided, we will _not_ save the backend we generate. Useful for initial setup/installation
local function validate_backend(dry_run, complete_callback)
    local backend_config = nil
    if type(M.config.backend) == 'string' then
        local success, config = pcall(require, string.format("recaffinated.backends.%s", M.config.backend))
        if not success then
            logger.critical(string.format('Unable to import recaffinated backend "%s"', M.config.backend))
            logger.error(config)
            return
        end
        backend_config = config
    elseif type(M.config.backend) == 'table' then
        backend_config = M.config.backend
    else
        logger.critical("Unknown backend type. Backend must either be a string or RecaffinatedBackendConfig!")
        return
    end
    local function complete(backend)
        if not dry_run and backend then
            M.backend = backend
            complete_callback()
        end
    end
    local function builder()
        local backend_builder = require('recaffinated.backends')
        local success, backend, build_err = nil, nil, nil
        success, backend = pcall(backend_builder.new, backend_builder, backend_config)
        if not success then
            logger.critical("Unable to create backend for Recaffinated!")
            logger.error(backend)
            return
        end
        success, build_err = pcall(backend.build, backend, function(build_success)
            logger.trace("Backend download was successful!", backend)
            if build_success then complete(backend) end end
        )
        if not success then
            logger.critical("Unable to build backend for Recaffinated!")
            logger.error(build_err)
        end
    end
    builder()
end

local function create_dirs()
    logger.info("Ensuring required filesystem directories exist")
    for _, dir in ipairs({
        -- We do not need to create the log dir as that is created when we initialize
        -- logging. Yes I know it should be here instead but we can't very
        -- well log without initializing logs first now can we?
        string.format("%s/%s", vim.fn.stdpath("data"), "recaffinated"), -- data
        string.format("%s/%s/%s", vim.fn.stdpath("data"), "recaffinated", "backends"), -- backends dir
        string.format("%s/%s", vim.fn.stdpath("cache"), "recaffinated"), -- temp dir
    }) do
        logger.trace(string.format('Checking for "%s"', dir))
        -- for some reason if not vim.fn.isdirectory is not working. I guess 0 isn't falsey or something in lua, idk
        if vim.fn.isdirectory(dir) == 0 then
            logger.info(string.format('Creating "%s"', dir))
            vim.fn.mkdir(dir, "p")
        end
    end
end

local function setup_au_commands()
    vim.api.nvim_create_autocmd({"BufReadPre"}, {
        pattern = {"*.class"},
        callback = function(event)
            local file = event.file
            local buffer = event.buf
            local function decompile()
                logger.trace("Decompiling!")
                M.backend:decompile(file, buffer)
            end
            if not M.backend then
                validate_backend(false, decompile)
            else
                decompile()
            end
        end
    })
end

---@param user_config RecaffinatedConfig|nil
function M.setup(user_config)
    if M.backend then return end
    M.__state = "starting"
    M.config = base_config.merge(user_config)
    logger.init({filter_level = M.config.log_level})
    logger.trace("Setting up recaffinated")
    create_dirs()
    setup_au_commands()
    M.__state = "setup"
end

-- TODO: Add a vim exposed "Setup" command that can be called manually to pull in the appropriate backend as requested
-- This should be something that is done manually and not automatically to avoid this being "not lazy"

return M
