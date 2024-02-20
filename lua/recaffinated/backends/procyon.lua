return {
    name = "procyon",
    path = vim.fn.stdpath("data") .. '/recaffinated/backends/procyon.jar',
    download_link = "https://github.com/mstrobel/procyon/releases/download/v0.6.0/procyon-decompiler-0.6.0.jar",
    backend_command = "java",
    backend_command_args = {"-jar"},
    writes_to_stdout = true
}
