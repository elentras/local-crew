# Workflows

This folder holds exported n8n workflow JSON files that orchestrate
the agent crew.

All 5 roles have a standalone workflow (`cto.json`, `pm.json`,
`backend_dev.json`, `frontend_dev.json`, `qa.json`), each following
the same chain: Manual Trigger → Set Prompt → HTTP Request (resolve
the role's config from the binding server) → Code (build the Ollama
payload) → HTTP Request (`POST /api/chat`) → Code (extract the
reply). The only differences between them are the role name in the
config-resolution URL, the system message, and the example prompt in
"Set Prompt". They hardcode `http://127.0.0.1:4567` (binding server)
and `http://localhost:11434` (Ollama) — fine for a first local proof
of concept, but worth revisiting (env var or n8n credential) before
this travels to another machine or repo.

On top of those, two orchestration workflows:

- **`router.json`** — the generic building block. Takes `{ role,
  prompt }` (via Manual Trigger + Set Defaults for standalone
  testing, or via an Execute Workflow Trigger when called as a
  sub-workflow) and runs the same resolve-config → call-Ollama →
  extract-reply chain as the per-role workflows, but for whichever
  role is given at runtime. The 5 per-role workflows above are now
  redundant with `router.json` — kept for now since they were built
  first and already work, but new role invocations should go through
  the router instead of duplicating the chain again.
- **`pipeline.json`** — a sequential demo: Set Feature Request → Call
  PM → Call Backend Dev → Call QA, each "Call X" an **Execute
  Workflow** node invoking `router.json` (referenced by its fixed
  workflow ID, `841e2429-310c-40c8-914e-9a75fd7bce34`) with a
  different `{role, prompt}`, where each step's prompt is built from
  the previous step's reply. Simulates a PM writing a story → Backend
  Dev implementing it → QA listing test cases, in one run. 3
  sequential Ollama calls — expect it to take a while, especially on
  the first run since `pm`'s model has a short `keep_alive` and
  reloads cold.

**Importing**: the n8n editor's "Import from File" dialog rejected
these files in testing (generic "doesn't seem to be a workflow JSON"
error) even though the JSON is well-formed. The CLI importer accepts
them without issue:

```bash
npx n8n import:workflow --input=.ai/workflows/<role>.json
```

## How a workflow resolves a role's config

Before calling Ollama, a workflow resolves the role's configuration
(model, temperature, context size, keep_alive) through an **HTTP
Request** node that calls a small local server wrapping
`BindingLoader`:

```
GET http://127.0.0.1:4567/bindings/<role>
```

The profile isn't in the URL — the server defaults to the `profile`
declared in `.ai/config.yml`, so workflows don't hardcode it. Pass
`?profile=<name>` to override it for a single call (e.g. testing a
different machine's profile without touching `config.yml`).

It returns a single JSON object:

```json
{"role":"backend_dev","model":"qwen2.5-coder:14b","temperature":0.2,"num_ctx":16384,"keep_alive":-1,"db":{"enabled":false}}
```

The next node uses that JSON to build the `POST /api/chat` request
sent directly to Ollama (`ollama_host` from the profile,
`http://localhost:11434` by default).

**Why a server instead of the `binding_loader.rb` CLI directly**:
sub-workflows invoked via the **Execute Workflow** node run in a
restricted execution context that doesn't load the **Execute
Command** node (`Unrecognized node type: n8n-nodes-base.executeCommand`)
— confirmed both via `n8n execute` headlessly and from the full
running server. A plain HTTP Request node works in every execution
context, so `router.json` (and, for consistency, the 5 standalone
role workflows) call this server instead. `binding_loader.rb`'s own
CLI still exists and still works standalone (manual use, other
tooling) — the server (`.ai/scripts/server.rb`) is a thin Sinatra
wrapper around the same `BindingLoader` class, kept in sync rather
than duplicated.

Start it before running any workflow that resolves a role's config:

```bash
bundle exec ruby .ai/scripts/server.rb
```

It binds to `127.0.0.1:4567`. Use `127.0.0.1`, not `localhost`, in
workflow URLs — n8n's HTTP Request node can resolve `localhost` to
the IPv6 loopback (`::1`), which the server (IPv4-only) won't accept,
producing `ECONNREFUSED`.

## Naming convention

One exported workflow per role, named `<role>.json` (e.g.
`backend_dev.json`) — the exported file name must match exactly the
`name` declared in that role's frontmatter (`roles/*.md`).
Orchestration workflows that aren't tied to a single role use a
descriptive name instead (`router.json`, `pipeline.json`).

## Known limitation: hardcoded workflow ID

`pipeline.json` references `router.json` by its fixed `id` field
(`841e2429-310c-40c8-914e-9a75fd7bce34`), set explicitly in
`router.json` so it's predictable. If `router.json` is ever
re-imported with a different `id`, `pipeline.json`'s three "Call X"
nodes will silently point at a workflow that no longer exists (or a
different one) — re-import both together, or update the `workflowId`
in `pipeline.json` if `router.json`'s id changes.

## Known limitation: published workflows

This n8n version requires a workflow to be **published** before it
can be invoked as a sub-workflow via an Execute Workflow node —
importing it isn't enough (`Workflow is not active and cannot be
executed.`). After importing or changing `router.json`:

```bash
npx n8n publish:workflow --id=841e2429-310c-40c8-914e-9a75fd7bce34
```

If the n8n server is already running, restart it for the published
change to take effect.
