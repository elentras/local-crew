# local-crew
Your AI team. Your machine. Your rules.

---
A modular system for simulating an IT team (CTO, PM, Backend Dev,
Frontend Dev, QA) as local AI agents — orchestrated with n8n and
served by Ollama, with zero data leaving your machine.

Role definitions, LLM bindings, and optional RAG (pgvector) are
strictly decoupled: change machines, scale up models, or swap a
database — without ever touching agent behavior.

# Setup

First, you have to check and define your roles, in .ai/roles. Precise the technologies used for each role to ensure it will respect it. Being precise with versions major and minor can help.

Then declare a machine profile in `.ai/profiles/` (how much RAM is available for models) and a matching binding in `.ai/bindings/` (which model serves which role on that machine). Validate the pair against your local Ollama instance:

```bash
bundle install
bundle exec ruby .ai/scripts/validate_bindings.rb <profile-name>
```

# Conventions

**All code comments, JSON Schema descriptions, YAML comments, and
runtime messages (errors, warnings, CLI output) must be written in
English.** This is mandatory for anyone contributing to this repo,
regardless of what language the surrounding conversation or task
description happens to be in — the codebase itself stays readable to
any future, non-French-speaking contributor. Role system prompts
(`.ai/roles/*.md`) follow the same rule.

# Why n8n, not CrewAI

Orchestration runs on n8n's visual workflows calling Ollama over
plain HTTP, not a Python agent framework like CrewAI/LangGraph. This
keeps the whole stack to Ruby + n8n: no Python runtime to maintain
alongside it (notably on Apple Silicon, where the Python ML ecosystem
is the more fragile piece to keep working), and no second language
for the validation tooling to interoperate with. A workflow resolves
a role's config by shelling out to a small Ruby CLI
(`binding_loader.rb`, see [Workflows](#workflows) below) and then
talks to Ollama directly — n8n never needs to know how `.ai/` is laid
out internally.

# Philosophy: role, binding, profile

Three concerns, strictly separated, each living in its own folder:

| Folder | Answers | Varies with |
|---|---|---|
| `roles/` | How this role behaves, on which tech stack | Nothing — stable across machines and consumer projects |
| `profiles/` | What the machine can handle (RAM, Ollama host) | The machine |
| `bindings/` | Which LLM serves which role, on which profile | The (role, machine) pair |

**A role never references a model.** `roles/backend-dev.md` describes a system prompt and a stack (Ruby on Rails) — it has no idea whether it runs on `qwen2.5-coder:14b` or anything else. That mapping lives exclusively in `bindings/`. Switching machines, or upgrading a model, never touches `roles/`.

**The tech stack is a property of the role, not of the binding.** The frontend role is React + Tailwind everywhere it's used — that doesn't depend on the machine or the consumer project.

The point of this separation: the same crew can be deployed on several machines (a 64GB Mac Studio today, a lighter machine tomorrow) and reused as-is across several projects, without ever duplicating or rewriting agent behavior.

# Structure

```
.ai/
├── roles/                  # behavior + tech stack, model-agnostic
│   ├── cto.md
│   ├── pm.md
│   ├── backend-dev.md
│   ├── frontend-dev.md
│   └── qa.md
├── profiles/                # declared machine capacity
│   └── mac-studio-64gb.yml
├── bindings/                # role -> model + db, per profile
│   └── mac-studio-64gb.yml
├── schema/                  # JSON Schemas, validated against by binding_loader.rb
│   ├── role.schema.json
│   └── bindings.schema.json
├── workflows/                # n8n workflow exports + integration convention
│   └── README.md
└── scripts/
    ├── validate_bindings.rb  # CLI: validates a binding against its profile + Ollama
    ├── pull_models.rb        # CLI: pulls every model in a binding not yet installed
    └── lib/
        ├── ollama_client.rb  # GET /api/tags, POST /api/chat, POST /api/pull — net/http only
        ├── binding_loader.rb # loads + schema-validates a binding; own CLI for n8n
        └── ram_estimator.rb  # missing-model check + RAM budget math

spec/                         # tooling tests — local-crew's own, don't travel with .ai/
├── validate_bindings_spec.rb
├── pull_models_spec.rb
├── fixtures/
└── lib/
    ├── ollama_client_spec.rb
    ├── binding_loader_spec.rb
    └── ram_estimator_spec.rb
```

Tests live at the repo root, not inside `.ai/`: copying `.ai/` into a
consumer project shouldn't also dump local-crew's own RSpec suite
into that project's `spec/` folder. Validating the tooling is this
repo's concern; once `.ai/` is copied elsewhere, the script is
trusted as-is.

## Role format (`roles/*.md`)

YAML frontmatter + a markdown body (the system prompt):

```markdown
---
name: backend_dev
tools: [read_file, write_file, run_tests, run_migrations]
output_format: code
stack:                    # optional — omitted for cto/pm/qa
  language: Ruby
  framework: Rails
  testing: RSpec
---

[system prompt...]
```

The `stack` block only makes sense for roles that produce code (`backend_dev`, `frontend_dev`) — it's absent from the others.

## Profile format (`profiles/*.yml`)

```yaml
total_memory_gb: 64
reserved_system_gb: 8
available_for_models_gb: 56
max_concurrent_models: 3
ollama_host: "http://localhost:11434"
```

## Binding format (`bindings/*.yml`)

```yaml
backend_dev:
  model: qwen2.5-coder:14b
  temperature: 0.2
  num_ctx: 16384
  keep_alive: -1
  db:
    enabled: false   # justified in a comment next to each role
```

Convention: `bindings/<name>.yml` always matches `profiles/<name>.yml` (same file name).

# Validation tooling

`scripts/validate_bindings.rb` is a thin CLI that wires together three single-purpose classes under `scripts/lib/`:

- **`BindingLoader`** loads a profile + binding by name and validates the binding's structure against `schema/bindings.schema.json` (via the `json-schema` gem — pinned to draft-06 syntax, since that gem doesn't support draft-07).
- **`OllamaClient`** wraps `GET /api/tags` and `POST /api/chat` over `net/http` — never an `ollama` subprocess.
- **`RamEstimator`** cross-checks the binding's models against what `OllamaClient` reports installed, then sums the real on-disk size (in bytes, from the API's `size` field — not a hand-maintained table) of every model whose `keep_alive` is long enough to realistically overlap another model in a working session (`-1`, or a duration ≥ 5 minutes). It fails if that total exceeds `available_for_models_gb`, warns (without failing) if the margin drops under 10%, and fails if the number of persistent models exceeds `max_concurrent_models`.

