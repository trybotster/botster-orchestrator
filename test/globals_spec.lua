-- Strict globals: the plugin's Lua (plugin.lua and lua/**) uses no global
-- that the sandbox does not define. The check parses the Lua and compares
-- every global name with the sandbox's real global set, so a call in an error
-- path that no runtime spec reaches fails here, not in production.
-- Run: botster-plugin-test --plugin . test/globals_spec.lua
local kit = require("botster.test")

kit.test("botster-orchestrator uses no global name that the sandbox does not define", function(t)
  local p = t:load(".")
  local found = p:undefined_globals()
  local names = {}
  for _, use in ipairs(found) do
    names[#names + 1] = use.file .. ":" .. use.line .. " " .. use.name
  end
  t:eq(#found, 0, "undefined globals: " .. table.concat(names, ", "))
end)
