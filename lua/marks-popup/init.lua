local M = {}
local api = vim.api
local fn = vim.fn

M.config = {
  width = 30,
  max_height = 10,
  offset_x = 2,
  offset_y = 1
}

local buf_id = nil
local win_id = nil
local marks_cache = nil

--- A function to processes a mark object.
---
--- Checks if the mark's name matches [a-zA-Z0-9],
--- and retrieves the corresponding line's content after stripping indentation.
---
--- @param mark table A mark object returned by `vim.fn.getmarklist()`.
--- @return table|nil A table with processed mark data or nil if invalid.
local function process_mark(mark)
  local name = string.sub(mark.mark, 2, 2)

  if not string.match(name, "[a-zA-Z0-9]") then
    return
  end

  local bufnr = mark.pos[1]
  local file = fn.bufname(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local ln = mark.pos[2]
  local cn = mark.pos[3]
  local line = ""
  local lines = api.nvim_buf_get_lines(bufnr, ln - 1, ln, false)
  if #lines > 0 then
    line = lines[1]:gsub("^%s+", "")
  end

  return {
    name = name,
    file = file,
    ln = ln,
    cn = cn,
    line = line
  }
end

--- A function to retrieves and processes local marks for the current buffer.
---
--- @return table|nil A list of processed marks in the current buffer.
local function get_marks()
  local bufnr = api.nvim_get_current_buf()
  if api.nvim_buf_get_option(bufnr, 'buftype') ~= '' then
    return nil
  end

  local raw_marks = fn.getmarklist(fn.bufname('%'))
  local marks = {}

  for _, mark in ipairs(raw_marks) do
    local processed = process_mark(mark)
    if processed ~= nil then
      table.insert(marks, processed)
    end
  end

  return marks
end

--- A function to updates the contents of the mark window.
---
--- If the mark buffer is not available or valid, does nothing.
--- Replaces the buffer content with the current list of marks.
--- If no marks are found, displays a "no marks" message.
---
--- @param marks table Marks.
local function update_mark_window(marks)
  if not buf_id or not api.nvim_buf_is_valid(buf_id) then
    return
  end

  api.nvim_buf_set_option(buf_id, 'modifiable', true)
  api.nvim_buf_set_lines(buf_id, 0, -1, false, {})

  local lines = {}
  if #marks == 0 then
    table.insert(lines, "no marks")
  else
    for _, mark in ipairs(marks) do
      table.insert(lines, string.format("%s: %s", mark.name, mark.line))
    end
  end

  api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  api.nvim_buf_set_option(buf_id, 'modifiable', false)
end

--- A function to opens a floating window to display marks.
---
--- Creates a new floating window, or reopens it if already open.
--- The window displays all local marks for the current buffer.
---
--- @return bool If a window is opened it returns true.
local function open_mark_window()
  if win_id and api.nvim_win_is_valid(win_id) then
    api.nvim_win_close(win_id, true)
    win_id = nil
    buf_id = nil
  end

  local marks = get_marks()
  if marks == nil then
    return false
  end
  marks_cache = marks

  local width = M.config.width
  local height = math.min(M.config.max_height, #marks > 0 and #marks or 1)

  local cursor_pos = api.nvim_win_get_cursor(0)
  local row = cursor_pos[1]
  local col = cursor_pos[2]

  local screenpos = fn.screenpos(0, row, col + 1)
  if screenpos.row == 0 or screenpos.col == 0 then
    screenpos.row = 1
    screenpos.col = 1
    vim.notify("Unable to position popup: cursor is not visible", vim.log.levels.WARN)
  end

  local win_row = screenpos.row + M.config.offset_y
  local win_col = screenpos.col + M.config.offset_x

  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  if win_col + width > screen_width then
    win_col = math.max(0, win_col - width - M.config.offset_x * 2)
  end
  if win_row + height > screen_height then
    win_row = math.max(0, win_row - height - M.config.offset_y)
  end

  buf_id = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
  api.nvim_buf_set_option(buf_id, 'filetype', 'marks-popup')
  api.nvim_buf_set_option(buf_id, 'modifiable', false)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = win_col - 1,
    row = win_row - 1,
    style = 'minimal',
    border = 'rounded'
  }

  win_id = api.nvim_open_win(buf_id, false, opts)
  api.nvim_win_set_option(win_id, 'winhl', 'Normal:Normal')
  api.nvim_win_set_option(win_id, 'number', false)
  api.nvim_win_set_option(win_id, 'relativenumber', false)
  api.nvim_win_set_option(win_id, 'wrap', false)

  update_mark_window(marks)

  return true
end

--- A function to closes the mark window and cleans up resources.
---
--- Closes the floating window if it exists and is valid.
--- Deletes the buffer if it exists and is valid.
function M.close_mark_window()
  if win_id and api.nvim_win_is_valid(win_id) then
    api.nvim_win_close(win_id, true)
    win_id = nil
  end
  if buf_id and api.nvim_buf_is_valid(buf_id) then
    api.nvim_buf_delete(buf_id, { force = true })
    buf_id = nil
  end
  marks_cache = nil
end

--- A function to show the marks window and handle mark navigation.
---
--- @param key_type string The type of mark navigation key to use ("'" or "`").
function M.show_marks(key_type)
  local opened = open_mark_window()
  if not opened then
    return
  end

  vim.defer_fn(function()
    local next_char = fn.getchar()
    M.close_mark_window()

    local char = fn.nr2char(next_char)
    if not char:match("[a-zA-Z0-9]") then
      return
    end

    local exists = false
    local marks = marks_cache ~= nil and marks_cache or get_marks()
    for _, mark in ipairs(marks) do
      if mark.name == char then
        exists = true
        break
      end
    end
    if not exists then
      return
    end

    vim.cmd("normal! " .. key_type .. char)
  end, 0)
end

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  api.nvim_set_keymap('n', "'", [[<cmd>lua require('marks-popup').show_marks("'")<CR>]], { noremap = true, silent = true })
  api.nvim_set_keymap('n', '`', [[<cmd>lua require('marks-popup').show_marks('`')<CR>]], { noremap = true, silent = true })
end

return M
