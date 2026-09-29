-- botster-orchestrator: the default agent-facing orchestration tools.
-- The Hub owns sessions, spawn, and authorization; this plugin owns only the
-- tool names, arguments, descriptions, and what each tool composes.
local spawn_tools = require("orchestrator.spawn_tools")

local TOOLS = {
  spawn_tools.list_spawn_targets,
  spawn_tools.create_agent,
  spawn_tools.create_accessory,
}

local registered = {}
for _, tool in ipairs(TOOLS) do
  registered[#registered + 1] = {
    name = tool.name,
    description = tool.description,
    input_schema = tool.input_schema,
    handler = tool.name,
    call = tool.call,
  }
end

return botster.register({ tools = registered })
