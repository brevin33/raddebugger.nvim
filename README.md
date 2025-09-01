# Rad Debugger Nvim

[Rad Debugger](https://github.com/EpicGamesExt/raddebugger) integration for Neovim

# Showcase

[![Video](https://img.youtube.com/vi/j1dKhIUZ-HA/0.jpg)](https://www.youtube.com/watch?v=j1dKhIUZ-HA)

# Requirements

- [Rad Debugger](https://github.com/EpicGamesExt/raddebugger/releases) installed and in your path: [https://github.com/EpicGamesExt/raddebugger/releases](https://github.com/EpicGamesExt/raddebugger/releases)

# Installation

## Lazy.nvim

```lua
{
    'brevin33/raddebugger.nvim',
    dependencies = {
        'nvim-lua/plenary.nvim',
        --'nvim-telescope/telescope.nvim', -- if you want to use telescope for adding targets
    },
    config = function()
        local raddbg = require("rad_debugger")
        raddbg.setup({
            split_height = 20,
            breakpoint_color = "#51202a",
            keymaps = {
                target_menu = {
                    select = "<CR>",
                    enabled = "h",
                    disabled = "l",
                    delete = "d",
                    toggle = "t",
                },
                breakpoint_menu = {
                    select = "<CR>",
                    delete = "d",
                },
            },
        })

        vim.keymap.set("n", "<leader>db", function()
            raddbg.break_point_menu()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<leader>dt", function()
            raddbg.target_menu()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<leader>dr", function()
            raddbg.run()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<leader>ddb", function()
            raddbg.remove_all_breakpoints()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-h>", function()
            raddbg.toggle_breakpoint()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-j>", function()
            raddbg.step_over_line()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-k>", function()
            raddbg.step_into_line()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-m>", function()
            raddbg.step_over()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-,>", function()
            raddbg.step_into()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-l>", function()
            raddbg.step_out()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-;>", function()
            raddbg.continue()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<A-CR>", function()
            raddbg.kill()
        end, { noremap = true, silent = true })

        -- this works well to auto find rad files
        local function find_rad_files(root)
            local uv = vim.loop
            local queue = { { path = root, depth = 0 } }

            while #queue > 0 do
                local current = table.remove(queue, 1)
                if current.depth > 4 then
                    break
                end
                local fd = uv.fs_scandir(current.path)
                if fd then
                    while true do
                        local name, typ = uv.fs_scandir_next(fd)
                        if not name then
                            break
                        end
                        local fullpath = current.path .. "/" .. name
                        if typ == "file" and name:match("%.rad$") then
                            return fullpath
                        elseif typ == "directory" then
                            table.insert(queue, { path = fullpath, depth = current.depth + 1 })
                        end
                    end
                end
            end
            return nil
        end

        local function select_rad_project()
            local rad_project_file_path = vim.fn.input("Path to rad project file: ")
            -- or auto find rad project file
            --local cwd = vim.fn.getcwd()
            --local rad_project_file_path = find_rad_files(cwd)

            if rad_project_file_path == nil then
                print("nil rad project file path")
                return
            end

            raddbg.select_project(rad_project_file_path)
        end

        vim.keymap.set("n", "<leader>dp", function()
            select_rad_project()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<leader>do", function()
            if raddbg.is_rad_init() == false then
                select_rad_project()
            end
            raddbg.open()
        end, { noremap = true, silent = true })

        vim.keymap.set("n", "<leader>da", function()
         	local path_to_executable = vim.fn.input("Path to executable: ")
         	raddbg.add_target(path_to_executable)
        end, { noremap = true, silent = true })

        -- if you use telescope you can use this instead

        --vim.keymap.set("n", "<leader>da", function()
        --    local is_windows = vim.loop.os_uname().version:match("Windows")
        --    local find_command = { "where", "/r", ".", "*.exe" }
        --    require("telescope.builtin").find_files({
        --        prompt_title = "Select Executable",
        --        cwd = vim.loop.cwd(),
        --        find_command = find_command,
        --        attach_mappings = function(_, map)
        --            map("i", "<CR>", function(prompt_bufnr)
        --                local selection = require("telescope.actions.state").get_selected_entry()
        --                require("telescope.actions").close(prompt_bufnr)
        --                if selection then
        --                    raddbg.add_target(selection.path)
        --                end
        --            end)
        --            return true
        --        end,
        --    })
        --end, { noremap = true, silent = true })
    end,
}
```
