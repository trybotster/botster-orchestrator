-- Thin reads and spawns over the Hub capability helpers. Each function
-- returns (value, nil) or (nil, refusal). Hub refusal kinds pass through.
local result = require("orchestrator.result")

local M = {}

local function capabilities()
  return botster.capabilities
end

-- Hub helpers that raise return a Lua string; keep its text as the message.
local function raised(kind, err)
  return result.refuse(kind, type(err) == "string" and err or tostring(err))
end

-- The hub this plugin runs in: { hub_id, display_name }.
function M.identity()
  local identified = botster.hub.identity()
  if identified.ok ~= true then
    return nil, result.refuse(identified.error.kind, identified.error.message)
  end
  return identified.value, nil
end

-- The one place a tool's `hub_id` argument is resolved. Nil means the local
-- hub. Hub routing replaces the refusal below; tools do not change.
function M.resolve(hub_id)
  local identity, err = M.identity()
  if err then
    return nil, err
  end
  if hub_id ~= nil and hub_id ~= identity.hub_id then
    return nil, result.refuse("remote_hub_unsupported",
      "only the local hub is supported: " .. identity.hub_id, { hub_id = hub_id })
  end
  return identity, nil
end

function M.spawn_targets()
  local ok, listed = pcall(capabilities().spawn_targets.list)
  if not ok then
    return nil, raised("hub_unavailable", listed)
  end
  if listed.ok ~= true then
    return nil, result.refuse(listed.error.kind, listed.error.message)
  end
  return listed.value, nil
end

-- Resolves an enabled target by id or by label. Exactly one of the two is used.
function M.find_target(target_id, target_name)
  local targets, err = M.spawn_targets()
  if err then
    return nil, err
  end
  local matches = {}
  for _, target in ipairs(targets) do
    if (target_id and target.target_id == target_id)
      or (not target_id and target_name and target.label == target_name) then
      matches[#matches + 1] = target
    end
  end
  local wanted = target_id or target_name
  if #matches == 0 then
    return nil, result.refuse("not_found", "no spawn target matches: " .. tostring(wanted))
  end
  if #matches > 1 then
    return nil, result.refuse("ambiguous_target", "more than one spawn target is named: " .. wanted)
  end
  if matches[1].enabled == false then
    return nil, result.refuse("target_disabled", "spawn target is disabled: " .. matches[1].target_id)
  end
  return matches[1], nil
end

function M.session_types(target_id)
  local ok, listed = pcall(capabilities().session_types.list, { target_id = target_id })
  if not ok then
    return nil, raised("hub_unavailable", listed)
  end
  return listed, nil
end

-- Spawns a session type in a managed worktree of `branch`.
function M.spawn_in_worktree(args)
  local ok, spawned = pcall(capabilities().session_types.ensure_worktree_and_spawn, args)
  if not ok then
    return nil, raised("spawn_refused", spawned)
  end
  if spawned.ok ~= true then
    return nil, result.refuse(spawned.error.kind, spawned.error.message)
  end
  return spawned.result, nil
end

-- Spawns a session type in the target's own directory.
function M.spawn_at_target(args)
  local ok, spawned = pcall(capabilities().session_types.spawn, args)
  if not ok then
    return nil, raised("spawn_refused", spawned)
  end
  return spawned, nil
end

return M
