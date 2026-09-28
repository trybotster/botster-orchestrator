# botster-orchestrator: premise r5.1 (2026-09-28)

r5.1 applies the ACCEPT bc2cc2e notes (denial ordering and exact kinds) and
records the 00a2 confirmation of package ownership.


r5 answers REJECT 9a75279. Section 3a separates check A (the invocation caller)
from check B (the plugin's per-operation grant), defines `kind = "plugin"`
invocations, and defines package ownership without agent lineage. Section 5
adds screen denial, independent grants, base width, approval, and plugin
invocation cases.


r4 applies the user decision on session authorization (section 3a) and
rewrites the section 5 authorization tests for it. The denied case moves from
"agent to agent" (now allowed) to "plugin without an approved `:any` permission".


r3.1 applies the ACCEPT 8caccda notes (Hub-side ablation; no plugin-caller
spawn exception). r3 answers the Request 1 verdict (REJECT 0aa2b89). New section 3a defines how
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
| `delete_agent` | remove the session (no `delete_worktree` until platform slice 7) | P4 session remove (gap) |
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

Platform writer answers (00a2, msg_plugin-w_1790637351_ac2926), in slice order 5a, 5b, 5c, 5d:
P1 built (`botster.hub.identity()` -> `{ ok, value = { hub_id, display_name } }`, no grant);
P2 slice 5a (grant `session_read`; `session_read:any` for all owners);
P3, P4, P6 slice 5d (scopes `session_update`, `session_remove`, `session_screen`);
P5 declined until slice 7, so `delete_agent` has no `delete_worktree` option;
P7 slice 5c (`call(args, request)`), after the collab writer's credential verify.
P9 is decided by the user (section 3a, r4). P1 is committed as 1c4ee55b and lands with the reviewed stack.

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
- **P9 caller-bound authorization.** Section 3a. The Hub binds the invocation
  caller to every session helper and applies the user's policy, including
  granular plugin `:any` permissions. Helpers refuse caller arguments.
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

## 3a. Hub authorization of session operations (r5)

The plugin does not authorize session operations. The Hub does. The plugin
only chooses the tool surface. Policy source: USER DECISION relayed by 00a2
(msg_plugin-w_1790639455_6f0632). There is no agent lineage.

The Hub allows a session operation only when BOTH checks pass:
check A on the caller, and check B on the plugin's grant. They are independent.

Operations: `read` (P2), `screen` (P6), `update` (P3), `remove` (P4), `spawn`
(both spawn helpers).

### Check A: the caller of the invocation

The Hub records the caller of each admitted invocation in its
`PluginInvocationContext`. Every session helper reads it from the running
invocation. No helper accepts a caller argument. A helper refuses `caller`,
`caller_session_id`, or `on_behalf_of` with `invalid_request`.

| Invocation | Caller | Check A |
|---|---|---|
| MCP tool call | `{ kind = "operator" }` | pass, for any session |
| MCP tool call | `{ kind = "session", session_id }`, verified | pass, for any session (as in the monorepo) |
| MCP tool call | missing or malformed | refuse `caller_invalid` |
| event, timer, surface route (no tool caller) | `{ kind = "plugin" }` | pass; only check B applies |

### Check B: the plugin's grant

Each operation has its own grant, with two widths:
- base (for example `session_screen`): the operation is allowed only on a
  session that this package spawned;
- `:any` (for example `session_screen:any`): the operation is allowed on any
  session. The manifest declares it, and the operator approves it at enable.
  A declared but unapproved `:any` grant counts as absent.

Grants are independent. For example, `session_screen:any` does not give
`session_remove` or `session_remove:any`. A missing grant is refused with
`capability_denied`. A base grant on a session that the package did not spawn
is refused with `forbidden`. Spawn needs the spawn scope that the package
already declares (`session_type_spawn`, `session_type_managed_git_spawn`).

Package ownership (how the Hub knows "this package spawned it"). At spawn, the
Hub stores the spawning package key on the session record. It takes the key
from the invocation that calls the spawn helper, never from arguments or from
the caller. This is package ownership, not agent lineage: it records which
plugin package made the session, not which agent asked for it. It is not
projected to clients. 00a2 confirmed this (msg_plugin-w_1790639577_d4337e):
the owning package lives in the durable per-session Hub record with label and
task, is empty for operator and agent spawns, survives disable, enable, and
reload, and appears only in Lua `sessions.list/show` rows as `owner_plugin`.
Grant names are final only in the slice 5d request.

### This plugin

Its tools act for agents on any session, so its manifest declares
`session_read:any`, `session_screen:any`, `session_update:any`, and
`session_remove:any` (00a2 settles the final names in slice 5d). The plugin
makes no authorization decision of its own. It passes Hub refusals through
unchanged.

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
4. Session authorization (user decision, section 3a): agents may act on any
   session; plugins need operator-approved granular `:any` permissions.

## 5. Test plan

- Kit specs (`test/*_spec.lua`, run by `botster-plugin-test` at a pinned Hub
  commit) for every tool: success path, each typed refusal, caller identity,
  and forged-caller refusal. Caller specs wait for kit gate G1.
- Authorization through the real runtime (section 3a, r5). Each case calls the
  plugin tool and asserts the Hub result, not a plugin-side check. Session B is
  spawned outside the package under test unless stated.
  - Check A, agent to agent: session C (verified) reads B's screen, updates B,
    and removes B; each call succeeds.
  - Check A, operator: an operator caller removes B.
  - Check A, missing caller: a tool call without `request.caller`, and one with
    a malformed caller, return `caller_invalid` for every tool, including
    `whoami`; B still exists.
  - Check B, screen denied: the package without `session_screen:any` calls
    `get_pty_snapshot` on B and receives the Hub refusal; no screen text returns.
  - Check B, independent grants: a package with `session_screen:any` and
    without `session_remove:any` reads B's screen and cannot remove B (B still
    exists). A package with `session_remove:any` and without
    `session_screen:any` removes B and cannot read its screen. The same pairs
    cover `update` and `read`.
  - Check B, base width: a package with only base `session_screen` reads the
    screen of a session it spawned and is refused for B.
  - Check B, approval: `session_remove:any` declared but not approved at enable
    is refused like an absent grant.
  - Check B, plugin invocation: an event handler of the package (caller kind
    `plugin`) is governed only by check B: with `session_remove:any` it removes
    B; without it, it is refused.
  - Forged identity: C passes `caller_session_id = A` (the plugin refuses with
    `invalid_arguments`); a fixture plugin passes `caller = A` directly to the
    Hub helper (the Hub refuses with `invalid_request`).
  - Ablation: run the screen-denied and independent-grant cases against a Hub
    build with the Hub grant check disabled. They must then fail. This proves
    that the tests observe the Hub decision.
  - Ordering: every denial case runs on its own session, or runs before any
    removal of that session, and asserts the exact Hub error kind
    (`capability_denied` for a missing grant, `forbidden` for base width on a
    foreign session, `caller_invalid` for check A). A denial observed after a
    removal proves nothing.
  - Grant variants are separate fixture manifests of the same Lua package; no
    Lua code changes between them.
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