```bash
bundle exec ruby .ai/scripts/validate_bindings.rb mac-studio-64gb
```

Exits non-zero with an explicit message (missing model + suggested `ollama pull`, RAM overshoot, or too many persistent models for the profile) instead of failing silently.

## Pulling models

`scripts/pull_models.rb` provisions a binding: it diffs the binding's
models against `OllamaClient#installed_models` and pulls only the
ones missing, via `POST /api/pull` (streamed, so progress prints as
it downloads) — never an `ollama pull` subprocess.

```bash
bundle exec ruby .ai/scripts/pull_models.rb mac-studio-64gb
```

Already-installed models are skipped; nothing re-downloads on a
second run.

## Tests

```bash
bundle exec rake spec
```

Tests stub the Ollama API via `webmock` — no real Ollama instance is required to run them.

# Workflows

n8n workflows resolve a role's config at runtime by calling `binding_loader.rb` directly as a CLI:

```bash
ruby .ai/scripts/lib/binding_loader.rb --role backend_dev --profile mac-studio-64gb
```

which prints the resolved config as JSON on stdout for an n8n **Execute Command** node to parse, before the next node calls Ollama's `/api/chat` directly. See [`.ai/workflows/README.md`](.ai/workflows/README.md) for the full convention (naming, why CLI over an HTTP server for now).

# Adding a new profile

1. Create `profiles/<machine-name>.yml` with the machine's RAM characteristics.
2. Create `bindings/<machine-name>.yml` with one model per role, sized to fit `available_for_models_gb`.
3. Validate: `bundle exec ruby .ai/scripts/validate_bindings.rb <machine-name>`.

`roles/` files never change for this.

# Reusing `.ai/` in another project

The `.ai/` folder is self-contained: copy it as-is to the root of the consumer project.

```bash
cp -r local-crew/.ai /path/to/project/.ai
```

The `.ai/` name is deliberately generic and decoupled from the `local-crew` repo name — nothing in this repo assumes it will still be called `local-crew` once copied elsewhere.

# Possible extensions (not implemented)

- **Per-project stack override**: today a role's stack (e.g. Rails for `backend_dev`) is fixed and shared across every consumer project. If projects ever needed different stacks for the same role, that would require a per-project override mechanism. Deliberately not implemented until a real need forces it.
- **HTTP server instead of CLI for `binding_loader.rb`**: fine as a CLI while a single workflow calls it occasionally. If usage grows (several concurrent workflows, subprocess latency becoming noticeable), wrapping the same classes in a small Sinatra/Rack server is a possible evolution — see `.ai/workflows/README.md`.
