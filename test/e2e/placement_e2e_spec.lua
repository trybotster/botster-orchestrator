-- botster-orchestrator against a REAL daemon process with a session worker.
-- Run with the candidate Hub binaries from the Hub's own gate:
--   BOTSTER_HUB_BIN=... BOTSTER_SESSION_WORKER_BIN=... BOTSTER_CANDIDATE_MANIFEST=... \
--     script/test-e2e
-- The in-process kit has no session worker, so a completed spawn, and the
-- event that announces it, are proven here.
--
-- The real-daemon mode cannot await another package's handler without a poll,
-- so these specs prove this package's half of the placement contract: a spawn
-- that asks for a workspace emits the declared `session_spawned` event and
-- the Hub router accepts it against the manifest's schema. The consumer half
-- is proven in botster-workspaces' kit specs (test/events_spec.lua).
local kit = require("botster.test")

-- A git target with a real repository, and a runnable botster.agent type.
local function admit_git_target_with_agent(t)
  local root = io.popen("mktemp -d"):read("*l")
  assert(os.execute("git -C '" .. root .. "' init --quiet && git -C '" .. root
    .. "' -c user.name=kit -c user.email=kit@localhost commit --quiet --allow-empty -m init"))
  t:eq(t:request({
    type = "create_spawn_target", target_id = "repo", label = "Repo",
    root = root, enabled = true, kind = "git",
  }).ok, true)
  t:eq(t:request({
    type = "create_session_type",
    source = { source = "device" },
    definition = {
      id = "agent", label = "agent", role = "botster.agent",
      interaction = "interactive", lifecycle = "task",
      execution = { mode = "shell_command" }, command = "cat", target_id = "repo",
    },
  }).ok, true)
end

local function hub_sessions(t)
  local listed = t:request({ type = "list_sessions" })
  t:eq(listed.ok, true)
  return listed.response.sessions
end

kit.test("create_agent with a workspace_id starts a real session and emits session_spawned", function(t)
  local p = t:load(".")
  admit_git_target_with_agent(t)
  local created = p:call_tool("create_agent", {
    issue_or_branch = "42", target_id = "repo", workspace_id = "ws_alpha_1",
  })
  t:eq(created.ok, true)
  local r = created.result
  t:eq(r.ok, true, "the Hub started the session: " .. tostring(r.error and r.error.message))
  t:eq(r.workspace_id, "ws_alpha_1")
  t:eq(r.workspace_event.ok, true, "the emit call succeeded")
  t:eq(r.workspace_event.value.status, "accepted", "the router accepted the declared event")
  -- The real Hub holds exactly the session the tool reported.
  local sessions = hub_sessions(t)
  t:eq(#sessions, 1)
  t:eq(sessions[1].session_id, r.session_id)
end)

kit.test("create_agent without a workspace_id starts a session and emits no event", function(t)
  local p = t:load(".")
  admit_git_target_with_agent(t)
  local r = p:call_tool("create_agent", { issue_or_branch = "43", target_id = "repo" }).result
  t:eq(r.ok, true, "the Hub started the session: " .. tostring(r.error and r.error.message))
  t:eq(r.workspace_id, nil)
  t:eq(r.workspace_event, nil)
  t:eq(#hub_sessions(t), 1)
end)
