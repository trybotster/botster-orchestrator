# botster-orchestrator

The default Botster plugin for agent-facing orchestration tools. The Hub owns
sessions, spawn, and authorization. This package owns only the tool surface:
names, arguments, descriptions, and what each tool composes.

## Tools

| Tool | What it does |
|---|---|
| `list_spawn_targets` | Lists the local hub's spawn targets with their session types. |
| `create_agent` | Spawns an agent session in a managed git worktree. `issue_or_branch` is a branch, or an issue number (branch `botster-issue-<n>`). The session type is `agent_name`, or the target's only session type with role `agent`. |
| `create_accessory` | Spawns a session type in the target's directory, or in a branch's managed worktree when `branch` is given. |

More tools (`list_hubs`, `whoami`, `update_session`, `delete_agent`,
`get_pty_snapshot`) follow as their Hub primitives land; see
`docs/PREMISE.md`, section 2.

Every result carries `hub_id`. Session references are `{ hub_id, session_id }`.
Every tool accepts an optional `hub_id`, which defaults to the local hub; another
hub is refused with `remote_hub_unsupported` until hub routing exists.

A refusal is `{ ok = false, error = { kind, message } }`. Hub refusal kinds pass
through unchanged. The plugin makes no authorization decision of its own.

To place a new session in a workspace, call botster-workspaces'
`move_agent_workspace` after `create_agent`.

## Testing

The specs in `test/*_spec.lua` run in the Botster plugin test kit, which loads
this package into a real Hub runtime (no API fakes):

```sh
cargo install --locked --git https://github.com/trybotster/botster-hub --rev <pin> botster-plugin-test-kit
BOTSTER_PLUGIN_TEST=botster-plugin-test script/test
```

The in-process kit starts no session worker, so a completed spawn is proven by
the end-to-end run on an isolated Hub, not by these specs.
