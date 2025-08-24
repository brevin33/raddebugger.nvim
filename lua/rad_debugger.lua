local M = {}
local rad_project = {}
local ns_id_menu = vim.api.nvim_create_namespace("rad_debugger")
local ns_id_breakpoints = vim.api.nvim_create_namespace("breakpoint_symbol")
local rad_project_file_path
local rel_path_to_project_file

local rad_target_selected_menu_keymaps = {
	select = "<CR>",
	enabled = "h",
	disabled = "l",
	delete = "d",
	toggle = "t",
}

local rad_breakpoint_selected_menu_keymaps = {
	select = "<CR>",
	delete = "d",
}

local breakpoint_color = "#51202a"

local split_height = 20

local function setup(opts)
	-- check if raddbg is in path
	local has_raddbg = vim.fn.executable("raddbg") == 1
	if not has_raddbg then
		-- how to throw error
		error("raddbg not found in PATH.")
		return
	end

	if opts ~= nil then
		if opts.keymaps ~= nil then
			local keymaps = opts.keymaps
			if keymaps.target_menu ~= nil then
				local target_menu = keymaps.target_menu
				if target_menu.select ~= nil then
					rad_target_selected_menu_keymaps.select = target_menu.select
				end
				if target_menu.enabled ~= nil then
					rad_target_selected_menu_keymaps.enabled = target_menu.enabled
				end
				if target_menu.disabled ~= nil then
					rad_target_selected_menu_keymaps.disabled = target_menu.disabled
				end
				if target_menu.delete ~= nil then
					rad_target_selected_menu_keymaps.delete = target_menu.delete
				end
				if target_menu.toggle ~= nil then
					rad_target_selected_menu_keymaps.toggle = target_menu.toggle
				end
			end
			if keymaps.breakpoint_menu ~= nil then
				local breakpoint_menu = keymaps.breakpoint_menu
				if breakpoint_menu.select ~= nil then
					rad_breakpoint_selected_menu_keymaps.select = breakpoint_menu.select
				end
				if breakpoint_menu.delete ~= nil then
					rad_breakpoint_selected_menu_keymaps.delete = breakpoint_menu.delete
				end
			end
		end

		if opts.split_height ~= nil then
			split_height = opts.split_height
		end

		if opts.breakpoint_color ~= nil then
			breakpoint_color = opts.breakpoint_color
		end
	end
end

local function switch_slashes(str)
	if str == nil then
		return str
	end
	return str:gsub("\\+", "/")
end

local function switch_slashes_to_bad(str)
	if str == nil then
		return str
	end
	return str:gsub("/", "\\")
end

local function relpath(from, to)
	from = vim.loop.fs_realpath(from)
	from = switch_slashes(from)
	to = vim.loop.fs_realpath(to)
	to = switch_slashes(to)
	local sep = "/"
	local function split(path)
		local t = {}
		for part in string.gmatch(path, "[^" .. sep .. "]+") do
			table.insert(t, part)
		end
		return t
	end

	local from_parts = split(from)
	local to_parts = split(to)

	-- Find common prefix
	local i = 1
	while from_parts[i] and to_parts[i] and from_parts[i] == to_parts[i] do
		i = i + 1
	end

	local up = {}
	for j = i, #from_parts do
		table.insert(up, "..")
	end
	for j = i, #to_parts do
		table.insert(up, to_parts[j])
	end

	local result = table.concat(up, sep)
	result = switch_slashes(result)
	return result
end
local function convert_from_rad_project_relative_to_abs(path)
	-- check to make sure not abs already
	if rel_path_to_project_file == "" then
		return path
	end
	if path:match("^%a:[\\/]") or path:match("^\\\\") then
		return path
	end
	-- get last char of rel_path_to_project_file
	local last_char = rel_path_to_project_file:sub(-1)
	local new_path
	if last_char == "/" then
		new_path = rel_path_to_project_file .. path
	else
		new_path = rel_path_to_project_file .. "/" .. path
	end
	return new_path
