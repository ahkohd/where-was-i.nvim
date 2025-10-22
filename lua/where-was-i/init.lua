-- luacheck: globals vim

-- where-was-i.nvim - Visual breadcrumb trail for cursor movement
-- Shows where you've been in a buffer with color-gradient indicators

local M = {}

-- Default configuration
local config = {
  trail_length = 20,
  character = "█",
  debounce_ms = 150,
  active_buffer_only = false, -- Show trail in all buffers by default
  trail_includes = "previous", -- "previous" | "current" - whether to show trail on current line
  excluded_buftypes = {}, -- Buffer types to exclude (e.g., {"terminal", "prompt", "nofile"})
  excluded_filetypes = {}, -- Filetypes to exclude (e.g., {"help", "qf"})
  color = { h = 0, s = 0, l = 70 }, -- HSL color for gradient generation (grayscale by default)
}

-- Buffer-local trail storage
-- trails[bufnr] = { {line = number, sign_id = number}, ... }
local trails = {}
local debounce_timers = {}
local sign_namespace = "where_was_i"
local next_sign_id = 1
local last_active_buffer = nil

-- Helper: Generate unique sign ID
local function get_sign_id()
  local id = next_sign_id
  next_sign_id = next_sign_id + 1
  return id
end

-- Helper: Convert HSL to RGB
-- Standard HSL to RGB conversion algorithm
-- Input: H in [0, 360], S in [0, 100], L in [0, 100]
-- Output: RGB values in [0, 255]
local function hsl_to_rgb(h, s, l)
  -- Normalize to [0, 1] range
  h = h / 360
  s = s / 100
  l = l / 100

  local r, g, b

  if s == 0 then
    -- Achromatic (gray) - no saturation means R=G=B
    r, g, b = l, l, l
  else
    -- Helper function to convert hue to RGB component
    local function hue_to_rgb(p, q, t)
      if t < 0 then
        t = t + 1
      end
      if t > 1 then
        t = t - 1
      end
      if t < 1 / 6 then
        return p + (q - p) * 6 * t
      end
      if t < 1 / 2 then
        return q
      end
      if t < 2 / 3 then
        return p + (q - p) * (2 / 3 - t) * 6
      end
      return p
    end

    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q

    r = hue_to_rgb(p, q, h + 1 / 3)
    g = hue_to_rgb(p, q, h)
    b = hue_to_rgb(p, q, h - 1 / 3)
  end

  -- Convert to [0, 255] range and round
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

-- Helper: Convert RGB to hex
local function rgb_to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

-- Helper: Convert hex to RGB
local function hex_to_rgb(hex)
  hex = hex:gsub("#", "")
  if #hex == 3 then
    -- Convert shorthand hex (e.g., #fff) to full form
    hex = hex:gsub("(.)", "%1%1")
  end

  -- Validate hex length after processing
  if #hex ~= 6 then
    return nil, nil, nil
  end

  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)

  -- Validate all conversions succeeded
  if not (r and g and b) then
    return nil, nil, nil
  end

  return r, g, b
end

-- Helper: Convert RGB to HSL
-- Standard RGB to HSL conversion algorithm
-- Input: RGB values in [0, 255]
-- Output: H in [0, 360], S in [0, 100], L in [0, 100]
local function rgb_to_hsl(r, g, b)
  -- Normalize to [0, 1] range
  r, g, b = r / 255, g / 255, b / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local h, s, l = 0, 0, (max + min) / 2

  if max ~= min then
    local d = max - min
    -- Calculate saturation based on lightness
    s = l > 0.5 and d / (2 - max - min) or d / (max + min)

    -- Calculate hue based on which component is maximum
    if max == r then
      h = (g - b) / d + (g < b and 6 or 0)
    elseif max == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
    h = h / 6
  end

  -- Convert to standard ranges and round
  return math.floor(h * 360 + 0.5), math.floor(s * 100 + 0.5), math.floor(l * 100 + 0.5)
end

-- Helper: Extract color from highlight group
local function get_hl_color(hl_name)
  local hl = vim.api.nvim_get_hl(0, { name = hl_name, link = false })
  if hl and hl.fg then
    -- Convert integer color to hex
    local hex = string.format("#%06x", hl.fg)
    return hex
  end
  return nil
