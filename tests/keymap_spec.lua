-- Headless test for CriticMarkup keymap actions (normal + visual mode).
-- Run: nvim --headless -u NONE -l tests/keymap_spec.lua

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

local function eq(got, expected, msg)
  if got ~= expected then
    error((msg or 'mismatch') .. ': expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(got))
  end
end

local function lines_eq(got, expected, msg)
  eq(table.concat(got, '\n'), table.concat(expected, '\n'), msg)
end

local script_dir = debug.getinfo(1, 'S').source:sub(2):match('(.*/)')
local repo_root = script_dir .. '../'
vim.opt.rtp:prepend(repo_root)

-- <Leader> expansion in keymap lhs reads g:mapleader at registration time.
vim.g.mapleader = ' '
require('critic').setup({})

-- Drive keys through nvim's mapping engine (so visual marks set correctly).
local function feed(keys)
  local termcode = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termcode, 'x', false)
end

local function fresh(lines)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  -- Leave any leftover mode (e.g. insert from prior test)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
end

local function buf_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

io.write('-- Normal-mode actions --\n')

test('comment on empty line', function()
  fresh({ '' })
  feed(' cc')
  lines_eq(buf_lines(), { '{>>  <<}' })
end)

test('comment on char', function()
  fresh({ 'a' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' cc')
  lines_eq(buf_lines(), { '{== a ==}{>>  <<}' })
end)

test('highlight on empty line', function()
  fresh({ '' })
  feed(' ch')
  lines_eq(buf_lines(), { '{==  ==}' })
end)

test('highlight on char', function()
  fresh({ 'a' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' ch')
  lines_eq(buf_lines(), { '{== a ==}' })
end)

test('insert on empty line', function()
  fresh({ '' })
  feed(' ci')
  lines_eq(buf_lines(), { '{++  ++}' })
end)

test('delete on char', function()
  fresh({ 'x' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' cd')
  lines_eq(buf_lines(), { '{-- x --}' })
end)

test('substitute on char', function()
  fresh({ 'old' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' cs')
  lines_eq(buf_lines(), { '{~~ o ~>  ~~}ld' })
end)

io.write('-- Visual-mode actions (single line) --\n')

test('v-mode comment wraps single-line selection', function()
  fresh({ 'hello world' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v4l cc') -- select "hello"
  lines_eq(buf_lines(), { '{== hello ==}{>>  <<} world' })
end)

test('v-mode highlight wraps single-line selection', function()
  fresh({ 'hello world' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v4l ch')
  lines_eq(buf_lines(), { '{== hello ==} world' })
end)

test('v-mode insert wraps single-line selection', function()
  fresh({ 'foo bar' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v2l ci') -- select "foo"
  lines_eq(buf_lines(), { '{++ foo ++} bar' })
end)

test('v-mode delete wraps single-line selection', function()
  fresh({ 'foo bar' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v2l cd')
  lines_eq(buf_lines(), { '{-- foo --} bar' })
end)

io.write('-- Visual-mode actions (multi-line) --\n')

test('V-line comment wraps multi-line selection', function()
  fresh({ 'line one', 'line two', 'line three' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('Vj cc') -- linewise select first two lines
  lines_eq(buf_lines(), { '{== line one', 'line two ==}{>>  <<}', 'line three' })
end)

test('V-line highlight wraps multi-line selection', function()
  fresh({ 'line one', 'line two', 'line three' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('Vj ch')
  lines_eq(buf_lines(), { '{== line one', 'line two ==}', 'line three' })
end)

test('v-mode multi-line charwise comment', function()
  fresh({ 'line one', 'line two' })
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  feed('vj4l cc') -- charwise from "one" to "two"
  -- expected: 'line {== one\nline two ==}{>>  <<}'
  local got = buf_lines()
  -- We only assert the original words are preserved + markers present
  local joined = table.concat(got, '\n')
  if not joined:match('{== one') then error('start marker missing: ' .. joined) end
  if not joined:match('two ==}{>>  <<}') then error('end marker missing: ' .. joined) end
end)

test('v-mode substitute wraps selection', function()
  fresh({ 'change me' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v5l cs') -- select "change"
  lines_eq(buf_lines(), { '{~~ change ~>  ~~} me' })
end)

io.write('-- Visual-mode edge cases --\n')

test('V-line cursor mid-line at V press', function()
  fresh({ 'line one', 'line two', 'line three' })
  vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- cursor on space before "one"
  feed('Vj cc')
  lines_eq(buf_lines(), { '{== line one', 'line two ==}{>>  <<}', 'line three' })
end)

test('V-line backward selection (Vk from row 2)', function()
  fresh({ 'line one', 'line two', 'line three' })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  feed('Vk cc')
  lines_eq(buf_lines(), { '{== line one', 'line two ==}{>>  <<}', 'line three' })
end)

test('charwise backward selection (vh)', function()
  fresh({ 'hello world' })
  vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- on 'o' of hello
  feed('v4h ch') -- backward to start
  lines_eq(buf_lines(), { '{== hello ==} world' })
end)

test('v-mode highlight+comment single-line', function()
  fresh({ 'hello world' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v4l cH')
  lines_eq(buf_lines(), { '{== hello ==}{>>  <<} world' })
end)

test('v-mode insert+comment single-line', function()
  fresh({ 'foo bar' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v2l cI')
  lines_eq(buf_lines(), { '{++ foo ++}{>>  <<} bar' })
end)

test('v-mode delete+comment single-line', function()
  fresh({ 'foo bar' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v2l cD')
  lines_eq(buf_lines(), { '{-- foo --}{>>  <<} bar' })
end)

test('v-mode substitute+comment single-line', function()
  fresh({ 'old text' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('v2l cS')
  lines_eq(buf_lines(), { '{~~ old ~>  ~~}{>>  <<} text' })
end)

test('selection=exclusive: V-line still works', function()
  vim.opt.selection = 'exclusive'
  fresh({ 'line one', 'line two', 'line three' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed('Vj cc')
  local result = buf_lines()
  vim.opt.selection = 'inclusive' -- reset
  lines_eq(result, { '{== line one', 'line two ==}{>>  <<}', 'line three' })
end)

io.write('-- Normal-mode edge cases --\n')

test('n-mode highlight+comment on empty line', function()
  fresh({ '' })
  feed(' cH')
  lines_eq(buf_lines(), { '{==  ==}{>>  <<}' })
end)

test('n-mode highlight+comment on char', function()
  fresh({ 'a' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' cH')
  lines_eq(buf_lines(), { '{== a ==}{>>  <<}' })
end)

test('n-mode insert+comment on empty line', function()
  fresh({ '' })
  feed(' cI')
  lines_eq(buf_lines(), { '{++  ++}{>>  <<}' })
end)

test('n-mode delete+comment on char', function()
  fresh({ 'x' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' cD')
  lines_eq(buf_lines(), { '{-- x --}{>>  <<}' })
end)

test('n-mode substitute+comment on empty line', function()
  fresh({ '' })
  feed(' cS')
  lines_eq(buf_lines(), { '{~~  ~>  ~~}{>>  <<}' })
end)

test('n-mode substitute+comment on char', function()
  fresh({ 'old' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(' cS')
  lines_eq(buf_lines(), { '{~~ o ~>  ~~}{>>  <<}ld' })
end)

test('n-mode delete on empty line', function()
  fresh({ '' })
  feed(' cd')
  lines_eq(buf_lines(), { '{--  --}' })
end)

io.write('\n' .. passed .. ' passed, ' .. failed .. ' failed\n')
if failed > 0 then os.exit(1) end
