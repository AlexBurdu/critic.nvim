# critic.nvim

Neovim plugin for [CriticMarkup](https://criticmarkup.com/) — a plain-text
annotation syntax for tracking edits in prose documents. Provides keybindings
to insert CriticMarkup annotations and extmark-based syntax highlighting with
concealment in markdown buffers.

Supports multi-line tags that span across line breaks.

## CriticMarkup syntax

| Operation    | Syntax                   |
|--------------|--------------------------|
| Addition     | `{++ added text ++}`     |
| Deletion     | `{-- deleted text --}`   |
| Substitution | `{~~ old ~> new ~~}`     |
| Highlight    | `{== highlighted ==}`    |
| Comment      | `{>> comment text <<}`   |

Operations can be combined with inline comments:
```
{-- removed text --}{>> explain why <<}
{~~ old ~> new ~~}{>> explain why <<}
```

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'AlexBurdu/critic.nvim',
  ft = { 'markdown' },
  opts = {},
}
```

With custom keybinding hints for which-key:

```lua
{
  'AlexBurdu/critic.nvim',
  ft = { 'markdown' },
  keys = {
    { '<Leader>cc', desc = 'CriticMarkup: comment' },
    { '<Leader>ch', desc = 'CriticMarkup: highlight' },
    { '<Leader>cH', desc = 'CriticMarkup: highlight + comment' },
    { '<Leader>ci', desc = 'CriticMarkup: insert' },
    { '<Leader>cI', desc = 'CriticMarkup: insert + comment' },
    { '<Leader>cd', desc = 'CriticMarkup: delete' },
    { '<Leader>cD', desc = 'CriticMarkup: delete + comment' },
    { '<Leader>cs', desc = 'CriticMarkup: substitute' },
    { '<Leader>cS', desc = 'CriticMarkup: substitute + comment' },
  },
  opts = {},
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'AlexBurdu/critic.nvim',
  config = function()
    require('critic').setup()
  end,
}
```

### Manual

Clone the repo and add it to your runtimepath:

```bash
git clone https://github.com/AlexBurdu/critic.nvim ~/.local/share/nvim/lazy/critic.nvim
```

```lua
vim.opt.rtp:prepend('~/.local/share/nvim/lazy/critic.nvim')
require('critic').setup()
```

## Usage

### Keybindings

All keybindings use the configured prefix (default `<Leader>c`) and work in
both normal and visual mode.

| Key          | Mode   | Action                            |
|--------------|--------|-----------------------------------|
| `{prefix}c`  | n / v | Comment (highlight char + comment) |
| `{prefix}h`  | n / v | Highlight                          |
| `{prefix}H`  | n / v | Highlight + comment                |
| `{prefix}i`  | n / v | Mark as insertion                  |
| `{prefix}I`  | n / v | Mark as insertion + comment        |
| `{prefix}d`  | n / v | Mark as deletion                   |
| `{prefix}D`  | n / v | Mark as deletion + comment         |
| `{prefix}s`  | n / v | Substitute                         |
| `{prefix}S`  | n / v | Substitute + comment               |

**Normal mode**: operations act on the character under the cursor. On empty
lines, they insert empty markers and enter insert mode.

**Visual mode**: operations wrap the selected text.

### Conceal mode

When `conceal = true` (default), CriticMarkup delimiters are hidden and only
the content is shown with highlighting. Comments are fully concealed inline
and rendered as virtual lines below the annotated text with the configured
`comment_icon`.

Set `conceal = false` to show raw markup with full-range highlighting.

### Examples

Mark text for insertion:
```
This is {++ newly added ++} text.
```

Mark text for deletion:
```
This is {-- removed --} text.
```

Suggest a substitution:
```
This is {~~ old ~> new ~~} text.
```

Highlight with a comment:
```
This is {== important ==}{>> Why is this important? <<} text.
```

Multi-line tags are supported:
```
{++ This addition
spans multiple lines ++}
```

## Configuration

All options with their defaults:

```lua
require('critic').setup({
  -- Keybinding prefix
  prefix = '<Leader>c',

  -- Enable extmark-based syntax highlighting
  highlight = true,

  -- Conceal delimiters and show clean text
  -- When false, raw markup is shown with full-range highlighting
  conceal = true,

  -- Icon shown before virtual comment lines (when conceal = true)
  comment_icon = '💬',

  -- Filetypes to enable highlighting for
  filetypes = { 'markdown' },

  -- Keybinding suffixes (appended to prefix)
  keys = {
    comment              = 'c',
    highlight            = 'h',
    insert               = 'i',
    delete               = 'd',
    substitute           = 's',
    highlight_comment    = 'H',
    insert_comment       = 'I',
    delete_comment       = 'D',
    substitute_comment   = 'S',
  },
})
```

### Disabling keybindings

To use highlighting without any keybindings, set `prefix = false`:

```lua
require('critic').setup({ prefix = false })
```

### Custom highlight groups

Each group derives its colors from standard Neovim highlight groups, making
them portable across colorschemes. All are defined with `default = true`,
so you can override them after `setup()` or in your colorscheme:

| Group              | Foreground from   | Background from | Attributes    |
|--------------------|-------------------|-----------------|---------------|
| `CriticAdd`        | `DiagnosticOk`    | `DiffAdd`       | bold          |
| `CriticDel`        | `DiagnosticError` | `DiffDelete`    | strikethrough |
| `CriticHighlight`  | `DiagnosticWarn`  | `DiffChange`    |               |
| `CriticComment`    | `DiagnosticInfo`  | `DiffChange`    | italic        |
| `CriticSubFrom`    | `DiagnosticError` | `DiffDelete`    | strikethrough |
| `CriticSubTo`      | `DiagnosticOk`    | `DiffAdd`       | bold          |

Override example:

```lua
vim.api.nvim_set_hl(0, 'CriticAdd', { fg = '#00ff00', bg = '#002200', bold = true })
```

## License

Apache 2.0