end

local function abs_to_rel(abs_path)
	local cwd = vim.fn.getcwd()
	return relpath(cwd, abs_path)
end

local get_rad_project_file_path = function()
	return rad_project_file_path
end

-- Define custom highlight group for breakpoints
vim.api.nvim_set_hl(0, "RadBreakpointLine", {
	bg = breakpoint_color, -- Dark red background
	-- fg = "#ffffff", -- Optional: set text color
})

local function split_by_space(str)
	local result = {}
	for word in string.gmatch(str, "%S+") do
		table.insert(result, word)
	end
	return result
end

local function is_rad_init()
	return rad_project_file_path ~= nil
end

local function format_file_location_for_rad(file_path, line)
	local abs_path = vim.fn.fnamemodify(file_path, ":p")
	return abs_path .. ":" .. tostring(line)
end

local function remove_quotes(str)
	return str:gsub('"', "")
end

local function get_file_name_and_extenstion_from_path(path)
	local file = path:match("([^\\/]+)$")
	if not file then
		print("failed to get file name and extension from path: " .. path)
		return path
	end
	local name, ext = file:match("^(.*)%.([^%.]+)$")
	if name and ext then
		return name .. "." .. ext
	end
	return file -- returns file name even if no extension
end

local function get_string_out(byWord, i)
	-- ok this might not be a string
	local first_char = byWord[i]:sub(1, 1)
	if first_char == '"' or first_char == "'" then
		local result = ""
		local first = true
		while true do
			i = i + 1
			local word = byWord[i]
			if first then
				result = word
				first = false
			else
				result = result .. " " .. word
			end

			local last_char = word:sub(-1)
			if last_char == '"' then
				break
			end
		end
		return result, i
	else
		i = i + 1
		local word = byWord[i]
		return word, i
	end
end

