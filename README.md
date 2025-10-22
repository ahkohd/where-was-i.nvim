<div align="center">

# where-was-i.nvim

A Neovim plugin that creates a visual breadcrumb trail showing where your cursor has been, with smooth color-gradient indicators that fade from bright to dark.

[![Neovim](https://img.shields.io/badge/Neovim%200.10+-green.svg?style=for-the-badge&logo=neovim)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-blue.svg?style=for-the-badge&logo=lua)](http://www.lua.org)

<!-- Demo source: https://github.com/user-attachments/assets/7936371a-cb8e-452f-8c08-e1907e1f1b89  -->
https://github.com/user-attachments/assets/7936371a-cb8e-452f-8c08-e1907e1f1b89

</div>


## Features

- Visual trail showing your recent cursor positions
- Smooth color gradients that fade from newest (bright) to oldest (dark)
- Configurable trail length and appearance
- Flexible color configuration: HSL values, hex colors, or highlight group names
- Debounced cursor tracking for performance
- Per-buffer or global trail modes
- Buffer type and filetype exclusion support
- Automatic cleanup and colorscheme adaptation

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ahkohd/where-was-i.nvim",
  event = "VeryLazy",
  opts = {}
}
```

## Quick Setup

Here's a basic configuration to get started:

```lua
require("where-was-i").setup({
  trail_length = 20,           -- Number of positions to track
  character = "█",             -- Character to display in sign column
  debounce_ms = 150,           -- Debounce time for cursor movement
  active_buffer_only = false,  -- Show trail in all buffers
  color = "Comment",           -- Color for gradient (HSL/hex/highlight group)
})
```

## Configuration

### Default Configuration

```lua
require("where-was-i").setup({
  -- Number of cursor positions to track (must be >= 1)
  trail_length = 20,

  -- Character displayed in the sign column
  character = "█",

  -- Debounce time in milliseconds for cursor movement tracking
  -- Higher values = less frequent updates, better performance
  debounce_ms = 150,

  -- Show trail only in the active buffer (true) or in all buffers (false)
  active_buffer_only = false,

  -- Whether to show trail marker on current cursor line
  -- "previous": only show markers on previous positions (default)
  -- "current": also show marker on current cursor line
  trail_includes = "previous",

  -- Buffer types to exclude from trail tracking
  -- Examples: {"terminal", "prompt", "nofile"}
  excluded_buftypes = {},

  -- Filetypes to exclude from trail tracking
  -- Examples: {"help", "qf", "NvimTree", "TelescopePrompt"}
  excluded_filetypes = {},

  -- Color configuration (see Color Configuration section below)
  color = { h = 0, s = 0, l = 70 }, -- Grayscale by default
})
```

### Color Configuration

The `color` option supports three formats:

#### 1. HSL Table

```lua
color = { h = 200, s = 80, l = 70 }
-- h: Hue (0-360) - Color on the color wheel
-- s: Saturation (0-100) - Color intensity (0 = grayscale)
-- l: Lightness (0-100) - Brightness level
```

**Examples:**
```lua
-- Blue gradient
color = { h = 200, s = 80, l = 70 }

-- Green gradient
color = { h = 120, s = 70, l = 65 }

-- Purple gradient
color = { h = 280, s = 75, l = 70 }

-- Grayscale (no saturation)
color = { h = 0, s = 0, l = 70 }
```

#### 2. Hex Color String

```lua
-- Full hex color
color = "#5fa3d4"

-- Shorthand hex
color = "#5ad"
```

The plugin will convert hex colors to HSL and generate the gradient from there.

#### 3. Highlight Group Name

```lua
-- Use your colorscheme's comment color (recommended for subtle trails)
color = "Comment"

-- Or any other highlight group
color = "Normal"
```

The plugin will automatically extract the foreground color from
the highlight group and update the trail colors whenever you change colorschemes.

### Gradient Behavior

The gradient is automatically generated from your chosen color:
- **Newest position** (position 1): Full brightness + bold
- **Oldest position** (position N): Faded to ~10% of base lightness
- All positions in between: Smooth linear interpolation

## Usage
## Example Configurations

### Minimal Configuration

```lua
require("where-was-i").setup({
  trail_length = 10,
  character = "•",
})
```

### Active Buffer Only

```lua
require("where-was-i").setup({
  trail_length = 15,
  active_buffer_only = true,
  debounce_ms = 200
  color = { h = 180, s = 70, l = 70 },
})
```

### With Exclusions

```lua
require("where-was-i").setup({
  trail_length = 20,
  excluded_buftypes = { "terminal", "prompt" },
  excluded_filetypes = { "help", "qf", "NvimTree", "neo-tree", "TelescopePrompt" },
  color = "#7aa2f7",
})
```

### Commands

```vim
" Clear trail in current buffer
:WhereWasIClear

" Clear trails in all buffers
:WhereWasIClearAll
```

### API

```lua
local where_was_i = require("where-was-i")

-- Clear current buffer's trail
where_was_i.clear()

-- Clear all buffer trails
where_was_i.clear_all()

-- Get trail data (optional buffer number)
where_was_i.get_trail(bufnr)
```
