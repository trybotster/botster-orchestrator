# botster-orchestrator: premise r3 (2026-09-28)

r3 answers the Request 1 verdict (REJECT 0aa2b89). New section 3a defines how
the Hub binds the verified caller to session operations and authorizes them.
Section 5 adds real-runtime tests for allowed access, denied access between
two sessions, a missing caller, and a forged identity. r2 changes follow.

r2 records the orchestrator decisions (msg_plugin-w_1790637092_b9f224) and the
caller shape agreed with the messaging writer (msg_plugin-w_1790637097_57833a):
- Federation is out of scope. A non-local `hub_id` returns `remote_hub_unsupported`.
- The orchestrator plugin owns `whoami`. Messaging does not register it.
- Workspace placement uses the event `botster-orchestrator.session_spawned`.
- This writer also owns the botster-workspaces side (new section 7).
- `request.caller` is `{ kind = "session", session_id }` or `{ kind = "operator" }`.


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
| `whoami` | caller session record plus hub id | P1, P2, P7 (owned here, section 4) |

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
- **P9 spawn lineage and caller-bound authorization.** Section 3a. The Hub
  binds the invocation caller to every session helper, stores and projects
  `spawned_by`, and applies the policy. Helpers refuse caller arguments.
- **P8 MCP env for spawned sessions (dependency, collab writer).** The Hub
  injects `BOTSTER_MCP_URL` and `BOTSTER_MCP_TOKEN` into sessions from both
  spawn helpers. The plugin never mints or passes tokens.

Every new helper returns the platform result shape and checks the calling
plugin's admitted grants, like the existing helpers.

## 3. Caller identity rules

- The caller comes only from `request.caller`, which the Hub verifies. Its shape
  is `{ kind = "session", session_id }` or `{ kind = "operator" }`.
- A missing or malformed `request.caller` fails closed with `caller_invalid`.
  It never means operator.
- Tool arguments never name the caller. Input schemas set
  `additionalProperties = false`, so an argument such as `caller` or
  `caller_session_id` is refused with `invalid_arguments`.
- `list_hubs` excludes a session caller.
- `update_session` without a target updates a session caller. For an operator
  caller it refuses with `caller_required`.
- `whoami` reports an operator explicitly: `session_id = nil`,
  `identity_source = "operator"`. For a session caller it reports
  `identity_source = "session"` and the session record.
- No tool uses a caller claim in its arguments to widen access (forged-caller test).

## 3a. Hub authorization of session operations (r3)

The plugin does not authorize session operations. The Hub does. The plugin
only chooses the tool surface.

Binding. The Hub records the verified caller of each admitted MCP invocation
in the invocation context (`PluginInvocationContext`). Every session helper
(P3 update, P4 remove, P6 read_screen, and both spawn helpers) reads the
caller from the context of the invocation that is running. No helper accepts
a caller argument. A helper refuses `caller`, `caller_session_id`, or
`on_behalf_of` with `invalid_request`. So a plugin cannot forge a caller, and
a tool argument cannot reach the Hub as identity.

Invocations without a tool caller (event handlers, timers, surface routes) run
with the caller `{ kind = "plugin" }`. The policy below refuses it for every
operation on a session other than one the same invocation just spawned.

Lineage (new P9). At spawn, the Hub stores `spawned_by` on the session record:
the caller session id, or `operator`. It projects `spawned_by` into the
`/session` entity. The caller cannot choose `spawned_by`.

Policy (proposed default; the Hub owner decides, section 4):

| Caller | own session | a session it spawned (direct child) | any other session |
|---|---|---|---|
| operator | allow | allow | allow |
| session | allow | allow | refuse `forbidden` |
| plugin (no tool caller) | — | refuse, except the same invocation's spawn result | refuse `forbidden` |
| missing or malformed | refuse `caller_invalid` | refuse `caller_invalid` | refuse `caller_invalid` |

The rule applies to remove, read_screen, and update. Spawn requires a
session or operator caller. The read-only list (P2) is allowed to every
session and operator caller, because `list_hubs` exists to discover peers.

Behaviour change against the monorepo: there, any agent could delete or read
any session. Under this default, a peer that did not spawn a session cannot
read its screen or delete it. The orchestrator session reaches every session it
spawned. The decision on this change goes to the Hub owner and the user
(section 4, item 4).

## 4. Decisions (orchestrator, 2026-09-28)