local function parse_rad_project_file(file_path)
	local rad_project = {}
	rad_project.targets = {}  -- initialize as an empty table
	rad_project.breakpoints = {} -- initialize as an empty table
	rad_project.recent_file = {} -- initialize as an empty table

	local file = io.open(file_path, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	local byWord = split_by_space(content)
	local i = 1
	while i <= #byWord do
		local word = byWord[i]

		-- parse recent_file
		if word == "recent_file:" then
			i = i + 1
			word = byWord[i]
			if word ~= "path:" then
				goto continue
			end
			i = i + 1
			word = byWord[i]
			local path = remove_quotes(word)
			path = convert_from_rad_project_relative_to_abs(path)
			table.insert(rad_project.recent_file, path)
			goto continue
		end

		-- parse target
		if word == "target:" then
			local target = {}
			target.enabled = false
			i = i + 1
			word = byWord[i]
			local lots_data = false
			if word == "{" then
				i = i + 1
				word = byWord[i]
				lots_data = true
			end
			while word ~= "}" do
				if word == "executable:" then
					local executable, j = get_string_out(byWord, i)
					i = j
					executable = remove_quotes(executable)
					executable = convert_from_rad_project_relative_to_abs(executable)
					executable = switch_slashes(executable)
					target.executable = executable
					goto contiue_target
				end
				if word == "working_directory:" then
					local working_directory, j = get_string_out(byWord, i)
					i = j
					working_directory = remove_quotes(working_directory)
					working_directory = switch_slashes(working_directory)
					target.working_directory = working_directory
					goto contiue_target
				end
				if word == "enabled:" then
					i = i + 1
					word = byWord[i]
					local enabled = word == "1"
					target.enabled = enabled
					goto contiue_target
				end
				::contiue_target::
				if lots_data == false then
					break
				end
				i = i + 1
				word = byWord[i]
			end
			table.insert(rad_project.targets, target)
			goto continue
		end

		-- parse breakpoints
		if word == "breakpoint:" then
			local breakpoint = {}
			i = i + 1
			word = byWord[i]
			local lots_data = false
			if word == "{" then
				i = i + 1
				word = byWord[i]
				lots_data = true
			end
			while word ~= "}" do
				if word == "source_location:" then
					local source_location, j = get_string_out(byWord, i)
					i = j
					source_location = remove_quotes(source_location)
					local path, line, column = string.match(source_location, "^(.-):(%d+):(%d+)$")
					path = convert_from_rad_project_relative_to_abs(path)
					path = switch_slashes(path)
					breakpoint.path = path
					breakpoint.line = line
					-- ignore column because it seems to always be 1
					-- breakpoint.column = column
					goto breakpoint_continue
				end
				if word == "condition:" then
					local condition, j = get_string_out(byWord, i)
					i = j
					condition = remove_quotes(condition)
					breakpoint.condition = condition
					goto breakpoint_continue
				end
				::breakpoint_continue::
				if lots_data == false then
					break
				end
				i = i + 1
				word = byWord[i]
			end

			-- get line contents
			local file_path = breakpoint.path
			local line = tonumber(breakpoint.line)
			local file = io.open(file_path, "r")
			if not file then
				line_content = "<no file found>"
			else
				local line_content
				for i = 1, line do
					line_content = file:read("*line")
					if not line_content then
						break
					end
				end
				file:close()
				breakpoint.content = line_content or " "
			end
			-- remove leading whitespace
			if breakpoint.content ~= nil then
				breakpoint.content = string.gsub(breakpoint.content, "^%s+", "")
			end

			table.insert(rad_project.breakpoints, breakpoint)
			goto continue
		end

		::continue::
		i = i + 1
	end
	return rad_project
end

local function copy_file(src, dst)
	local infile = io.open(src, "rb")
	if not infile then
		return false
	end

	local content = infile:read("*all")
	infile:close()
	if not content then
		return false
	end

	local outfile = io.open(dst, "wb")
	if not outfile then
		return false
	end

	local ok = outfile:write(content)
	outfile:close()
	return ok ~= nil
end

local function save_rad_project()
	local rad_project_file_path = get_rad_project_file_path()
	local data_dir = vim.fn.stdpath("data")
	local temp_file_path = data_dir .. "/rad_project.tmp"
	-- write the project to a temp to make sure we don't lose our project
	os.remove(temp_file_path)
	local ok = os.rename(rad_project_file_path, temp_file_path)
	if not ok then
		print("failed to rename rad project file to temp file.")
		return false
	end
	--local ok = copy_file(rad_project_file_path, temp_file_path)
	--if not ok then
	--print("failed to copy rad project file to temp file. rad debugger may not be running.")
	--return false
	--end
	os.remove(rad_project_file_path)
	--vim.fn.system("raddbg --ipc save_project " .. rad_project_file_path)
	os.execute("raddbg --ipc save_project " .. rad_project_file_path)
	os.execute("raddbg --ipc accept " .. rad_project_file_path)

	-- loop until the file exists
	local start_time = vim.loop.hrtime()
	while true do
		local file = io.open(rad_project_file_path, "r")
		if file then
			file:close()
			break
		end
		if (vim.loop.hrtime() - start_time) / 1e6 > 1000 then -- 500ms timeout
			-- copy the temp file to the original file because we failed to save the project
			copy_file(temp_file_path, rad_project_file_path)
			return false
		end
	end
	os.remove(temp_file_path)
	return true
end

local update_rad_project = function()
	if rad_project_file_path == nil then
		print("have not selected a rad project file yet")
		return false
	end

	local success = save_rad_project()
	if not success then
		print("failed to save rad project file. Rad debugger may not be running.")
		return false
	end
	local rad_project_file_path = get_rad_project_file_path()
	local file = io.open(rad_project_file_path, "r")
	if not file then
		rad_project = {}
		print("no rad project file found. path checked: " .. rad_project_file_path)
		return false
	end
	file:close()
	local last_breakpoints = rad_project.breakpoints
	rad_project = parse_rad_project_file(rad_project_file_path)

	vim.schedule(function()
		-- remove all breakpoints
		if last_breakpoints then
			for _, breakpoint in ipairs(last_breakpoints) do
				local file_path = breakpoint.path
				local bufnr = vim.fn.bufnr(file_path, false)
				if bufnr ~= -1 then
					vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace("breakpoint_symbol"), 0, -1)
					vim.api.nvim_buf_clear_namespace(bufnr, ns_id_breakpoints, 0, -1)
				end
			end
		end
		-- add a symbol and color lines with breakpoints
		for _, breakpoint in ipairs(rad_project.breakpoints) do
			local file_path = breakpoint.path
			local line = tonumber(breakpoint.line)

			-- check if the file exists
			local ok = vim.fn.filereadable(file_path) == 1
			if not ok then
				print("No file found at path: " .. file_path)
				goto continue
			end

			-- Get buffer number for the file
			local bufnr = vim.fn.bufnr(file_path, true)

			-- Load the buffer if it's not already loaded
			if not vim.api.nvim_buf_is_loaded(bufnr) then
				vim.fn.bufload(bufnr)
			end

			-- check if the line exists in the buffer
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			if line > line_count or line < 1 then
				print("Line " .. line .. " is out of range in file: " .. file_path)
				goto continue
			end

			vim.api.nvim_buf_set_extmark(bufnr, vim.api.nvim_create_namespace("breakpoint_symbol"), line - 1, 0, {})
			-- Place the sign using extmarks (more modern approach)
			vim.api.nvim_buf_set_extmark(bufnr, ns_id_breakpoints, line - 1, 0, {
				sign_hl_group = "DiagnosticError",
				line_hl_group = "RadBreakpointLine",
			})

			::continue::
		end
	end)

	return true
