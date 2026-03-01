local M = {}

local function wrap_char(prefix, suffix)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local char = line:sub(col + 1, col + 1)
  if char == '' then return end
  local before = line:sub(1, col)
  local after = line:sub(col + 2)
  vim.api.nvim_set_current_line(before .. prefix .. char .. suffix .. after)
  vim.api.nvim_win_set_cursor(0, { row, col + #prefix })
end

local function wrap_selection(prefix, suffix, cursor_from_end)
  vim.cmd('normal! "zy')
  local text = vim.fn.getreg('z')
  local _, sr, sc, _ = unpack(vim.fn.getpos("'<"))
  local _, er, ec, _ = unpack(vim.fn.getpos("'>"))
  local end_line = vim.api.nvim_buf_get_lines(0, er - 1, er, true)[1]
  ec = math.min(ec, #end_line)
  text = text:gsub('\n$', '')
  local lines = vim.split(text, '\n', { plain = true })
  lines[1] = prefix .. lines[1]
  lines[#lines] = lines[#lines] .. suffix
  vim.api.nvim_buf_set_text(0, sr - 1, sc - 1, er - 1, ec, lines)
  local end_row = sr - 1 + #lines - 1
  local end_col
  if #lines == 1 then
    end_col = (sc - 1) + #lines[1] - cursor_from_end
  else
    end_col = #lines[#lines] - cursor_from_end
  end
  vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
  vim.cmd('startinsert')
end

-- Helper: wrap char under cursor, then append {>> comment <<}
local function wrap_char_comment(prefix, suffix)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local char = line:sub(col + 1, col + 1)
  local before = line:sub(1, col)
  if char == '' then
    local inserted = prefix .. ' ' .. suffix .. '{>>  <<}'
    vim.api.nvim_set_current_line(before .. inserted)
    vim.api.nvim_win_set_cursor(0, { row, col + #inserted - #'<<}' - 1 })
  else
    local after = line:sub(col + 2)
    local inserted = prefix .. char .. suffix .. '{>>  <<}'
    vim.api.nvim_set_current_line(before .. inserted .. after)
    vim.api.nvim_win_set_cursor(0, { row, col + #inserted - #'<<}' - 1 })
  end
  vim.cmd('startinsert')
end

-- Helper: insert empty markers at cursor with optional comment
local function insert_at_cursor(markers, comment, cursor_offset)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  local inserted = comment and (markers .. '{>>  <<}') or markers
  vim.api.nvim_set_current_line(before .. inserted .. after)
  vim.api.nvim_win_set_cursor(0, { row, col + cursor_offset })
  vim.cmd('startinsert')
end

-- Helper: wrap char or insert empty, with optional comment, enter insert mode
local function char_or_empty(prefix, suffix, comment)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local char = line:sub(col + 1, col + 1)
  local before = line:sub(1, col)
  if char == '' then
    local markers = prefix .. ' ' .. suffix
    if comment then
      local inserted = markers .. '{>>  <<}'
      vim.api.nvim_set_current_line(before .. inserted)
      vim.api.nvim_win_set_cursor(0, { row, col + #inserted - #'<<}' - 1 })
    else
      vim.api.nvim_set_current_line(before .. markers)
      vim.api.nvim_win_set_cursor(0, { row, col + #prefix })
    end
    vim.cmd('startinsert')
  elseif comment then
    wrap_char_comment(prefix, suffix)
  else
    wrap_char(prefix, suffix)
  end
end

function M.register(config)
  local p = config.prefix
  local k = config.keys

  -- Comment: {>> comment <<} (or {== char ==}{>> comment <<} on a char)
  vim.keymap.set('n', p .. k.comment, function()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local char = line:sub(col + 1, col + 1)
    local before = line:sub(1, col)
    if char == '' then
      vim.api.nvim_set_current_line(before .. '{>>  <<}')
      vim.api.nvim_win_set_cursor(0, { row, col + #'{>> ' })
    else
      local after = line:sub(col + 2)
      local marker = '{== ' .. char .. ' ==}{>>  <<}'
      vim.api.nvim_set_current_line(before .. marker .. after)
      vim.api.nvim_win_set_cursor(0, { row, col + #'{== ' + #char + #' ==}{>> ' })
    end
    vim.cmd('startinsert')
  end, { desc = 'CriticMarkup: comment' })

  vim.keymap.set('v', p .. k.comment, function()
    wrap_selection('{== ', ' ==}{>>  <<}', 4)
  end, { desc = 'CriticMarkup: highlight + comment' })

  -- Highlight: {== text ==}
  vim.keymap.set('n', p .. k.highlight, function()
    char_or_empty('{== ', ' ==}', false)
  end, { desc = 'CriticMarkup: highlight' })

  vim.keymap.set('v', p .. k.highlight, function()
    wrap_selection('{== ', ' ==}', 1)
  end, { desc = 'CriticMarkup: highlight' })

  -- Highlight + comment: {== text ==}{>> comment <<}
  vim.keymap.set('n', p .. k.highlight_comment, function()
    char_or_empty('{== ', ' ==}', true)
  end, { desc = 'CriticMarkup: highlight + comment' })

  vim.keymap.set('v', p .. k.highlight_comment, function()
    wrap_selection('{== ', ' ==}{>>  <<}', 4)
  end, { desc = 'CriticMarkup: highlight + comment' })

  -- Insert: {++ text ++}
  vim.keymap.set('n', p .. k.insert, function()
    insert_at_cursor('{++  ++}', false, #'{++ ')
  end, { desc = 'CriticMarkup: insert' })

  vim.keymap.set('v', p .. k.insert, function()
    wrap_selection('{++ ', ' ++}', 1)
  end, { desc = 'CriticMarkup: insert' })

  -- Insert + comment: {++ text ++}{>> comment <<}
  vim.keymap.set('n', p .. k.insert_comment, function()
    insert_at_cursor('{++  ++}', true, #'{++ ')
  end, { desc = 'CriticMarkup: insert + comment' })

  vim.keymap.set('v', p .. k.insert_comment, function()
    wrap_selection('{++ ', ' ++}{>>  <<}', 4)
  end, { desc = 'CriticMarkup: insert + comment' })

  -- Delete: {-- text --}
  vim.keymap.set('n', p .. k.delete, function()
    char_or_empty('{-- ', ' --}', false)
  end, { desc = 'CriticMarkup: delete' })

  vim.keymap.set('v', p .. k.delete, function()
    wrap_selection('{-- ', ' --}', 1)
  end, { desc = 'CriticMarkup: delete' })

  -- Delete + comment: {-- text --}{>> comment <<}
  vim.keymap.set('n', p .. k.delete_comment, function()
    char_or_empty('{-- ', ' --}', true)
  end, { desc = 'CriticMarkup: delete + comment' })

  vim.keymap.set('v', p .. k.delete_comment, function()
    wrap_selection('{-- ', ' --}{>>  <<}', 4)
  end, { desc = 'CriticMarkup: delete + comment' })

  -- Substitute: {~~ old ~> new ~~}
  vim.keymap.set('n', p .. k.substitute, function()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local char = line:sub(col + 1, col + 1)
    local before = line:sub(1, col)
    if char == '' then
      vim.api.nvim_set_current_line(before .. '{~~  ~>  ~~}')
      vim.api.nvim_win_set_cursor(0, { row, col + #'{~~ ' })
    else
      local after = line:sub(col + 2)
      vim.api.nvim_set_current_line(before .. '{~~ ' .. char .. ' ~>  ~~}' .. after)
      vim.api.nvim_win_set_cursor(0, { row, col + #'{~~ ' + #char + #' ~> ' })
    end
    vim.cmd('startinsert')
  end, { desc = 'CriticMarkup: substitute' })

  vim.keymap.set('v', p .. k.substitute, function()
    wrap_selection('{~~ ', ' ~>  ~~}', 4)
  end, { desc = 'CriticMarkup: substitute' })

  -- Substitute + comment: {~~ old ~> new ~~}{>> comment <<}
  vim.keymap.set('n', p .. k.substitute_comment, function()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_get_current_line()
    local char = line:sub(col + 1, col + 1)
    local before = line:sub(1, col)
    if char == '' then
      local inserted = '{~~  ~>  ~~}{>>  <<}'
      vim.api.nvim_set_current_line(before .. inserted)
      vim.api.nvim_win_set_cursor(0, { row, col + #'{~~ ' })
    else
      local after = line:sub(col + 2)
      local inserted = '{~~ ' .. char .. ' ~>  ~~}{>>  <<}'
      vim.api.nvim_set_current_line(before .. inserted .. after)
      vim.api.nvim_win_set_cursor(0, { row, col + #'{~~ ' + #char + #' ~> ' })
    end
    vim.cmd('startinsert')
  end, { desc = 'CriticMarkup: substitute + comment' })

  vim.keymap.set('v', p .. k.substitute_comment, function()
    wrap_selection('{~~ ', ' ~>  ~~}{>>  <<}', 12)
  end, { desc = 'CriticMarkup: substitute + comment' })
end

return M
