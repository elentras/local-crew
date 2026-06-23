# Workflows

This folder holds exported n8n workflow JSON files that orchestrate
the agent crew.

All 5 roles now have a workflow (`cto.json`, `pm.json`,
`backend_dev.json`, `frontend_dev.json`, `qa.json`), each following
the same chain: Manual Trigger → Set Prompt → Execute Command
(`binding_loader.rb`) → Code (build the Ollama payload) → HTTP
Request (`POST /api/chat`) → Code (extract the reply). The only
differences between them are the role name passed to
`binding_loader.rb`, the system message, and the example prompt in
"Set Prompt". They hardcode the repo's absolute path in the Execute
Command node and `http://localhost:11434` in the HTTP Request node —
fine for a first local proof of concept, but worth revisiting (env
var or n8n credential) before this travels to another machine or
repo. No `orchestrator.json` yet — each role's workflow still runs
standalone, nothing routes between roles.

**Importing**: the n8n editor's "Import from File" dialog rejected
these files in testing (generic "doesn't seem to be a workflow JSON"
error) even though the JSON is well-formed. The CLI importer accepts
them without issue:

```bash
npx n8n import:workflow --input=.ai/workflows/<role>.json
```

## How a workflow resolves a role's config

Before calling Ollama, a workflow resolves the role's configuration
(model, temperature, context size, keep_alive) through an **Execute
Command** node that calls `binding_loader.rb`:

```bash
ruby .ai/scripts/lib/binding_loader.rb --role backend_dev --profile mac-studio-64gb
```

It prints a single JSON object to stdout:

```json
{"role":"backend_dev","model":"qwen2.5-coder:14b","temperature":0.2,"num_ctx":16384,"keep_alive":-1,"db":{"enabled":false}}
```

The next node parses that JSON and uses it to build the
`POST /api/chat` request sent directly to Ollama (`ollama_host` from
the profile, `http://localhost:11434` by default). `binding_loader.rb`
never makes a network call itself — it only resolves config.

**Why a CLI instead of a dedicated HTTP server**: it's the simplest
thing that works, consistent with not building infrastructure ahead
of a real need. If usage grows (several workflows running
concurrently, subprocess latency becoming noticeable), a small
Sinatra/Rack server wrapping the same classes (`BindingLoader`,
`RamEstimator`) is a possible evolution without rewriting the
underlying logic.

## Naming convention

One exported workflow per role, named `<role>.json` (e.g.
`backend_dev.json`), plus an optional `orchestrator.json` for the
workflow that routes between roles. The exported file name must match
exactly the `name` declared in that role's frontmatter
(`roles/*.md`).