end

-- Helper: Check if string looks like a hex color
local function is_hex_color(str)
  -- Match #xxx, #xxxxxx, xxx, or xxxxxx (where x is hex digit)
  return str:match("^#?%x%x%x$") ~= nil or str:match("^#?%x%x%x%x%x%x$") ~= nil
end

-- Helper: Convert hex string to HSL
local function hex_to_hsl(hex)
  local r, g, b = hex_to_rgb(hex)
  if not (r and g and b) then
    return nil, nil, nil
  end
  return rgb_to_hsl(r, g, b)
end

-- Helper: Normalize color config to HSL format
local function normalize_color_to_hsl(color)
  -- If already HSL table, return as is
  if type(color) == "table" and color.h and color.s and color.l then
    return { h = color.h, s = color.s, l = color.l }
  end

  if type(color) ~= "string" then
    return nil
  end

  -- Try as hex color first
  if is_hex_color(color) then
    local h, s, l = hex_to_hsl(color)
    if h then
      return { h = h, s = s, l = l }
    else
      vim.notify("where-was-i: Invalid hex color format", vim.log.levels.WARN)
      return nil
    end
  end

  -- Try as highlight group
  local hex = get_hl_color(color)
  if not hex then
    vim.notify(
      string.format("where-was-i: Could not extract color from highlight group '%s'", color),
      vim.log.levels.WARN
    )
    return nil
  end

  local h, s, l = hex_to_hsl(hex)
  if h then
    return { h = h, s = s, l = l }
  else
    vim.notify(
      string.format("where-was-i: Invalid color extracted from highlight group '%s'", color),
      vim.log.levels.WARN
    )
    return nil
  end
end

-- Helper: Generate gradient colors from base HSL color
local function generate_gradient_colors()
  local colors = {}
  local base_h = config.color.h
  local base_s = config.color.s
  local base_l = config.color.l

  -- Generate colors from bright (high L) to dark (low L)
  for i = 1, config.trail_length do
    -- Interpolate from 0 (newest) to 1 (oldest)
    -- Guard against division by zero when trail_length = 1
    local t = config.trail_length > 1 and (i - 1) / (config.trail_length - 1) or 0
    -- Interpolate lightness from base_l down to a minimum (10% of base, min 5)
    local min_l = math.max(5, base_l * 0.1)
    local l = base_l * (1 - t) + min_l * t  -- Linear interpolation

    local r, g, b = hsl_to_rgb(base_h, base_s, l)
    colors[i] = rgb_to_hex(r, g, b)
  end

  return colors
end

-- Helper: Define signs with color gradient
local function define_signs()
  local colors = generate_gradient_colors()

  -- Define signs for the full trail length
  for i = 1, config.trail_length do
    local hl_name = string.format("WhereWasI%d", i)
    local sign_name = string.format("WhereWasI%d", i)

    -- Define highlight group (will override existing)
    vim.api.nvim_set_hl(0, hl_name, {
      fg = colors[i],
      bold = i == 1, -- Make newest position bold
    })

    -- Define sign
    vim.fn.sign_define(sign_name, {
      text = config.character,
      texthl = hl_name,
    })
  end
end

-- Helper: Get or create trail for buffer
local function get_trail(bufnr)
  if not trails[bufnr] then
    trails[bufnr] = {}
  end
  return trails[bufnr]
end

-- Helper: Remove oldest sign from buffer
local function remove_oldest_sign(bufnr, trail)
  if #trail > 0 then
    local oldest = table.remove(trail) -- Remove from end (oldest)
    if oldest.sign_id then
      vim.fn.sign_unplace(sign_namespace, {
        buffer = bufnr,
        id = oldest.sign_id,
      })
    end
  end
end

-- Helper: Get current cursor line for buffer
local function get_current_line(bufnr)
  -- Check current window first (handles multiple splits correctly)
  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(current_win) == bufnr then
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, current_win)
    if ok then
      return cursor[1]
    end
  end

  -- Fallback: find any window showing this buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
      if ok then
        return cursor[1]
      end
    end
  end
  return nil
end

-- Helper: Hide signs for a buffer
local function hide_signs(bufnr)
  vim.fn.sign_unplace(sign_namespace, { buffer = bufnr })
