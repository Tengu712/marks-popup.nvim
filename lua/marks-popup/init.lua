local M = {}
local api = vim.api
local fn = vim.fn

M.config = {
  width = 30,
}

local buf_id = nil
local win_id = nil
local namespace_id = nil

--- Processes a mark object.
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
--- @return table A list of processed marks in the current buffer.
local function get_marks()
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
local function update_mark_window()
  if not buf_id or not api.nvim_buf_is_valid(buf_id) then
    return
  end

  api.nvim_buf_set_option(buf_id, 'modifiable', true)
  api.nvim_buf_set_lines(buf_id, 0, -1, false, {})

  local marks = get_marks()

  if #marks == 0 then
    api.nvim_buf_set_lines(buf_id, 0, 0, false, {"no marks"})
    api.nvim_buf_set_option(buf_id, 'modifiable', false)
    return
  end

  local lines = {}

  for _, mark in ipairs(marks) do
    table.insert(lines, string.format("%s: %s", mark.name, mark.line))
  end

  api.nvim_buf_set_lines(buf_id, 0, 0, false, lines)
  api.nvim_buf_set_option(buf_id, 'modifiable', false)
end

--- Opens a floating window to display marks.
---
--- Creates a new floating window, or reopens it if already open.
--- The window displays all local marks for the current buffer.
local function open_mark_window()
  if win_id and api.nvim_win_is_valid(win_id) then
    api.nvim_win_close(win_id, true)
    win_id = nil
    buf_id = nil
  end

  buf_id = api.nvim_create_buf(false, true)
  api.nvim_buf_set_option(buf_id, 'bufhidden', 'wipe')
  api.nvim_buf_set_option(buf_id, 'filetype', 'marks-popup')
  api.nvim_buf_set_option(buf_id, 'modifiable', false)

  local width = M.config.width
  local height = 10  -- TODO: resize.
  local win_width = api.nvim_win_get_width(0)
  local win_height = api.nvim_win_get_height(0)

  local col = 0
  if M.config.position == "right" then
    col = win_width - width
  end

  local row = math.floor((win_height - height) / 2)
  local opts = {
    relative = 'win',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded'
  }

  win_id = api.nvim_open_win(buf_id, false, opts)
  api.nvim_win_set_option(win_id, 'winhl', 'Normal:Normal')
  api.nvim_win_set_option(win_id, 'number', false)
  api.nvim_win_set_option(win_id, 'relativenumber', false)
  api.nvim_win_set_option(win_id, 'wrap', false)

  update_mark_window()
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
end

--- A function to show the marks window and handle mark navigation.
---
--- @param key_type string The type of mark navigation key to use ("'" or "`").
function M.show_marks(key_type)
  open_mark_window()

  vim.defer_fn(function()
    local next_char = fn.getchar()
    M.close_mark_window()
    local char = fn.nr2char(next_char)
    if char:match("[a-zA-Z0-9]") then
      vim.cmd("normal! " .. key_type .. char)
    end
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
