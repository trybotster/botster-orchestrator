-- Tool results and argument checks shared by every orchestrator tool.
local M = {}

function M.refuse(kind, message, extra)
  local result = { ok = false, error = { kind = kind, message = message } }
  for key, value in pairs(extra or {}) do
    result.error[key] = value
  end
  return result
end

-- A table that encodes as a JSON array even when empty. A plain empty Lua
-- table crosses the Hub boundary as `{}`; a decoded JSON array keeps its
-- array marker (docs/lua-plugin-abi.md, Runtime Basics).
function M.array()
  return botster.json.decode({ text = "[]" }).value
end

-- Trimmed non-empty string, or nil.
function M.text(value)
  if type(value) ~= "string" then
    return nil
  end
  local trimmed = value:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil
  end
  return trimmed
end

-- Checks arguments against a tool's declared properties. The Hub does not
-- enforce input schemas, so every tool calls this before it reads anything.
-- Returns nil when the arguments are acceptable, otherwise a refusal.
function M.check_arguments(arguments, schema)
  if arguments == nil then
    arguments = {}
  end
  if type(arguments) ~= "table" then
    return M.refuse("invalid_arguments", "arguments must be an object")
  end
  local properties = schema.properties or {}
  for key, value in pairs(arguments) do
    local property = properties[key]
    if property == nil then
      return M.refuse("invalid_arguments", "unknown argument: " .. tostring(key))
    end
    if property.type == "string" and type(value) ~= "string" then
      return M.refuse("invalid_arguments", key .. " must be a string")
    end
    if property.type == "boolean" and type(value) ~= "boolean" then
      return M.refuse("invalid_arguments", key .. " must be a boolean")
    end
  end
  for _, key in ipairs(schema.required or {}) do
    if M.text(arguments[key]) == nil then
      return M.refuse("invalid_arguments", key .. " is required")
    end
  end
  return nil
end

return M