1. `whoami`: the orchestrator plugin owns it.
2. Workspace placement: `create_agent` passes `context.workspace_id` to the
   spawn helper. After a successful spawn it emits the declared event
   `botster-orchestrator.session_spawned` `{ session_id, workspace_id }`.
   botster-workspaces subscribes and claims membership (section 7). The
   orchestrator never writes workspace state. `workspace_id` is the only
   workspace argument. The reference `workspace_name` argument is cut,
   because the orchestrator does not read workspace records.
3. Remote hubs: out of scope. The user may still decide otherwise.
4. OPEN: the session authorization policy in section 3a (owner: the plugin
   platform writer, with the user for the behaviour change). The plugin needs
   no change for another policy: it passes Hub refusals through unchanged.

## 5. Test plan

- Kit specs (`test/*_spec.lua`, run by `botster-plugin-test` at a pinned Hub
  commit) for every tool: success path, each typed refusal, caller identity,
  and forged-caller refusal. Caller specs wait for kit gate G1.
- Authorization through the real runtime (section 3a). Each case calls the
  plugin tool with a Hub-verified caller and asserts the Hub result, not a
  plugin-side check:
  - allowed: session A spawns B; A reads B's screen, updates B, removes B;
  - denied: session C did not spawn B; C's remove, read_screen, and update of B
    return `forbidden`, and B still exists afterwards;
  - operator: an operator caller removes B;
  - missing caller: an invocation without `request.caller`, and one with a
    malformed caller, return `caller_invalid` for every tool, including `whoami`;
  - forged identity: C passes `caller_session_id = A` (plugin refuses
    `invalid_arguments`), and a fixture plugin passes `caller = A` directly to
    the Hub helper (Hub refuses `invalid_request`); in both cases B still exists.
  - Ablation: a fixture that skips the Hub check (plugin-side allow) must make
    the denied case fail, which proves the test observes the Hub decision.
- Where each case runs: the kit, when kit gate G1 (caller) is present and the kit can
  spawn a session; otherwise the e2e run on an isolated Hub, with two real
  agent sessions calling tools over HTTP MCP with their own tokens. The
  forged-token case (C's token with A's id in arguments) runs in e2e.
- No hand-written API fakes. Session input comes from the kit's
  `sessions_baseline` / `session_upsert` through production code.
- End-to-end on an isolated Hub (`--e2e`, `botsterq run --exclusive`): the
  orchestrator creates a session, lists it, labels it, reads its screen, and
  deletes it; a forged caller argument is refused over HTTP MCP.
- `script/test` runs both against the pinned Hub commit; README documents it.

## 6. Steps (each reviewed before the next)

Steps for botster-workspaces are W1 and W2 in section 7.

1. Package skeleton, manifest, `list_spawn_targets`, `create_accessory`,
   `create_agent` on existing helpers; kit specs for them.
2. `list_hubs`, `get_pty_snapshot`, `delete_agent`, `update_session`,
   `whoami` as each Hub primitive lands.
3. Caller identity specs (G1/P7) and the forged-caller tests.
4. e2e proof, `script/test`, README, landing.

## 7. botster-workspaces side (owned by this writer)

Repo: ~/Projects/botster-workspaces, base main 742891f. Worktree:
~/botster-sessions/botster-workspaces-delivery-agent-tools-20260928, branch
delivery/workspaces-agent-tools-20260928.

The TUI and the Web call the existing `botster_workspaces.*` tools
(botster-tui `src/app.rs`, botster-web `scripts/live-packaged-protocol-harness.mjs`).
These names do not change.

- **W1 subscription.** botster-workspaces subscribes to
  `{ owner = "botster-orchestrator", name = "session_spawned" }`. The handler
  claims membership through the existing claim path (the same code as
  `add_session`). An unknown `workspace_id` or an existing owner is logged and
  ignored, so the spawn stays successful and the session stays ungrouped.
  Kit spec: orchestrator emit, then membership in plugin_db and in the
  membership entity. The chain must settle in one kit step.
- **W2 agent tools.** Three agent-facing tools, with the names that agents use
  today: `list_workspaces`, `rename_workspace`, `move_agent_workspace`. Each
  one is a thin entry over the same internal functions as the
  `botster_workspaces.*` tool. `move_agent_workspace` takes `session_id` and
  `workspace_id`. A `label` needs P2 to resolve; until P2 lands, label
  resolution is not offered. `hub_id` follows the section 1 rule.
- The two surfaces use one implementation. The agent tools exist only for the
  agent-facing argument names and descriptions.
