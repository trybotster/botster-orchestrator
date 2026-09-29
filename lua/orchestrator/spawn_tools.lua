-- list_spawn_targets, create_agent, create_accessory.
local result = require("orchestrator.result")
local hub = require("orchestrator.hub")

local M = {}

local function string_property(description)
  return { type = "string", description = description }
end

local function hub_property(properties)
  properties.hub_id = string_property("Hub ID. Omit for the local hub; other hubs are not supported yet.")
  return properties
end

local function target_properties(properties)
  hub_property(properties)
  properties.target_id = string_property("Spawn target ID from list_spawn_targets.")
  properties.target_name = string_property(
    "Spawn target label from list_spawn_targets. Used when target_id is omitted.")
  return properties
end

-- A number becomes the branch `botster-issue-<n>`; anything else is the branch.
local function branch_for(issue_or_branch)
  if issue_or_branch:match("^%d+$") then
    return "botster-issue-" .. issue_or_branch
  end
  return issue_or_branch
end

local function resolve_target(arguments)
  local target_id = result.text(arguments.target_id)
  local target_name = result.text(arguments.target_name)
  if not target_id and not target_name then
    return nil, result.refuse("invalid_arguments", "target_id or target_name is required")
  end
  return hub.find_target(target_id, target_name)
end

