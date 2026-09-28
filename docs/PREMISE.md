# botster-orchestrator: premise r1 (2026-09-28)

Writer: Claude session (Orchestrator plugin writer). Reviewer: "Orchestrator plugin — Codex reviewer".
Brief: /private/tmp/botster-default-plugins-brief-20260928.md (LazyVim model).
Hub baseline read: botster-hub origin/main f617e2d1.

The Hub owns session objects, operations, and authorization. This plugin owns
only the agent-facing surface: tool names, arguments, descriptions, and what
"create an agent" composes. The plugin holds no copy of Hub session state
that it must keep correct; it reads the Hub at call time.

## 1. Tools

Names match the reference tools that agents use today. Arguments use the Hub
term `session_id` (the reference used `session_uuid`; cold cut, no alias).
Every tool that targets a session accepts `session_id` or `label`. A `label`
resolves through the Hub session list; zero matches or two or more matches
return a typed refusal (`not_found`, `ambiguous_label`).

| Tool | Composes | Hub primitive (status) |
|---|---|---|
| `list_hubs` | local hub id plus its sessions, minus the caller | P1 hub identity (gap), P2 session list (gap), P7 caller (dependency) |
| `list_spawn_targets` | targets plus `session_types.list` per target | `spawn_targets.list`, `session_types.list` (exist) |
| `create_agent` | target by id or name, session type by name or auto (role `agent`), branch from `issue_or_branch`, prompt, label, workspace | `session_types.ensure_worktree_and_spawn` (exists), P3 label at spawn (gap), P8 MCP env (dependency) |
| `create_accessory` | target root, or a managed worktree when `branch` is given | `session_types.spawn` / `ensure_worktree_and_spawn` (exist), P3 (gap) |
| `delete_agent` | remove the session; optional `delete_worktree` | P4 session remove (gap), P5 worktree removal (gap, or cut the option) |
| `update_session` | `label` and/or `task`; `""` clears; target defaults to the caller | P3 label/task update (gap), P7 caller (dependency) |
| `get_pty_snapshot` | current screen text | P6 screen read (gap) |
| `whoami` | caller session record plus hub id | P1, P2, P7 — ownership to agree with the messaging writer (section 4) |

Every refusal is a typed result `{ ok = false, error = { kind, message } }`.
Kinds: `invalid_arguments`, `not_found`, `ambiguous_label`,
`caller_required`, `remote_hub_unsupported`, plus Hub kinds passed through
unchanged (`capability_denied`, `ensure_backpressured`, ...).

`hub_id`: the plugin accepts it only when it equals the local hub id. Any
other value returns `remote_hub_unsupported`. Hub-to-hub federation is out
of scope for this delivery (decision requested from the orchestrator).

## 2. Hub Lua API primitives needed (gap list for the plugin platform writer)

Exists today and is enough: `spawn_targets.list/validate`,
`session_types.list/show/spawn/ensure_worktree_and_spawn`, `worktrees.list/show`.

Missing. Each item names the daemon operation that already exists, if any.

- **P1 hub identity.** `botster.hub.identity()` returns `{ hub_id, display_name }`.
  The daemon has `host_id` only in the `Whoami` response.
- **P2 synchronous session read.** `botster.capabilities.sessions.list()` and
  `.show({ session_id })` return the `/session` entity fields plus `label`,
  `task`, and the session context summary (`target_id`, `worktree_id`,
  `branch`, `workspace_id`). The daemon has `ListSessions` (id and lifecycle
  only) and `ReadSessionContext`. Reason for a sync read and not the
  `session_family` stream: a Lua mirror of the stream is a second copy of Hub
  state, is empty until a baseline arrives, and must handle gaps. A tool call
  needs the current answer once.
- **P3 Hub-owned `label` and `task`.** Two mutable session fields on the Hub
  session record, projected into the `/session` entity.
  `botster.capabilities.sessions.update({ session_id, label = ?, task = ? })`,
  where `""` clears a field. `spawn` and `ensure_worktree_and_spawn` accept
  `label` so the label exists at spawn (no spawn-then-update window).
  No daemon operation exists today. Scope proposal:
  `{ surface = "session_actions", scope = "session_update" }`.
- **P4 session remove.** `botster.capabilities.sessions.remove({ session_id })`
  over `RemoveSession`. Typed `not_found`. Scope: `session_remove`.
- **P5 managed worktree removal.** Needed only for `delete_agent.delete_worktree`.
  `DeleteWorktree` deletes the record, not the files. If the platform will not
  add a managed filesystem removal, the plugin drops the option (preferred
  over a record-only delete that leaves files).
- **P6 screen read.** `botster.capabilities.sessions.read_screen({ session_id })`
  over `ReadScreen`, returning `{ session_id, text, unavailable? }`.
  Scope: `session_read_screen`.
- **P7 caller identity (dependency, collab writer).** The tool `call` receives a
  second argument `request` with the Hub-verified `request.caller.session_id`
  (nil for a non-session caller). Today `call` receives only the arguments.
- **P8 MCP env for spawned sessions (dependency, collab writer).** The Hub
  injects `BOTSTER_MCP_URL` and `BOTSTER_MCP_TOKEN` into sessions from both
  spawn helpers. The plugin never mints or passes tokens.

Every new helper returns the platform result shape and checks the calling
plugin's admitted grants, like the existing helpers.

## 3. Caller identity rules

- The caller comes only from `request.caller.session_id`. Tool arguments never
  name the caller. An argument named `caller`, `caller_session_id`, or
  `session_uuid` is refused with `invalid_arguments` (input schemas set
  `additionalProperties = false`).
- `list_hubs` excludes the caller. `update_session` without a target updates
  the caller; without a caller it refuses `caller_required`. `whoami` without
  a caller refuses `caller_required`.
- No tool trusts a caller claim in arguments to widen access (forged-caller test).

## 4. Open decisions

1. `whoami` ownership (orchestrator vs messaging). Proposal: orchestrator owns
   it, because the answer is the session record (label, task, branch,
   worktree). Messaging needs only the Hub caller, which it gets from P7.
2. Workspace placement for `create_agent.workspace_id`. Proposal: the plugin
   passes `context.workspace_id` to the spawn helper and emits the declared
   event `botster-orchestrator.session_spawned` `{ session_id, workspace_id }`;
   botster-workspaces subscribes and claims membership. Orchestrator never
   writes workspace state. Needs agreement from the botster-workspaces owner.
3. Remote hubs: out of scope (section 1).

## 5. Test plan

- Kit specs (`test/*_spec.lua`, run by `botster-plugin-test` at a pinned Hub
  commit) for every tool: success path, each typed refusal, caller identity,
  and forged-caller refusal. Caller specs wait for kit gate G1.
- No hand-written API fakes. Session input comes from the kit's
  `sessions_baseline` / `session_upsert` through production code.
- End-to-end on an isolated Hub (`--e2e`, `botsterq run --exclusive`): the
  orchestrator creates a session, lists it, labels it, reads its screen, and
  deletes it; a forged caller argument is refused over HTTP MCP.
- `script/test` runs both against the pinned Hub commit; README documents it.

## 6. Steps (each reviewed before the next)

1. Package skeleton, manifest, `list_spawn_targets`, `create_accessory`,
   `create_agent` on existing helpers; kit specs for them.
2. `list_hubs`, `get_pty_snapshot`, `delete_agent`, `update_session`,
   `whoami` as each Hub primitive lands.
3. Caller identity specs (G1/P7) and the forged-caller tests.
4. e2e proof, `script/test`, README, landing.