end

local function replace_underscores_with_spaces(str)
	-- make sure we have a string
	if type(str) ~= "string" then
		return str
	end
	return str:gsub("_", " ")
end

local function line_to_target_index(line)
	local buf = vim.api.nvim_get_current_buf()
	local idx = 0
	for l = 1, line do
		local text = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
		if text and not text:match("^%s") then
			idx = idx + 1
		end
	end
	return idx > 0 and idx or nil
end

local function create_list_buf(name, list, list_val_main_key)
	local target_bufnr = nil

	if target_bufnr then
		-- Switch to the buffer in a new window
		vim.cmd("botright " .. tostring(split_height) .. "split")
		vim.api.nvim_win_set_buf(0, target_bufnr)
		buf = target_bufnr
		vim.api.nvim_buf_set_option(buf, "modifiable", true)
	else
		vim.cmd("botright " .. tostring(split_height) .. "new")
		buf = vim.api.nvim_get_current_buf()
	end

	local lines = {}
	local meta = {}
	for _, target in ipairs(list) do
		-- insert main key
		local found_main_key = false
		for key, value in pairs(target) do
			if key == list_val_main_key then
				local k = replace_underscores_with_spaces(key)
				local val = tostring(value)
				found_main_key = true
				-- stip leading whitespace and trailing whitespace
				val = string.gsub(val, "^%s+", "")
				val = string.gsub(val, "%s+$", "")
				if val == nil then
					val = "<no value>"
				end
				if val == "" then
					val = "<empty string>"
				end
				table.insert(lines, val)
				table.insert(meta, { type = "main_key" })
			end
		end
		if not found_main_key then
			table.insert(lines, "<no main key>")
			table.insert(meta, { type = "main_key" })
		end

		-- insert all other keys
		for key, value in pairs(target) do
			if key ~= list_val_main_key then
				local k = replace_underscores_with_spaces(key)
				local val = tostring(value)
				-- if first char is _ then don't add it
				table.insert(lines, "  " .. k .. ": " .. val)
				table.insert(meta, { type = "property", key = k, val = val })
				::continue::
			end
		end
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(buf, ns_id_menu, 0, -1)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	for i, info in ipairs(meta) do
		if info.type == "main_key" then
			vim.api.nvim_buf_set_extmark(buf, ns_id_menu, i - 1, 0, {
				virt_text = { { lines[i], "String" } },
				virt_text_pos = "overlay",
			})
		elseif info.type == "property" then
			vim.api.nvim_buf_set_extmark(buf, ns_id_menu, i - 1, 0, {
				virt_text = {
					{ "  " .. info.key, "Identifier" },
					{ ": ",             "Normal" },
					{ info.val,         "Normal" },
				},
				virt_text_pos = "overlay",
			})
		end
	end

	local function move_to_next_target()
		local buf = vim.api.nvim_get_current_buf()
		local curr_line = vim.fn.line(".")
		local total_lines = vim.api.nvim_buf_line_count(buf)
		for l = curr_line + 1, total_lines do
			local text = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
			if text and not text:match("^%s") then
				vim.api.nvim_win_set_cursor(0, { l, 0 })
				return
			end
		end
	end

	local function move_to_prev_target()
		local buf = vim.api.nvim_get_current_buf()
		local curr_line = vim.fn.line(".")
		for l = curr_line - 1, 1, -1 do
			local text = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
			if text and not text:match("^%s") then
				vim.api.nvim_win_set_cursor(0, { l, 0 })
				return
			end
		end
	end

	vim.api.nvim_buf_set_keymap(buf, "n", "j", "", { noremap = true, silent = true, callback = move_to_next_target })
	vim.api.nvim_buf_set_keymap(buf, "n", "k", "", { noremap = true, silent = true, callback = move_to_prev_target })

	vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		noremap = true,
		silent = true,
		callback = callback,
	})

	-- bind escape key to exit the buffer
	vim.api.nvim_buf_set_keymap(buf, "n", "<ESC>", "", {
		noremap = true,
		silent = true,
		callback = function()
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
	})