local function available_types(target_id)
  local types, err = hub.session_types(target_id)
  if err then
    return nil, err
  end
  local available = result.array()
  for _, session_type in ipairs(types) do
    if session_type.available ~= false then
      available[#available + 1] = session_type
    end
  end
  return available, nil
end

local function type_ids(types)
  local ids = result.array()
  for _, session_type in ipairs(types) do
    ids[#ids + 1] = session_type.session_type_id
  end
  return ids
end

-- Finds one session type by id or label. Without a name, picks the only type
-- whose role is `role`.
local function choose_session_type(target_id, name, role)
  local types, err = available_types(target_id)
  if err then
    return nil, err
  end
  local matches = {}
  for _, session_type in ipairs(types) do
    local wanted
    if name then
      wanted = session_type.session_type_id == name or session_type.id == name
        or session_type.label == name
    else
      wanted = session_type.role == role
    end
    if wanted then
      matches[#matches + 1] = session_type
    end
  end
  if #matches == 1 then
    return matches[1], nil
  end
  local described = name and ("named " .. name) or ("with role " .. role)
  local kind = #matches == 0 and "session_type_not_found" or "session_type_ambiguous"
  return nil, result.refuse(kind, "target " .. target_id .. " has "
    .. (#matches == 0 and "no" or "more than one") .. " session type " .. described,
    { candidates = type_ids(#matches == 0 and types or matches) })
end

local function spawned(identity, session, target, session_type)
  local reply = {
    ok = true,
    hub_id = identity.hub_id,
    session_id = session.session_id,
    target_id = target.target_id,
    session_type_id = session_type.session_type_id,
    branch = session.branch,
    worktree_id = session.worktree_id,
    worktree_path = session.worktree_path,
    created_worktree = session.created_worktree,
    reused_worktree = session.reused_worktree,
  }
  return reply
end

M.list_spawn_targets = {
  name = "list_spawn_targets",
  description = "List the spawn targets on the local hub with their session types. "
    .. "Use a target_id (or target label) and a session_type_id from this list "
    .. "when calling create_agent or create_accessory.",
  input_schema = { type = "object", properties = hub_property({}), additionalProperties = false },
  call = function(arguments)
    local refused = result.check_arguments(arguments, M.list_spawn_targets.input_schema)
    if refused then
      return refused
    end
    local identity, err = hub.resolve(result.text(arguments.hub_id))
    if err then
      return err
    end
    local targets
    targets, err = hub.spawn_targets()
    if err then
      return err
    end
    local rows = result.array()
    for _, target in ipairs(targets) do
      local row = {
        target_id = target.target_id,
        label = target.label,
        kind = target.kind,
        enabled = target.enabled,
        session_types = result.array(),
      }
      if target.enabled ~= false then
        local types, types_err = available_types(target.target_id)
        if types_err then
          row.session_types_error = types_err.error
        else
          for _, session_type in ipairs(types) do
            row.session_types[#row.session_types + 1] = {
              session_type_id = session_type.session_type_id,
              label = session_type.label,
              role = session_type.role,
              description = session_type.description,
            }
          end
        end
      end
      rows[#rows + 1] = row
    end
    return { ok = true, hub_id = identity.hub_id, targets = rows }
  end,
}

M.create_agent = {
  name = "create_agent",
  description = "Create an agent session in a managed git worktree on the local hub. "
    .. "issue_or_branch is a branch name, or an issue number (branch botster-issue-<n>). "
    .. "The worktree is created if missing and reused if present. "
    .. "Returns the new session_id when the Hub has spawned the session.",
  input_schema = {
    type = "object",
    properties = target_properties({
      issue_or_branch = string_property("Issue number or branch name for the agent's worktree."),
      prompt = string_property("Task prompt for the agent."),
      agent_name = string_property(
        "Session type ID or label. Omit to use the target's only session type with role 'agent'."),
    }),
    required = { "issue_or_branch" },
    additionalProperties = false,
  },
  call = function(arguments)
    local refused = result.check_arguments(arguments, M.create_agent.input_schema)
    if refused then
      return refused
    end
    local identity, err = hub.resolve(result.text(arguments.hub_id))
    if err then
      return err
    end
    local target
    target, err = resolve_target(arguments)
    if err then
      return err
    end
    if target.kind ~= "git" then
      return result.refuse("target_not_git",
        "create_agent needs a git spawn target for its worktree: " .. target.target_id)
    end
    local session_type
    session_type, err = choose_session_type(target.target_id, result.text(arguments.agent_name), "agent")
    if err then
      return err
    end
    local session
    session, err = hub.spawn_in_worktree({
      target_id = target.target_id,
      branch = branch_for(result.text(arguments.issue_or_branch)),
      session_type_id = session_type.session_type_id,
      context = { prompt = result.text(arguments.prompt) },
    })
    if err then
      return err
    end
    return spawned(identity, session, target, session_type)
  end,
}

M.create_accessory = {
  name = "create_accessory",
  description = "Create an accessory session (for example a server or a terminal) on the local hub. "
    .. "With branch, it runs in that branch's managed worktree (git targets only). "
    .. "Without branch, it runs in the target's own directory.",
  input_schema = {
    type = "object",
    properties = target_properties({
      accessory_name = string_property("Session type ID or label of the accessory."),
      branch = string_property("Branch whose managed worktree the accessory runs in."),
    }),
    required = { "accessory_name" },
    additionalProperties = false,
  },
  call = function(arguments)
    local refused = result.check_arguments(arguments, M.create_accessory.input_schema)
    if refused then
      return refused
    end
    local identity, err = hub.resolve(result.text(arguments.hub_id))
    if err then
      return err
    end
    local target
    target, err = resolve_target(arguments)
    if err then
      return err
    end
    local session_type
    session_type, err = choose_session_type(target.target_id, result.text(arguments.accessory_name))
    if err then
      return err
    end
    local branch = result.text(arguments.branch)
    local context = {}
    local session
    if branch then
      if target.kind ~= "git" then
        return result.refuse("target_not_git",
          "branch needs a git spawn target: " .. target.target_id)
      end
      session, err = hub.spawn_in_worktree({
        target_id = target.target_id,
        branch = branch,
        session_type_id = session_type.session_type_id,
        context = context,
      })
    else
      session, err = hub.spawn_at_target({
        session_type_id = session_type.session_type_id,
        target_id = target.target_id,
        context = context,
      })
    end
    if err then
      return err
    end
    return spawned(identity, session, target, session_type)
  end,
}

return M