end

-- Helper: Show signs for a buffer
local function show_signs(bufnr)
  local trail = trails[bufnr]
  if not trail or #trail == 0 then
    return
  end

  -- Get current line to skip if trail_includes is "previous"
  local current_line = nil
  if config.trail_includes == "previous" then
    current_line = get_current_line(bufnr)
  end

  -- Place all signs for this buffer
  for idx, pos in ipairs(trail) do
    -- Skip current line if trail_includes is "previous"
    if not (current_line and pos.line == current_line) then
      local sign_name = string.format("WhereWasI%d", idx)
      if not pos.sign_id then
        pos.sign_id = get_sign_id()
      end

      -- Protect against invalid buffer/line numbers
      local ok = pcall(vim.fn.sign_place, pos.sign_id, sign_namespace, sign_name, bufnr, {
        lnum = pos.line,
        priority = 10,
      })
      if not ok then
        -- Sign placement failed, possibly invalid line number or buffer
        -- Sign will be missing but won't crash
      end
    end
  end
end

-- Helper: Update sign indices after adding new position
local function update_sign_indices(bufnr, trail, current_line)
  -- Clear all existing signs
  vim.fn.sign_unplace(sign_namespace, { buffer = bufnr })

  -- Re-place all signs with updated colors (only if should be visible)
  if config.active_buffer_only and bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end

  -- Calculate current_line only if not provided (avoid redundant lookups)
  if current_line == nil and config.trail_includes == "previous" then
    current_line = get_current_line(bufnr)
  end

  for idx, pos in ipairs(trail) do
    -- Skip current line if trail_includes is "previous"
    if not (current_line and pos.line == current_line) then
      local sign_name = string.format("WhereWasI%d", idx)
      pos.sign_id = get_sign_id()

      -- Protect against invalid buffer/line numbers
      local ok = pcall(vim.fn.sign_place, pos.sign_id, sign_namespace, sign_name, bufnr, {
        lnum = pos.line,
        priority = 10,
      })
      if not ok then
        -- Sign placement failed, possibly invalid line number or buffer
        -- Sign will be missing but won't crash
      end
    end
  end
end

-- Main: Record cursor position
local function record_position(bufnr, line)
  local trail = get_trail(bufnr)

  -- Check if this line is already the most recent position
  if #trail > 0 and trail[1].line == line then
    return
  end

  -- Remove this line from trail if it exists elsewhere
  for i = #trail, 1, -1 do
    if trail[i].line == line then
      local pos = table.remove(trail, i)
      if pos.sign_id then
        vim.fn.sign_unplace(sign_namespace, {
          buffer = bufnr,
          id = pos.sign_id,
        })
      end
    end
  end

  -- Add new position at the front
  table.insert(trail, 1, { line = line, sign_id = nil })

  -- Remove oldest if trail exceeds limit
  if #trail > config.trail_length then
    remove_oldest_sign(bufnr, trail)
  end

  -- Calculate current line once to avoid redundant window iteration
  local current_line = nil
  if config.trail_includes == "previous" then
    current_line = get_current_line(bufnr)
  end

  -- Update all sign indices and colors
  update_sign_indices(bufnr, trail, current_line)
end

-- Main: Debounced cursor handler
local function on_cursor_moved()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Safely get cursor position
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok then
    return
  end
  local line = cursor[1]

  -- Check if buffer should be excluded (use modern API)
  local buftype = vim.bo[bufnr].buftype
  local filetype = vim.bo[bufnr].filetype

  for _, excluded_type in ipairs(config.excluded_buftypes) do
    if buftype == excluded_type then
      return
    end
  end

  for _, excluded_ft in ipairs(config.excluded_filetypes) do
    if filetype == excluded_ft then
      return
    end
  end

  -- Cancel existing timer for this buffer
  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
  end

  -- Set new debounced timer - capture bufnr but get fresh cursor position on fire
  debounce_timers[bufnr] = vim.fn.timer_start(config.debounce_ms, function()
    debounce_timers[bufnr] = nil

    -- Validate buffer is still valid
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- Get fresh cursor position at time of recording
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then
      return  -- Buffer not visible in any window
    end

    local ok_cursor, current_cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if ok_cursor then
      record_position(bufnr, current_cursor[1])
    end
  end)
