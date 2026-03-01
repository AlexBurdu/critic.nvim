-- Headless test for multi-line CriticMarkup highlighting
-- Run: nvim --headless -u NONE -l tests/highlight_spec.lua

local ns = vim.api.nvim_create_namespace('critic')
local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write('  PASS: ' .. name .. '\n')
  else
    failed = failed + 1
    io.write('  FAIL: ' .. name .. ': ' .. tostring(err) .. '\n')
  end
end

local function assert_eq(got, expected, msg)
  if got ~= expected then
    error((msg or '') .. ' expected ' .. tostring(expected) .. ', got ' .. tostring(got))
  end
end

-- Load highlight module relative to repo root
local script_dir = debug.getinfo(1, 'S').source:sub(2):match('(.*/)')
local repo_root = script_dir .. '../'
vim.opt.rtp:prepend(repo_root)
local hl = require('critic.highlight')

local function highlight(text_lines, config)
  -- Clear autocmds from prior test
  vim.api.nvim_create_augroup('CriticHighlight', { clear = true })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text_lines)
  hl.enable(config)
  -- Setting filetype triggers the FileType autocmd → highlight_buf
  vim.bo[buf].filetype = 'markdown'
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  return buf, marks
end

local function cleanup(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

local CONCEAL = { conceal = true, comment_icon = '>', filetypes = { 'markdown' } }
local NO_CONCEAL = { conceal = false, comment_icon = '>', filetypes = { 'markdown' } }

-- Helpers to find marks by property
local function find_hl(marks, group)
  for _, m in ipairs(marks) do
    if m[4].hl_group == group then return m end
  end
end

local function count_conceal(marks)
  local n = 0
  for _, m in ipairs(marks) do
    if m[4].conceal == '' then n = n + 1 end
  end
  return n
end

local function find_virt(marks)
  for _, m in ipairs(marks) do
    if m[4].virt_lines then return m end
  end
end

io.write('--- Single-line tags (regression) ---\n')

test('add no-conceal: whole match highlighted', function()
  local buf, marks = highlight({ 'hello {++ added ++} world' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticAdd')
  assert(m, 'CriticAdd not found')
  assert_eq(m[2], 0, 'sr') assert_eq(m[3], 6, 'sc')
  assert_eq(m[4].end_row, 0, 'er') assert_eq(m[4].end_col, 19, 'ec')
  cleanup(buf)
end)

test('add conceal: content highlighted, open/close concealed', function()
  local buf, marks = highlight({ 'hello {++ added ++} world' }, CONCEAL)
  local m = find_hl(marks, 'CriticAdd')
  assert(m, 'CriticAdd not found')
  -- content "added" starts at col 10 (after "hello {++ "), ends at col 15
  assert_eq(m[2], 0, 'sr') assert_eq(m[3], 10, 'sc')
  assert_eq(m[4].end_row, 0, 'er') assert_eq(m[4].end_col, 15, 'ec')
  assert_eq(count_conceal(marks), 2, 'conceal count')
  cleanup(buf)
end)

test('del no-conceal', function()
  local buf, marks = highlight({ '{-- removed --}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticDel')
  assert(m, 'CriticDel not found')
  assert_eq(m[3], 0, 'sc') assert_eq(m[4].end_col, 15, 'ec')
  cleanup(buf)
end)

test('highlight no-conceal', function()
  local buf, marks = highlight({ '{== marked ==}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticHighlight')
  assert(m, 'CriticHighlight not found')
  assert_eq(m[3], 0, 'sc') assert_eq(m[4].end_col, 14, 'ec')
  cleanup(buf)
end)

test('substitution no-conceal', function()
  local buf, marks = highlight({ '{~~ old ~> new ~~}' }, NO_CONCEAL)
  local from = find_hl(marks, 'CriticSubFrom')
  local to = find_hl(marks, 'CriticSubTo')
  assert(from, 'SubFrom not found') assert(to, 'SubTo not found')
  -- SubFrom: start to before ~>
  assert_eq(from[3], 0, 'from sc')
  -- SubTo: from ~> to end
  assert_eq(to[4].end_col, 18, 'to ec')
  cleanup(buf)
end)

test('substitution conceal', function()
  local buf, marks = highlight({ '{~~ old ~> new ~~}' }, CONCEAL)
  local from = find_hl(marks, 'CriticSubFrom')
  local to = find_hl(marks, 'CriticSubTo')
  assert(from, 'SubFrom not found') assert(to, 'SubTo not found')
  -- "old" at col 4..6 (end_col 7 exclusive), "new" at col 11..13 (end_col 14 exclusive)
  assert_eq(from[3], 4, 'from sc') assert_eq(from[4].end_col, 7, 'from ec')
  assert_eq(to[3], 11, 'to sc') assert_eq(to[4].end_col, 14, 'to ec')
  assert_eq(count_conceal(marks), 3, 'conceal count (open + middle + close)')
  cleanup(buf)
end)

test('comment no-conceal', function()
  local buf, marks = highlight({ '{>> note <<}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticComment')
  assert(m, 'CriticComment not found')
  assert_eq(m[3], 0, 'sc') assert_eq(m[4].end_col, 12, 'ec')
  cleanup(buf)
end)

test('comment conceal with virtual line', function()
  local buf, marks = highlight({ 'word {>> note <<}' }, CONCEAL)
  assert_eq(count_conceal(marks), 1, 'conceal count')
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(v[2], 0, 'attach row')
  local text = v[4].virt_lines[1][1][1]
  assert(text:find('> note'), 'virtual line text: ' .. text)
  cleanup(buf)
end)

io.write('\n--- Multi-line tags ---\n')

test('multi-line add no-conceal', function()
  local buf, marks = highlight({ '{++ added', 'text ++}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticAdd')
  assert(m, 'CriticAdd not found')
  assert_eq(m[2], 0, 'sr') assert_eq(m[3], 0, 'sc')
  assert_eq(m[4].end_row, 1, 'er') assert_eq(m[4].end_col, 8, 'ec')
  cleanup(buf)
end)

test('multi-line add conceal', function()
  local buf, marks = highlight({ '{++ added', 'text ++}' }, CONCEAL)
  local m = find_hl(marks, 'CriticAdd')
  assert(m, 'CriticAdd not found')
  -- content "added\ntext" starts row 0 col 4, ends row 1 col 4
  assert_eq(m[2], 0, 'sr') assert_eq(m[3], 4, 'sc')
  assert_eq(m[4].end_row, 1, 'er') assert_eq(m[4].end_col, 4, 'ec')
  assert_eq(count_conceal(marks), 2, 'conceal count')
  cleanup(buf)
end)

test('multi-line comment concealed with flattened virtual line', function()
  local buf, marks = highlight({ 'word {>> long', 'comment <<}' }, CONCEAL)
  assert(count_conceal(marks) >= 1, 'conceal mark')
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  -- Attach row = 1 (where <<} ends)
  assert_eq(v[2], 1, 'attach row')
  local text = v[4].virt_lines[1][1][1]
  assert(text:find('long comment'), 'flattened text: ' .. text)
  cleanup(buf)
end)

test('multi-line substitution no-conceal', function()
  local buf, marks = highlight({ '{~~ old', 'text ~> new ~~}' }, NO_CONCEAL)
  local from = find_hl(marks, 'CriticSubFrom')
  local to = find_hl(marks, 'CriticSubTo')
  assert(from, 'SubFrom not found') assert(to, 'SubTo not found')
  -- SubFrom starts at (0,0)
  assert_eq(from[2], 0, 'from sr') assert_eq(from[3], 0, 'from sc')
  -- SubTo ends at row 1
  assert_eq(to[4].end_row, 1, 'to er') assert_eq(to[4].end_col, 15, 'to ec')
  cleanup(buf)
end)

test('multi-line substitution conceal', function()
  local buf, marks = highlight({ '{~~ old', 'text ~> new ~~}' }, CONCEAL)
  local from = find_hl(marks, 'CriticSubFrom')
  local to = find_hl(marks, 'CriticSubTo')
  assert(from, 'SubFrom not found') assert(to, 'SubTo not found')
  -- "old\ntext" content: row 0 col 4 to row 1 col 4
  assert_eq(from[2], 0, 'from sr') assert_eq(from[3], 4, 'from sc')
  assert_eq(from[4].end_row, 1, 'from er') assert_eq(from[4].end_col, 4, 'from ec')
  -- "new" content on row 1
  assert_eq(to[2], 1, 'to sr')
  assert_eq(to[4].end_row, 1, 'to er')
  assert_eq(count_conceal(marks), 3, 'conceal count')
  cleanup(buf)
end)

io.write('\n--- Comment pattern bug fix ---\n')

test('comment without trailing space before <<', function()
  local buf, marks = highlight({ '{>> no space<<}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticComment')
  assert(m, 'CriticComment not found — pattern failed without trailing space')
  assert_eq(m[3], 0, 'sc') assert_eq(m[4].end_col, 15, 'ec')
  cleanup(buf)
end)

test('comment without trailing space, conceal virtual line', function()
  local buf, marks = highlight({ 'word {>> no space<<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  local text = v[4].virt_lines[1][1][1]
  assert(text:find('> no space'), 'virtual line text: ' .. text)
  cleanup(buf)
end)

test('comment without leading space after >>', function()
  local buf, marks = highlight({ '{>>no space <<}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticComment')
  assert(m, 'CriticComment not found — pattern failed without leading space')
  cleanup(buf)
end)

test('comment with no spaces at all', function()
  local buf, marks = highlight({ '{>>nospaces<<}' }, NO_CONCEAL)
  local m = find_hl(marks, 'CriticComment')
  assert(m, 'CriticComment not found — pattern failed with no spaces')
  cleanup(buf)
end)

io.write('\n--- Comment anchor alignment ---\n')

test('comment after substitution anchors under replacement text', function()
  -- "hello {~~ old ~> new ~~} {>> note <<}"
  -- With conceal, display: "hello oldnew"
  -- "old" at display col 6, "new" at display col 9
  -- Comment should anchor under "new" (col 9), not "old" (col 6)
  local buf, marks = highlight({ 'hello {~~ old ~> new ~~} {>> note <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  local text = v[4].virt_lines[1][1][1]
  -- Count leading spaces to verify indent
  local leading = #text:match('^( *)')
  -- "hello " = 6 visible chars, "old" = 3, so "new" starts at display col 9
  assert_eq(leading, 9, 'indent should be 9 (under "new"), got ' .. leading)
  cleanup(buf)
end)

test('comment after add anchors under added text', function()
  local buf, marks = highlight({ 'hello {++ added ++} {>> note <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  local text = v[4].virt_lines[1][1][1]
  local leading = #text:match('^( *)')
  -- "hello " = 6 visible chars, content starts at display col 6
  assert_eq(leading, 6, 'indent should be 6 (under "added")')
  cleanup(buf)
end)

io.write('\n--- Comment variant colors ---\n')

test('comment after add uses CriticAddComment', function()
  local buf, marks = highlight({ '{++ added ++} {>> note <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(v[4].virt_lines[1][1][2], 'CriticAddComment', 'hl_group')
  cleanup(buf)
end)

test('comment after del uses CriticDelComment', function()
  local buf, marks = highlight({ '{-- removed --} {>> note <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(v[4].virt_lines[1][1][2], 'CriticDelComment', 'hl_group')
  cleanup(buf)
end)

test('comment after highlight uses CriticHighlightComment', function()
  local buf, marks = highlight({ '{== marked ==} {>> note <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(v[4].virt_lines[1][1][2], 'CriticHighlightComment', 'hl_group')
  cleanup(buf)
end)

test('comment after substitution uses CriticSubComment', function()
  local buf, marks = highlight({ '{~~ old ~> new ~~} {>> note <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(v[4].virt_lines[1][1][2], 'CriticSubComment', 'hl_group')
  cleanup(buf)
end)

test('standalone comment uses CriticComment', function()
  local buf, marks = highlight({ '{>> standalone <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(v[4].virt_lines[1][1][2], 'CriticComment', 'hl_group')
  cleanup(buf)
end)

io.write('\n--- Strikethrough bleed prevention ---\n')

test('@markup.strikethrough.markdown_inline links to Normal', function()
  local hl_info = vim.api.nvim_get_hl(0, { name = '@markup.strikethrough.markdown_inline' })
  assert(hl_info.link, 'should have a link')
  assert_eq(hl_info.link, 'Normal', 'should link to Normal')
  cleanup(vim.api.nvim_create_buf(false, true))
end)

io.write('\n--- Virtual line wrapping ---\n')

test('short comment fits in one virtual line', function()
  local buf, marks = highlight({ 'word {>> short <<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert_eq(#v[4].virt_lines, 1, 'should be 1 virtual line')
  cleanup(buf)
end)

test('long comment wraps to multiple virtual lines', function()
  -- Force a narrow width by using a config-level test
  -- The headless nvim has vim.o.columns typically 80
  local long = string.rep('word ', 30)  -- 150 chars
  local buf, marks = highlight({ '{>> ' .. long .. '<<}' }, CONCEAL)
  local v = find_virt(marks)
  assert(v, 'virtual line not found')
  assert(#v[4].virt_lines > 1, 'expected multiple virt lines, got ' .. #v[4].virt_lines)
  -- All lines should have CriticComment highlight
  for i, vl in ipairs(v[4].virt_lines) do
    assert_eq(vl[1][2], 'CriticComment', 'hl_group on line ' .. i)
  end
  cleanup(buf)
end)

io.write('\n--- Pass 4: Legitimate strikethrough re-application ---\n')

test('legitimate ~~text~~ gets CriticMdStrike with subs present', function()
  -- Two subs + legitimate strikethrough
  local buf, marks = highlight({
    '{~~ old ~> new ~~} text.',
    '',
    'Legit ~~struck~~ rest.',
    '',
    'Another {~~ foo ~> bar ~~} end.',
  }, CONCEAL)
  local strike_marks = {}
  for _, m in ipairs(marks) do
    if m[4].hl_group == 'CriticMdStrike' then
      table.insert(strike_marks, m)
    end
  end
  -- Should have at least one CriticMdStrike on the legitimate ~~struck~~
  assert(#strike_marks > 0, 'expected CriticMdStrike marks for legitimate strikethrough')
  -- All should be on line 2 (0-indexed)
  local found_line2 = false
  for _, m in ipairs(strike_marks) do
    if m[2] == 2 then found_line2 = true end
  end
  assert(found_line2, 'CriticMdStrike should be on line with ~~struck~~')
  cleanup(buf)
end)

test('CriticMdStrike applied even without substitutions', function()
  -- Pass 4 always runs since we globally disabled treesitter strikethrough
  local buf, marks = highlight({ '{++ added ++} ~~struck~~' }, CONCEAL)
  local strike_marks = {}
  for _, m in ipairs(marks) do
    if m[4].hl_group == 'CriticMdStrike' then
      table.insert(strike_marks, m)
    end
  end
  assert(#strike_marks > 0, 'CriticMdStrike should exist for legitimate ~~text~~')
  cleanup(buf)
end)

io.write('\n--- Summary ---\n')
io.write(string.format('%d passed, %d failed\n', passed, failed))
if failed > 0 then
  vim.cmd('cquit! 1')
else
  vim.cmd('qall!')
end
