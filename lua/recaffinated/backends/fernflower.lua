return {
    name = "fernflower",
    path = vim.fn.stdpath("data") .. "/recaffinated/backends/fernflower.jar",
    download_link = "https://github.com/miversen33/recaffeinate-backends/raw/main/backends/fernflower/fernflower.jar",
    backend_command = "java",
    backend_command_args = {"-jar"},
    backend_args = {"-dbs=true", "$FILE", '$TEMP_DIR'},
    writes_to_stdout = false
}