end

-- Main: Clear trail for buffer
local function clear_buffer_trail(bufnr)
  vim.fn.sign_unplace(sign_namespace, { buffer = bufnr })
  trails[bufnr] = nil

  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
    debounce_timers[bufnr] = nil
  end
end

-- API: Clear current buffer's trail
function M.clear()
  local bufnr = vim.api.nvim_get_current_buf()
  clear_buffer_trail(bufnr)
end

-- API: Clear all trails
function M.clear_all()
  for bufnr, _ in pairs(trails) do
    clear_buffer_trail(bufnr)
  end
end

-- API: Get trail for debugging
function M.get_trail(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return get_trail(bufnr)
end

-- Setup function
function M.setup(opts)
  -- Merge user config with defaults
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- Normalize and validate color config
  if not config.color then
    vim.notify("where-was-i: color configuration is required", vim.log.levels.WARN)
    return
  end

  local normalized_color = normalize_color_to_hsl(config.color)
  if not normalized_color then
    vim.notify(
      "where-was-i: color must be an HSL table {h, s, l}, hex string, or highlight group name",
      vim.log.levels.WARN
    )
    return
  end

  -- Validate HSL values are in correct ranges
  if normalized_color.h < 0 or normalized_color.h > 360 then
    vim.notify("where-was-i: HSL hue must be 0-360", vim.log.levels.WARN)
    return
  end
  if normalized_color.s < 0 or normalized_color.s > 100 then
    vim.notify("where-was-i: HSL saturation must be 0-100", vim.log.levels.WARN)
    return
  end
  if normalized_color.l < 0 or normalized_color.l > 100 then
    vim.notify("where-was-i: HSL lightness must be 0-100", vim.log.levels.WARN)
    return
  end

  config.color = normalized_color

  -- Validate trail_length
  if type(config.trail_length) ~= "number" or config.trail_length < 1 then
    vim.notify("where-was-i: trail_length must be a number >= 1", vim.log.levels.WARN)
    return
  end

  -- Validate debounce_ms
  if type(config.debounce_ms) ~= "number" or config.debounce_ms < 0 then
    vim.notify("where-was-i: debounce_ms must be a non-negative number", vim.log.levels.WARN)
    return
  end

  -- Validate trail_includes
  if config.trail_includes ~= "previous" and config.trail_includes ~= "current" then
    vim.notify('where-was-i: trail_includes must be "previous" or "current"', vim.log.levels.WARN)
    return
  end

  -- Store original color config for colorscheme changes
  config.original_color = opts and opts.color

  -- Define signs with colors
  define_signs()

  -- Set up autocommands
  local group = vim.api.nvim_create_augroup("WhereWasI", { clear = true })

  -- Track cursor movement
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = on_cursor_moved,
  })

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(ev)
      clear_buffer_trail(ev.buf)
    end,
  })

  -- Redefine signs on colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      -- Re-extract color if it was from a highlight group
      if config.original_color and type(config.original_color) == "string" and not is_hex_color(config.original_color) then
        local normalized = normalize_color_to_hsl(config.original_color)
        if normalized then
          config.color = normalized
        end
      end
      define_signs()
    end,
  })

  -- Handle buffer switching for active_buffer_only mode
  if config.active_buffer_only then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function(ev)
        -- Validate buffer is valid
        if not vim.api.nvim_buf_is_valid(ev.buf) then
          return
        end

        -- Hide signs in previous buffer
        if last_active_buffer and vim.api.nvim_buf_is_valid(last_active_buffer) then
          hide_signs(last_active_buffer)
        end
        -- Show signs in new buffer
        show_signs(ev.buf)
        last_active_buffer = ev.buf
      end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
      group = group,
      callback = function(ev)
        -- Hide signs when leaving buffer
        hide_signs(ev.buf)
      end,
    })
  end

  -- Create user commands
  vim.api.nvim_create_user_command("WhereWasIClear", M.clear, {
    desc = "Clear trail for current buffer",
  })

  vim.api.nvim_create_user_command("WhereWasIClearAll", M.clear_all, {
    desc = "Clear trails for all buffers",
  })
end

return M

-- vim:noet:ts=4:sts=4:sw=4:
