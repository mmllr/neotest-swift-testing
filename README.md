# neotest-swift-testing

This is an adapter for using the [neotest](https://github.com/nvim-neotest/neotest) framework with [Swift Testing](https://github.com/swiftlang/swift-testing).

The plugin is tested with Xcode 16 only but might work with earlier versions as well.
Thanks to Emmet Murray for his [neotest-swift](https://github.com/ehmurray8/neotest-swift) plugin which I used as a starting point.
I focused on Swift Testing only, legacy XCTest is not supported but might work.

## Features

- [x] - Run Swift Test suites and tests
- [x] - Debug tests cases with neotest dap support
- [ ] - Show parametrized tests in the test list

## Neovim DAP configuration for Swift

Add the following configuration file (e.q. neovim-dap.lua for Lazy) to enable debugging of Swift code with `nvim-dap`:

```lua
return {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = "williamboman/mason.nvim",
    opts = function()
        local dap = require("dap")
        if not dap.adapters.lldb then
            local lldb_dap_path = vim.fn.trim(vim.fn.system("xcrun -f lldb-dap"))
            dap.adapters.lldb = {
                type = "executable",
                command = lldb_dap_path, -- adjust as needed, must be absolute path
                name = "lldb",
            }
        end

        dap.configurations.swift = {
            {
                name = "Launch file",
                type = "lldb",
                request = "launch",
                program = function()
                    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
                end,
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
            },
        }
    end,
}
```

Feel free to start a pull request if you have any improvements or bug fixes.
