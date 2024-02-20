local logger = require("recaffinated.log")
local curl = require("plenary.curl")
local job = require("plenary.job")

local uv = vim.uv or vim.loop
local OS_SEP = uv.os_uname().sysname:lower():match('windows') and '\\' or '/' -- \ for windows, mac and linux both use \

local CACHE = string.format("%s/recaffinated/", vim.fn.stdpath("cache"))

---@alias BackendConfig RecaffinatedBackendConfig
---@class RecaffinatedBackendConfig
---@field name string The name of the backend
---@field path string The filesystem path to the backend
---@field download_link string|nil The web path to use to download the backend. Note, this must be a link that we can download with curl. THIS SHOULD NOT BE A GIT CLONE LINK
---@field backend_command string The command to run the backend against. EG, java
---@field backend_command_args table<string> Any arguments that need to be passed to the command. EG {"-jar"} . Note, this is _not_ where you pass arguments for the backend. These arguments are used to _run_ the backend.
---@field backend_args table<string>|nil Any arguments to pass to the backend. IE `$FILE`. If you wish to associate the name of the file being decompiled with a flag (such as `--file`), you can add the `$FILE` string to your args list and it will be replaced with the name of the file being decompiled. If this is uneeded for your backend (or you don't care), you do not have to do this. If `$FILE` is not found in the backend_args, we will simply set the file path as the last value in your backend args
---@field writes_to_stdout boolean|nil If provided, this tells us that we can just consume the output of stdout and dump that into the buffer. Otherwise, we will figure out the filename that the backend wrote to and open that in the buffer instead

---@class RecaffinatedBackend
---@field name string The name of the backend
---@field path string The path to the backend library to use
---@field download_link string|nil The link to use to download this backend
---@field command string The command to run the backend in. EG java
---@field command_args table<string> The arguments to put with the command to run the backend. EG: '-jar'
---@field backend_args table<string>|nil Any extra arguments to pass to the backend
---@field consume_stdout boolean Tells us if we should eat the output of stdout
---@field user_args table<string>|nil Any arguments the user provided to be used with the backend args
---@field is_ready boolean A boolean that will be set to true once the backend has been downloaded/verified
local backend = {}

---@param callback fun(success: boolean) A function for us to call once we have completed. A true/false will be provided as the parameter to indicate if the build was successful or not
function backend:build(callback)
    local successful = function()
        logger.warn(string.format("We successfully setup %s", self.name))
        self.is_ready = true
        callback(true)
    end
    local failed = function(err, data)
        if err then
            logger.error(err)
        end
        logger.warn(string.format("We were unable to setup %s", self.name))
        logger.trace(data)
        callback(false)
    end
    logger.info(string.format('Checking if "%s" at "%s" already exists', self.name, self.path))
    if vim.fn.filereadable(self.path) ~= 1 then
        logger.trace(string.format('"%s" doesn\'t exist, attempting to download it now', self.path))
        assert(self.download_link, string.format('You must provide a valid link to download "%s" as we cannot locate it with the provided path: "%s"', self.name, self.path))
        -- Download the binary
        logger.info(string.format('Attempting to fetch backend "%s" and save it to "%s"', self.name, self.path))
        local response = nil
        logger.infon(string.format('Downloading backend "%s"', self.name))
        response = curl.get({
            url = self.download_link,
            output = self.path,
            callback = successful,
            on_error = function(err) failed(err, response) end
        })
    else
        successful()
    end
end

---@param args BackendConfig
---@return RecaffinatedBackend
function backend:new(args)
    assert(args, "You must provide arguments to create a new backend interface!")
    assert(args.name, "Your backend must have a name!")
    assert(args.path, "You must specify the path to your backend!")
    assert(args.backend_command, "You must specify the command to run your backend with!")
    args.backend_command_args = args.backend_command_args or {}
    args.backend_args = args.backend_args or { "$FILE" }

    assert(type(args.backend_command_args) == 'table', "Backend command args must be a table!")
    assert(type(args.backend_args) == 'table', "Backend args must be a table!")
    assert(vim.fn.executable(args.backend_command) == 1, string.format('[Recaffinated.nvim]: Unable to read/run required backend command: "%s"', args.backend_command))
    local new_backend = {}
    setmetatable(new_backend, self)
    self.__index = self
    self.is_ready = false
    self.name = args.name
    self.path = args.path
    self.download_link = args.download_link
    self.command = args.backend_command
    self.command_args = args.backend_command_args
    self.backend_args = args.backend_args
    self.consume_stdout = args.writes_to_stdout
    return new_backend
end

---@param jar string The path to a jar that needs to be decompressed and then its contents decompiled.
---@return string decompressed_path The path to which the jar was decompiled.
function backend:decompress(jar)
    -- TODO probably need to figure out how to "mask" the extraction location over the jar
end

---@param class_file string The path the to class file to decompile
---@param buffer number The id of the buffer to write into
function backend:decompile(class_file, buffer)
    local args = {}
    for _, arg in ipairs(self.command_args or {}) do
        table.insert(args, arg)
    end
    table.insert(args, self.path)
    for _, arg in ipairs(self.backend_args or {}) do
        if arg == '$FILE' then
            table.insert(args, class_file)
        elseif arg == '$TEMP_DIR' then
            table.insert(args, CACHE)
        else
            table.insert(args, arg)
        end
    end
    logger.infon(string.format('Attempting to decompile "%s"', class_file))
    local buffer_cache = {}
    logger.debug(string.format("Decompiling %s with backend %s", class_file, self.name))
    logger.trace(self.command, args)
    local dump_stdout_to_buffer = function(cleanup_file)
        vim.schedule(function()
            vim.api.nvim_buf_set_lines(buffer, 0, -1, false , buffer_cache)
            vim.api.nvim_set_option_value("modified", false, {buf = buffer})
            vim.api.nvim_set_option_value("filetype", "java", {buf = buffer})
            vim.api.nvim_set_option_value("readonly", true, {buf = buffer})
            if cleanup_file then
                vim.api.nvim_create_autocmd("BufDelete", {
                    buffer = buffer,
                    callback = function()
                        logger.trace(string.format('Cleaning up "%s" from filesystem', cleanup_file))
                        vim.fn.delete(vim.fn.fnameescape(cleanup_file))
                    end
                })
            end
        end)
    end
    local dump_file_to_buffer = function()
        local file_name_parts = {}
        local path_sep = '[^' .. OS_SEP .. ']+'
        for part in class_file:gmatch(path_sep) do
            table.insert(file_name_parts, part)
        end
        local file_name = file_name_parts[#file_name_parts]
        file_name_parts = {CACHE}
        for path in file_name:gmatch('[^.]+') do
            table.insert(file_name_parts, path)
        end
        if file_name_parts[#file_name_parts] == 'class' then
            -- stripping off the extension of the filename
            table.remove(file_name_parts, #file_name_parts)
        end
        local out_file = table.concat(file_name_parts, OS_SEP) .. '.java'
        logger.trace(string.format("Attempting to open created file %s", out_file))
        local out_file_handle = io.open(out_file, 'r')
        if not out_file_handle then
            logger.critical(string.format('Unable to locate decompiled version of "%s"!', class_file))
            return
        end
        for line in out_file_handle:lines() do
            table.insert(buffer_cache, line)
        end
        out_file_handle:close()
        dump_stdout_to_buffer(out_file)
    end
    local job_id = job:new({
        command = self.command,
        args = args,
        enable_handlers = true,
        -- Should we stream this into the buffer or cache it and drop it in at once?
        on_stdout = function(err, data)
            if self.consume_stdout then
                if data then
                    table.insert(buffer_cache, data)
                end
            else
                logger.trace(string.format("STDOUT %s", data))
            end
        end,
        on_exit = function(_, code, signal)
            logger.trace(string.format("Code: %s -- Signal: %s", code, signal))
            if code == 0 then
                if self.consume_stdout then
                    dump_stdout_to_buffer()
                else
                    dump_file_to_buffer()
                end
            end
            logger.infon("Completed decompile")
        end
    }):start()
end

return backend
