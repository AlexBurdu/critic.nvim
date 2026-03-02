local M = {}

local ns = vim.api.nvim_create_namespace('critic')

local groups = {
  { name = 'CriticAdd',       fg = 'DiagnosticOk',    bg = 'DiffAdd',    bold = true },
  { name = 'CriticDel',       fg = 'DiagnosticError', bg = 'DiffDelete', strikethrough = true },
  { name = 'CriticHighlight', fg = 'DiagnosticWarn',  bg = 'DiffChange' },
  { name = 'CriticComment',   fg = 'DiagnosticInfo',  bg = 'DiffChange', italic = true },
  { name = 'CriticSubFrom',   fg = 'DiagnosticError', bg = 'DiffDelete', strikethrough = true },
  { name = 'CriticSubTo',     fg = 'DiagnosticOk',    bg = 'DiffAdd',    bold = true },
  -- Comment variants: match parent tag colors, italic
  { name = 'CriticAddComment',       fg = 'DiagnosticOk',    bg = 'DiffAdd',    italic = true },
  { name = 'CriticDelComment',       fg = 'DiagnosticError', bg = 'DiffDelete', italic = true },
  { name = 'CriticHighlightComment', fg = 'DiagnosticWarn',  bg = 'DiffChange', italic = true },
  { name = 'CriticSubComment',       fg = 'DiagnosticOk',    bg = 'DiffAdd',    italic = true },
}

-- Map content hl_group → comment variant for virtual lines
local comment_hl_for = {
  CriticAdd       = 'CriticAddComment',
  CriticDel       = 'CriticDelComment',
  CriticHighlight = 'CriticHighlightComment',
}

-- Multi-line patterns: [%s%S] matches any char including newline
local NL = '[%s%S]'
local simple_patterns = {
  { '{%+%+%s(' .. NL .. '-)%s%+%+}', 'CriticAdd' },
  { '{%-%-%s(' .. NL .. '-)%s%-%-}', 'CriticDel' },
  { '{==%s(' .. NL .. '-)%s==}',     'CriticHighlight' },
}
local comment_pattern = '{>>(' .. NL .. '-)<<}'
local sub_pattern = '{~~%s(' .. NL .. '-)%s~>%s(' .. NL .. '-)%s~~}'