end

local function rad_select_target(target_path)
	local file_name = get_file_name_and_extenstion_from_path(target_path)
	if file_name == nil then
		vim.fn.system("raddbg --ipc select_target " .. target_path)
	else
		vim.fn.system("raddbg --ipc select_target " .. file_name)
	end
end

local function rad_enable_target(target_path)
	local file_name = get_file_name_and_extenstion_from_path(target_path)
	if file_name == nil then
		vim.fn.system("raddbg --ipc enable_target " .. target_path)
	else
		vim.fn.system("raddbg --ipc enable_target " .. file_name)
	end
end

local function rad_disable_target(target_path)
	local file_name = get_file_name_and_extenstion_from_path(target_path)
	if file_name == nil then
		vim.fn.system("raddbg --ipc disable_target " .. target_path)
	else
		vim.fn.system("raddbg --ipc disable_target " .. file_name)
	end
end

local function rad_delete_target(target_path)
	local file_name = get_file_name_and_extenstion_from_path(target_path)
	if file_name == nil then
		vim.fn.system("raddbg --ipc remove_target " .. target_path)
	else
		vim.fn.system("raddbg --ipc remove_target " .. file_name)
	end
end

local function select_rad_target()
	local success = update_rad_project()
	if not success then
		return false
	end
	if rad_project.targets == nil then
		print("No targets found in rad project file")
		return false
	end
	local targets_len = #rad_project.targets
	if targets_len == 0 then
		print("No targets found in rad project file")
		return false
	end
	create_list_buf("rad_target_list", rad_project.targets, "executable")
	local buf = vim.api.nvim_get_current_buf()
	local function select()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local target = rad_project.targets[line_idx]
		-- close the list buffer
		vim.api.nvim_buf_delete(buf, { force = true })
		rad_select_target(target.executable)
	end

	local function enabled()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local target = rad_project.targets[line_idx]
		rad_enable_target(target.executable)
		-- reopen to refresh the list
		vim.api.nvim_buf_delete(buf, { force = true })
		success = select_rad_target()
		-- jump to the line we are on
		if line <= vim.api.nvim_buf_line_count(0) then
			if success then
				vim.api.nvim_win_set_cursor(0, { line, 0 })
			end
		end
	end

	local function disabled()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local target = rad_project.targets[line_idx]
		rad_disable_target(target.executable)
		-- reopen to refresh the list
		vim.api.nvim_buf_delete(buf, { force = true })
		success = select_rad_target()
		-- jump to the line we are on
		if line <= vim.api.nvim_buf_line_count(0) then
			if success then
				vim.api.nvim_win_set_cursor(0, { line, 0 })
			end
		end
	end

	local function toggle_enabled()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local target = rad_project.targets[line_idx]
		if target.enabled then
			rad_disable_target(target.executable)
		else
			rad_enable_target(target.executable)
		end
		-- reopen to refresh the list
		vim.api.nvim_buf_delete(buf, { force = true })
		success = select_rad_target()
		-- jump to the line we are on
		if line <= vim.api.nvim_buf_line_count(0) then
			if success then
				vim.api.nvim_win_set_cursor(0, { line, 0 })
			end
		end
	end

	local function delete()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local target = rad_project.targets[line_idx]
		rad_delete_target(target.executable)
		-- reopen to refresh the list
		vim.api.nvim_buf_delete(buf, { force = true })
		success = select_rad_target()
		-- jump to the line we are on
		if line <= vim.api.nvim_buf_line_count(0) then
			if success then
				vim.api.nvim_win_set_cursor(0, { line, 0 })
			end
		end
	end

	vim.api.nvim_buf_set_keymap(buf, "n", rad_target_selected_menu_keymaps.select, "", {
		noremap = true,
		silent = true,
		callback = select,
	})

	vim.api.nvim_buf_set_keymap(buf, "n", rad_target_selected_menu_keymaps.enabled, "", {
		noremap = true,
		silent = true,
		callback = enabled,
	})

	vim.api.nvim_buf_set_keymap(buf, "n", rad_target_selected_menu_keymaps.disabled, "", {
		noremap = true,
		silent = true,
		callback = disabled,
	})

	vim.api.nvim_buf_set_keymap(buf, "n", rad_target_selected_menu_keymaps.delete, "", {
		noremap = true,
		silent = true,
		callback = delete,
	})

	vim.api.nvim_buf_set_keymap(buf, "n", rad_target_selected_menu_keymaps.toggle, "", {
		noremap = true,
		silent = true,
		callback = toggle_enabled,
	})

	return true
