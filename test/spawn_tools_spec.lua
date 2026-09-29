-- Kit specs for list_spawn_targets, create_agent, create_accessory.
-- Run: botster-plugin-test --plugin . test/spawn_tools_spec.lua
--
-- The in-process kit starts no session worker, so a successful spawn is
-- proven by the end-to-end run, not here. These specs cover every path up to
-- the Hub spawn helper, against the real runtime.
local kit = require("botster.test")

local TOOLS = { "create_accessory", "create_agent", "list_spawn_targets" }

local function tool_names(p)
  local names = {}
  for _, tool in ipairs(p:tools()) do
    for _, own in ipairs(TOOLS) do
      if tool.name == own then
        names[#names + 1] = tool.name
      end
    end
  end
  table.sort(names)
  return names
end

-- Admits a directory spawn target through the Hub's own request.
local function admit_target(t, id, label, kind)
  local response = t:request({
    type = "create_spawn_target",
    target_id = id,
    label = label,
    root = os.getenv("TMPDIR"),
    enabled = true,
    kind = kind,
  })
  t:eq(response.ok, true)
end

-- A JSON array decodes to a table carrying mlua's array metatable; a JSON
-- object decodes to a plain table. Empty lists must cross as arrays.
local function json_array(t, value, what)
  t:ok(type(value) == "table" and getmetatable(value) ~= nil, what .. " is a JSON array")
  t:eq(#value, 0)
end

-- A git target: a fresh repository with one commit.
local function git_root()
  local root = io.popen("mktemp -d"):read("*l")
  assert(os.execute("git -C '" .. root .. "' init --quiet && git -C '" .. root
    .. "' -c user.name=kit -c user.email=kit@localhost commit --quiet --allow-empty -m init"))
  return root
end

-- Admits a device session type for a target through the Hub's own request.
local function admit_session_type(t, target_id, id, role)
  local response = t:request({
    type = "create_session_type",
    source = { source = "device" },
    definition = {
      id = id,
      label = id,
      role = role,
      interaction = "interactive",
      lifecycle = "task",
      execution = { mode = "shell_command" },
      command = "cat",
      target_id = target_id,
    },
  })
  t:eq(response.ok, true)
end

local function local_hub_id(p)
  return p:call_tool("list_spawn_targets", {}).result.hub_id
end

kit.test("the package registers exactly its tools", function(t)
  local p = t:load(".")
  t:eq(tool_names(p), TOOLS)
end)

kit.test("list_spawn_targets on an empty hub returns an empty array and the hub id", function(t)
  local p = t:load(".")
  local r = p:call_tool("list_spawn_targets", {})
  t:eq(r.ok, true)
  t:eq(r.result.ok, true)
  json_array(t, r.result.targets, "targets")
  t:ok(type(r.result.hub_id) == "string" and r.result.hub_id ~= "", "hub_id is present")
end)

kit.test("an admitted target is listed with its session types as an array", function(t)
  local p = t:load(".")
  admit_target(t, "plain", "Plain", "directory")
  local r = p:call_tool("list_spawn_targets", {}).result
  t:match(r.targets, { { target_id = "plain", label = "Plain", kind = "directory", enabled = true } })
  -- An empty list must reach JSON as [] and not {}.
  json_array(t, r.targets[1].session_types, "session_types")
end)

kit.test("unknown arguments are refused before any Hub call", function(t)
  local p = t:load(".")
  for _, tool in ipairs(TOOLS) do
    local r = p:call_tool(tool, { caller_session_id = "sess-forged" }).result
    t:eq(r.ok, false)
    t:eq(r.error.kind, "invalid_arguments")
  end
end)

kit.test("required and typed arguments are enforced", function(t)
  local p = t:load(".")
  t:eq(p:call_tool("create_agent", {}).result.error.kind, "invalid_arguments")
  t:eq(p:call_tool("create_agent", { issue_or_branch = "  " }).result.error.kind, "invalid_arguments")
  t:eq(p:call_tool("create_agent", { issue_or_branch = 42 }).result.error.kind, "invalid_arguments")
  t:eq(p:call_tool("create_agent", { issue_or_branch = "b" }).result.error.kind, "invalid_arguments")
  t:eq(p:call_tool("create_accessory", { target_id = "t" }).result.error.kind, "invalid_arguments")
end)

kit.test("a target must exist, by id or by label", function(t)
  local p = t:load(".")
  t:eq(p:call_tool("create_agent", { issue_or_branch = "b", target_id = "missing" }).result.error.kind, "not_found")
  t:eq(p:call_tool("create_accessory", { accessory_name = "shell", target_name = "missing" }).result.error.kind,
    "not_found")
end)

kit.test("create_agent needs a git target", function(t)
  local p = t:load(".")
  admit_target(t, "plain", "Plain", "directory")
  local r = p:call_tool("create_agent", { issue_or_branch = "7", target_name = "Plain" }).result
  t:eq(r.error.kind, "target_not_git")
end)

kit.test("an unknown session type is refused with the candidates as an array", function(t)
  local p = t:load(".")
  admit_target(t, "plain", "Plain", "directory")
  local r = p:call_tool("create_accessory", { accessory_name = "nope", target_id = "plain" })
  t:eq(r.result.error.kind, "session_type_not_found")
  json_array(t, r.result.error.candidates, "candidates")
end)

kit.test("hub_id defaults to the local hub and a remote hub is refused", function(t)
  local p = t:load(".")
  local hub_id = local_hub_id(p)
  t:eq(p:call_tool("list_spawn_targets", { hub_id = hub_id }).result.ok, true)
  local remote = "hub-elsewhere"
  t:eq(p:call_tool("list_spawn_targets", { hub_id = remote }).result.error.kind, "remote_hub_unsupported")
  t:eq(p:call_tool("create_agent", { hub_id = remote, issue_or_branch = "b", target_id = "t" }).result.error.kind,
    "remote_hub_unsupported")
  t:eq(p:call_tool("create_accessory", { hub_id = remote, accessory_name = "x", target_id = "t" }).result.error.kind,
    "remote_hub_unsupported")
end)

-- Review of dc521f8: Hub roles are namespaced ("botster.agent"). Without
-- agent_name, create_agent must pick the target's only agent type and reach
-- the Hub spawn helper, not refuse with session_type_not_found.
kit.test("create_agent picks the target's only botster.agent session type", function(t)
  local p = t:load(".")
  local response = t:request({
    type = "create_spawn_target", target_id = "repo", label = "Repo",
    root = git_root(), enabled = true, kind = "git",
  })
  t:eq(response.ok, true)
  admit_session_type(t, "repo", "agent", "botster.agent")
  admit_session_type(t, "repo", "shell", "botster.accessory")
  local listed = p:call_tool("list_spawn_targets", {}).result
  t:match(listed.targets, { { target_id = "repo", session_types = {
    { role = "botster.agent" }, { role = "botster.accessory" },
  } } })
  local r = p:call_tool("create_agent", { issue_or_branch = "7", target_id = "repo" }).result
  if r.ok ~= true then
    t:ok(r.error.kind ~= "session_type_not_found" and r.error.kind ~= "session_type_ambiguous",
      "the agent type was chosen; the refusal came later: " .. tostring(r.error.kind))
  end
end)

-- A malformed hub_id never falls back to the local hub.
kit.test("a malformed hub_id is refused", function(t)
  local p = t:load(".")
  for _, bad in ipairs({ false, 42, "   " }) do
    t:eq(p:call_tool("list_spawn_targets", { hub_id = bad }).result.error.kind, "invalid_arguments")
    t:eq(p:call_tool("create_agent", { hub_id = bad, issue_or_branch = "b", target_id = "t" }).result.error.kind,
      "invalid_arguments")
    t:eq(p:call_tool("create_accessory", { hub_id = bad, accessory_name = "x", target_id = "t" }).result.error.kind,
      "invalid_arguments")
  end
end)