local function resolve_hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function define_highlights()
  for _, g in ipairs(groups) do
    local opts = { default = true }
    if g.fg then opts.fg = resolve_hl(g.fg).fg end
    if g.bg then
      local src = resolve_hl(g.bg)
      opts.bg = src.bg or src.fg
    end
    if g.bold then opts.bold = true end
    if g.italic then opts.italic = true end
    if g.strikethrough then opts.strikethrough = true end
    vim.api.nvim_set_hl(0, g.name, opts)
  end
  -- Neutralise strikethrough from both treesitter and vim regex syntax.
  -- Treesitter and vim's markdown syntax both misinterpret ~~ in CriticMarkup
  -- {~~ as markdown strikethrough, creating spurious spans. We redirect all
  -- strikethrough groups to Normal (link stops @-capture hierarchy walk).
  -- Legitimate ~~text~~ strikethrough is re-applied in highlight_buf Pass 4.
  for _, name in ipairs({
    '@markup.strikethrough.markdown_inline',
    '@markup.strikethrough.markdown',
    '@markup.strikethrough',
    'markdownStrike',
    'markdownStrikeDelimiter',
    'htmlStrike',
  }) do
    vim.api.nvim_set_hl(0, name, { link = 'Normal' })
  end
end

-- Word-wrap a virtual comment line into multiple virt_lines entries
local function wrap_comment(padding, prefix, text, hl_group, max_width)
  local first = padding .. prefix .. text
  if vim.api.nvim_strwidth(first) <= max_width then
    return { { { first, hl_group } } }
  end
  local cont_pad = padding .. string.rep(' ', vim.api.nvim_strwidth(prefix))
  local result = {}
  local cur_pad = padding .. prefix
  local line = cur_pad
  for word in text:gmatch('%S+') do
    local sep = (line == cur_pad) and '' or ' '
    local candidate = line .. sep .. word
    if vim.api.nvim_strwidth(candidate) > max_width and line ~= cur_pad then
      table.insert(result, { { line, hl_group } })
      cur_pad = cont_pad
      line = cont_pad .. word
    else
      line = candidate
    end
  end
  if #line > 0 then
    table.insert(result, { { line, hl_group } })
  end
  return result
end

local function highlight_buf(buf, config)
  local conceal = config.conceal
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local num_lines = #lines
  if num_lines == 0 then return end

  -- Text area width for virtual line wrapping
  local text_width = vim.o.columns
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      local info = vim.fn.getwininfo(win)
      if info and info[1] then
        text_width = vim.api.nvim_win_get_width(win) - info[1].textoff
      end
      break
    end
  end

  local full = table.concat(lines, '\n')

  -- line_off[row_0] = 1-indexed byte offset of that row's start in full
  local line_off = {}
  line_off[0] = 1
  for r = 1, num_lines - 1 do
    line_off[r] = line_off[r - 1] + #lines[r] + 1
  end

  -- Convert 1-indexed byte in full to (row, col) both 0-indexed
  local function to_pos(b)
    for r = num_lines - 1, 0, -1 do
      if b >= line_off[r] then
        return r, b - line_off[r]
      end
    end
    return 0, b - 1
  end

  -- Highlight extmark spanning [b_start, b_end) — 1-indexed bytes in full
  local function set_hl(b_start, b_end, group)
    local sr, sc = to_pos(b_start)
    local er, ec = to_pos(b_end)
    vim.api.nvim_buf_set_extmark(buf, ns, sr, sc, {
      end_row = er, end_col = ec, hl_group = group,
    })
  end

  -- Track concealed byte ranges per row for display-column calculation
  local concealed_on = {}

  local function track_conceal(sr, sc, er, ec)
    for r = sr, er do
      if not concealed_on[r] then concealed_on[r] = {} end
      local cs = (r == sr) and sc or 0
      local ce = (r == er) and ec or #lines[r + 1]
      table.insert(concealed_on[r], { cs, ce })
    end
  end

  -- Conceal extmark spanning [b_start, b_end) and record concealed regions
  local function set_conceal(b_start, b_end)
    local sr, sc = to_pos(b_start)
    local er, ec = to_pos(b_end)
    vim.api.nvim_buf_set_extmark(buf, ns, sr, sc, {
      end_row = er, end_col = ec, conceal = '',
    })
    track_conceal(sr, sc, er, ec)
  end

  -- Display column at (row, col) accounting for concealed bytes on that row
  local function disp_col(row, col)
    local regions = concealed_on[row]
    if not regions then return col end
    local hidden = 0
    for _, r in ipairs(regions) do
      if r[2] <= col then
        hidden = hidden + (r[2] - r[1])
      elseif r[1] < col then
        hidden = hidden + (col - r[1])
      end
    end
    return col - hidden
  end

  -- Content regions for comment anchor alignment (1-indexed byte in full)
  local content_regions = {}
  -- Virtual comments to emit: { row, col, line }
  local virt_comments = {}

  -- Pass 1: Substitutions
  -- Track sub ranges as {start_row, start_col, end_row, end_col} for Pass 4
  local sub_ranges = {}
  local s = 1
  while true do
    local ms, me, cap1, cap2 = full:find(sub_pattern, s)
    if not ms then break end

    local from_s = ms + 4
    local from_e = from_s + #cap1
    local to_s = from_e + 4
    local to_e = to_s + #cap2

    table.insert(content_regions, { to_s, 'CriticSubComment' })

    local sr, sc = to_pos(ms)
    local er, ec = to_pos(me + 1)
    table.insert(sub_ranges, { sr, sc, er, ec })

    if conceal then
      set_hl(from_s, from_e, 'CriticSubFrom')
      set_hl(to_s, to_e, 'CriticSubTo')
      set_conceal(ms, from_s)
      set_conceal(from_e, to_s)
      set_conceal(to_e, me + 1)
    else
      local arrow = from_e + 1
      set_hl(ms, arrow, 'CriticSubFrom')
      set_hl(arrow, me + 1, 'CriticSubTo')
    end
    s = me + 1
  end

  -- Pass 2: Simple patterns (add, del, highlight)
  for _, pat in ipairs(simple_patterns) do
    s = 1
    while true do
      local ms, me, cap = full:find(pat[1], s)
      if not ms then break end

      local content_s = ms + 4
      local content_e = content_s + #cap

      table.insert(content_regions, { ms, comment_hl_for[pat[2]] or 'CriticComment' })

      if conceal then
        set_hl(content_s, content_e, pat[2])
        set_conceal(ms, content_s)
        set_conceal(content_e, me + 1)
      else
        set_hl(ms, me + 1, pat[2])
      end
      s = me + 1
    end
  end

  -- Pass 3: Comments (conceal + virtual lines)
  s = 1
  while true do
    local ms, me, cap = full:find(comment_pattern, s)
    if not ms then break end

    if conceal then
      -- Find nearest preceding content region for alignment and color
      local anchor_byte = 0
      local anchor_hl = 'CriticComment'
      for _, cr in ipairs(content_regions) do
        if cr[1] < ms and cr[1] > anchor_byte then
          anchor_byte = cr[1]
          anchor_hl = cr[2]
        end
      end

      -- Standalone comment alone on its line: show inline instead of
      -- as a virtual line below.
      local comment_sr, comment_sc = to_pos(ms)
      local comment_er = to_pos(me)
      local alone_on_line = false
      if anchor_byte == 0 and comment_sr == comment_er then
        local line = lines[comment_sr + 1]
        local before = comment_sc > 0 and line:sub(1, comment_sc) or ''
        local after_col = comment_sc + (me - ms + 1)
        local after = after_col <= #line and line:sub(after_col + 1) or ''
        alone_on_line = vim.trim(before) == '' and vim.trim(after) == ''
      end

      if alone_on_line then
        -- Conceal {>> and replace with the comment icon
        local open_end = ms + 3
        local osr, osc = to_pos(ms)
        local oer, oec = to_pos(open_end)
        vim.api.nvim_buf_set_extmark(buf, ns, osr, osc, {
          end_row = oer, end_col = oec, conceal = '',
          virt_text = { { config.comment_icon, anchor_hl } },
          virt_text_pos = 'inline',
        })
        track_conceal(osr, osc, oer, oec)
        -- Conceal <<}
        set_conceal(me - 2, me + 1)
        -- Highlight comment content
        set_hl(open_end, me - 2, anchor_hl)
      else
        set_conceal(ms, me + 1)

        local attach_row = to_pos(me)
        local indent = 0
        if anchor_byte > 0 then
          local ar, ac = to_pos(anchor_byte)
          indent = disp_col(ar, ac)
        end

        local flat = vim.trim(cap:gsub('\n', ' '))
        local padding = string.rep(' ', math.max(0, indent))
        local icon_prefix = config.comment_icon .. ' '
        table.insert(virt_comments, {
          row = attach_row,
          col = indent,
          lines = wrap_comment(padding, icon_prefix, flat, anchor_hl, text_width),
        })
      end
    else
      set_hl(ms, me + 1, 'CriticComment')
    end
    s = me + 1
  end

  -- Emit virtual comment lines grouped by attach row
  if #virt_comments > 0 then
    local by_row = {}
    for _, vc in ipairs(virt_comments) do
      if not by_row[vc.row] then by_row[vc.row] = {} end
      table.insert(by_row[vc.row], vc)
    end
    for row, comments in pairs(by_row) do
      table.sort(comments, function(a, b) return a.col < b.col end)
      local virt_lines = {}
      for _, vc in ipairs(comments) do
        for _, vl in ipairs(vc.lines) do
          table.insert(virt_lines, vl)
        end
      end
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        virt_lines = virt_lines,
      })
    end
  end

  -- Pass 4: Re-apply legitimate ~~text~~ strikethrough
  -- We globally disabled @markup.strikethrough.markdown_inline because
  -- treesitter misinterprets ~~ in CriticMarkup {~~ as strikethrough.
  -- Re-apply strikethrough for genuine ~~text~~ that doesn't overlap subs.
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown_inline')
  if ok then
    parser:parse()
    local strike_hl = vim.api.nvim_get_hl(0, { name = '@markup.strikethrough', link = false })
    if not strike_hl.strikethrough then strike_hl = { strikethrough = true } end
    vim.api.nvim_set_hl(0, 'CriticMdStrike', vim.tbl_extend('force', strike_hl, { default = true }))

    for _, tree in ipairs(parser:trees()) do
      local root = tree:root()
      local function apply_strike(node)
        if node:type() == 'strikethrough' then
          local nsr, nsc, ner, nec = node:range()
          local spurious = false
          for _, r in ipairs(sub_ranges) do
            if (nsr < r[3] or (nsr == r[3] and nsc < r[4]))
              and (ner > r[1] or (ner == r[1] and nec > r[2])) then
              spurious = true
              break
            end
          end
          if not spurious then
            vim.api.nvim_buf_set_extmark(buf, ns, nsr, nsc, {
              end_row = ner, end_col = nec, hl_group = 'CriticMdStrike',
            })
          end
        end
        for child in node:iter_children() do apply_strike(child) end
      end
      apply_strike(root)
    end
  end
end

local augroup = vim.api.nvim_create_augroup('CriticHighlight', { clear = true })

function M.enable(config)
  define_highlights()

  if config.conceal then
    vim.api.nvim_create_autocmd('FileType', {
      group = augroup,
      pattern = config.filetypes,
      callback = function(ev)
        vim.wo[0][0].conceallevel = 2
      end,
    })
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = augroup,
    pattern = config.filetypes,
    callback = function(ev)
      highlight_buf(ev.buf, config)
      vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = augroup,
        buffer = ev.buf,
        callback = function()
          highlight_buf(ev.buf, config)
        end,
      })
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = augroup,
    callback = function()
      define_highlights()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          local ft = vim.bo[buf].filetype
          for _, pattern in ipairs(config.filetypes) do
            if ft == pattern then
              highlight_buf(buf, config)
              break
            end
          end
        end
      end
    end,
  })

  -- Highlight any already-open matching buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      for _, pattern in ipairs(config.filetypes) do
        if ft == pattern then
          highlight_buf(buf, config)
          break
        end
      end
    end
  end
end

return M