end

local function goto_rad_breakpoint()
	local success = update_rad_project()
	if not success then
		return false
	end
	if rad_project.breakpoints == nil then
		print("No breakpoints found in rad project file")
		return false
	end
	local breakpoints_len = #rad_project.breakpoints
	if breakpoints_len == 0 then
		print("No breakpoints found in rad project file")
		return false
	end
	create_list_buf("rad_breakpoint_list", rad_project.breakpoints, "path")
	local buf = vim.api.nvim_get_current_buf()
	local function select()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local last_buffer = vim.api.nvim_get_current_buf()
		local breakpoint = rad_project.breakpoints[line_idx]
		local ok = vim.fn.filereadable(breakpoint.path) == 1
		if not ok then
			print("No file found at path: " .. breakpoint.path)
			return
		end
		-- close the list buffer
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.cmd("edit " .. breakpoint.path)
		-- move to the line
		local line = tonumber(breakpoint.line)
		-- check if the line exists in the buffer
		vim.api.nvim_win_set_cursor(0, { line, 0 })
	end

	local function delete()
		local line = vim.fn.line(".")
		local line_idx = line_to_target_index(line)
		local breakpoint = rad_project.breakpoints[line_idx]

		local file_location = format_file_location_for_rad(breakpoint.path, breakpoint.line)
		-- format a bit differently becuase we need to target the exact thing from the project file
		--local file_location = tostring(breakpoint.path) .. ":" .. tostring(breakpoint.line)

		vim.fn.system("raddbg --ipc toggle_breakpoint " .. file_location)
		-- reopen to refresh the list
		vim.api.nvim_buf_delete(buf, { force = true })
		success = goto_rad_breakpoint()
		-- jump to the line we are on
		-- make sure line is not out of range
		if line <= vim.api.nvim_buf_line_count(0) then
			if success then
				vim.api.nvim_win_set_cursor(0, { line, 0 })
			end
		end
	end

	vim.api.nvim_buf_set_keymap(buf, "n", rad_breakpoint_selected_menu_keymaps.select, "", {
		noremap = true,
		silent = true,
		callback = select,
	})

	vim.api.nvim_buf_set_keymap(buf, "n", rad_breakpoint_selected_menu_keymaps.delete, "", {
		noremap = true,
		silent = true,
		callback = delete,
	})
	return true
