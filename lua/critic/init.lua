local M = {}

local defaults = {
  prefix = '<Leader>c',
  highlight = true,
  conceal = true,
  comment_icon = '💬',
  filetypes = { 'markdown' },
  keys = {
    comment = 'c',
    highlight = 'h',
    insert = 'i',
    delete = 'd',
    substitute = 's',
    highlight_comment = 'H',
    insert_comment = 'I',
    delete_comment = 'D',
    substitute_comment = 'S',
  },
}

function M.setup(opts)
  local config = vim.tbl_deep_extend('force', defaults, opts or {})
  require('critic.keymaps').register(config)
  if config.highlight then
    require('critic.highlight').enable(config)
  end
end

return M
