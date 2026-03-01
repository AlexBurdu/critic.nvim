# critic.nvim

Neovim plugin for [CriticMarkup](https://criticmarkup.com/) — a plain-text
annotation syntax for tracking edits in prose documents. Provides keybindings
to insert CriticMarkup annotations and extmark-based syntax highlighting with
concealment in markdown buffers.

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

### lazy.nvim

```lua
{
  dir = '~/projects/critic.nvim',  -- or a GitHub URL
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
  config = function()
    require('critic').setup()
  end,
}
```

### packer.nvim

```lua
use {
  '~/projects/critic.nvim',
  config = function()
    require('critic').setup()
  end,
}
```

### Manual

Clone the repo and add it to your runtimepath:

```lua
vim.opt.rtp:prepend('~/projects/critic.nvim')
require('critic').setup()
```

## Configuration

```lua
require('critic').setup({
  prefix = '<Leader>c',           -- keybinding prefix (default)
  highlight = true,               -- enable syntax highlighting (default)
  conceal = true,                 -- conceal delimiters, show clean text (default)
  comment_icon = '💬',            -- icon for virtual comment lines (default)
  filetypes = { 'markdown' },    -- filetypes to highlight (default)
  keys = {                        -- keybinding suffixes (appended to prefix)
    comment = 'c',                -- comment
    highlight = 'h',              -- highlight
    insert = 'i',                 -- insert
    delete = 'd',                 -- delete
    substitute = 's',             -- substitute
    highlight_comment = 'H',      -- highlight + comment
    insert_comment = 'I',         -- insert + comment
    delete_comment = 'D',         -- delete + comment
    substitute_comment = 'S',     -- substitute + comment
  },
})
```

## Keybindings

All keybindings use the configured prefix (default `<Leader>c`) plus
the key suffix. Both normal and visual mode are supported.

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

In normal mode, operations act on the character under the cursor. On
empty lines, they insert empty markers and enter insert mode.

In visual mode, operations wrap the selected text.

## Conceal

When `conceal = true` (default), CriticMarkup delimiters are hidden and
only the content is shown with highlighting. Comments are fully concealed
inline and rendered as virtual lines below the annotated text with the
configured `comment_icon`.

Set `conceal = false` to show raw markup with full-range highlighting.

## Highlight groups

Each group derives its colors from standard neovim highlight groups, making
them portable across colorschemes. All are defined with `default = true`,
so you can override them in your colorscheme or after `setup()`:

| Group            | Foreground from   | Background from | Attributes    |
|------------------|-------------------|-----------------|---------------|
| `CriticAdd`      | `DiagnosticOk`    | `DiffAdd`       | bold          |
| `CriticDel`      | `DiagnosticError` | `DiffDelete`    | strikethrough |
| `CriticHighlight`| `DiagnosticWarn`  | `DiffChange`    |               |
| `CriticComment`  | `DiagnosticInfo`  | `DiffChange`    | italic        |
| `CriticSubFrom`  | `DiagnosticError` | `DiffDelete`    | strikethrough |
| `CriticSubTo`    | `DiagnosticOk`    | `DiffAdd`       | bold          |

## Examples

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

Delete with a reason:
```
This is {-- redundant --}{>> Already covered in section 2 <<} text.
```