end

local function rad_toggle_breakpoint()
	local line = vim.fn.line(".")
	local current_buffer = vim.api.nvim_get_current_buf()
	local file_path = vim.api.nvim_buf_get_name(current_buffer)
	local file_location = format_file_location_for_rad(file_path, line)
	file_location = switch_slashes(file_location)
	--vim.fn.system("raddbg --ipc toggle_breakpoint " .. file_location)
	local scrolloff = vim.opt.scrolloff:get()

	-- remove all breakpoints
	local exists = false
	local current_buffer = vim.api.nvim_get_current_buf()
	local current_file_path = vim.api.nvim_buf_get_name(current_buffer)
	local current_line = vim.fn.line(".")

	-- async because this can have to wait on the rad debugger
	local Job = require("plenary.job")
	Job:new({
		command = "raddbg",
		args = { "--ipc", "toggle_breakpoint", file_location },
		on_exit = function(j, return_val)
			update_rad_project()
			vim.schedule(function()
				-- don't no why neovim is doing this
				vim.opt.scrolloff = scrolloff
			end)
		end,
	}):start()
end

local function rad_step_over()
	vim.fn.system("raddbg --ipc step_over_line")
end

local function rad_step_into()
	vim.fn.system("raddbg --ipc step_into_line")
end

local function rad_step_out()
	vim.fn.system("raddbg --ipc step_out")
end

local function rad_continue()
	vim.fn.system("raddbg --ipc continue")
end

local function rad_kill()
	vim.fn.system("raddbg --ipc kill_all")
end

local function rad_add_target(path_to_executable)
	vim.fn.system("raddbg --ipc add_target " .. path_to_executable)
	vim.fn.system("raddbg --ipc cancel")
end

local function select_rad_project_file(path)
	rad_project_file_path = path
	-- make sure file exists
	local file = io.open(rad_project_file_path, "r")
	if not file then
		print("rad project file does not exist at path: " .. rad_project_file_path)
		return
	end
	file:close()
	-- get the relative path to the project file
	local cwd = vim.fn.getcwd()
	rel_path_to_project_file = relpath(cwd, rad_project_file_path)
	rel_path_to_project_file = vim.fn.fnamemodify(rel_path_to_project_file, ":h")
	if rad_project_file_path == nil then
		print("rad project file path is nil")
		return
	end
	if rel_path_to_project_file == "." or rel_path_to_project_file == "./" then
		rel_path_to_project_file = ""
	end
end

local function rad_remove_all_breakpoints()
	vim.fn.system("raddbg --ipc clear_breakpoints")
end

local function rad_run()
	vim.fn.system("raddbg --ipc run")
end

local function rad_open()
	if rad_project_file_path == nil then
		print("have not selected a rad project file yet")
		return false
	end
	vim.fn.system("raddbg " .. rad_project_file_path)
end

M.setup = setup
M.add_target = rad_add_target
M.remove_all_breakpoints = rad_remove_all_breakpoints
M.step_over = rad_step_over
M.step_into = rad_step_into
M.step_out = rad_step_out
M.continue = rad_continue
M.kill = rad_kill
M.break_point_menu = goto_rad_breakpoint
M.target_menu = select_rad_target
M.select_project = select_rad_project_file
M.toggle_breakpoint = rad_toggle_breakpoint
M.run = rad_run
M.is_rad_init = is_rad_init
M.open = rad_open
return M
