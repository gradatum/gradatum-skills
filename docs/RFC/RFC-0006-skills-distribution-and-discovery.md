---
rfc: RFC-0006
title: Skills distribution and discovery (with vault-discipline reference skill)
status: Draft
author: '@gradatum-maintainer'
created: 2026-05-08
updated: 2026-05-10
version: 1
depends_on: []
required_by: []
related_to:
  - gradatum:RFC-0003
  - gradatum:RFC-0005
category: feature
scope: gradatum-engine
crates_touched:
  - gradatum-admin
  - gradatum-server
phase_target: "Phase 3 (no blocking dependencies; can land independently of other Phase 3 RFCs)"
tracking_issue: backlog Phase 3
license: Apache-2.0
---

# RFC-0006 — Skills distribution and discovery (with `vault-discipline` reference skill)

## Status note

This RFC formalises **how Gradatum bundles, distributes and surfaces Anthropic-format skills** to LLM clients, AND introduces the first reference skill (`vault-discipline`) as a normative annex. The two are bundled in one RFC because the convention only makes sense alongside a concrete first example — and the first example only makes sense once the convention is ratified.

The RFC can be implemented incrementally:

1. Land `examples/skills/vault-discipline/SKILL.md` (Annex A) and `examples/skills/README.md` (Annex B) — pure documentation, no code.
2. Add `gradatum-admin skills install/list/uninstall` subcommand.
3. Add the MCP `instructions` hint in `gradatum-server` initialize.

Each step is independently useful. Step 1 alone gives the discipline to operators willing to copy the skill manually. Steps 2 and 3 reduce friction but are not strictly required.

---

## 1. Motivation

Gradatum exposes itself to LLM agents through three MCP channels: **tools** (read/write/search), **resources** (note contents, presets), **prompts** (templated commands). None of these is the right channel for instructions that guide *how* an agent should use the vault — the retrieve-before-reason discipline, the section-scope rules, the write-then-purge pattern, the prompt-cache layering.

These are conduct rules, not data and not actions. The Anthropic Skills format is the right primitive for them: a `SKILL.md` markdown file with a `description` frontmatter that drives the LLM client's auto-discovery; the client loads the skill into context when the conversation matches.

Without a clear convention for how Gradatum ships and surfaces these skills, three problems accumulate:

- Operators who deploy Gradatum get no guidance on how their agents should behave; the vault accumulates poorly-classified, non-atomic notes.
- Each operator reinvents the discipline from scratch in their system prompt, with varying quality.
- Improvements to the discipline (better retrieval timing, better cache structure) cannot propagate — every operator's prompt is bespoke.

Concretely, an agent without `vault-discipline` typically writes one giant `retrospectives` note at the end of a 4-hour session, accumulates 40k+ tokens of working buffer mid-session, and produces notes too coarse to be retrievable point-by-point. An agent with the skill writes 20-40 atomic notes during the same session, stays under 15k tokens of buffer, and produces a vault that compounds in value.

This RFC commits to four decisions:

1. A canonical location in the repo for bundled skills: `examples/skills/`.
2. A standard install mechanism via `gradatum-admin skills`.
3. A non-intrusive discovery hint via MCP `initialize.instructions`.
4. A reference first skill (`vault-discipline`) that codifies the discipline.

---

## 2. Design

### 2.1 Repository layout

```
gradatum/
├── examples/
│   ├── presets/                              (existing — ACL templates)
│   └── skills/                               (NEW)
│       ├── README.md                         (catalogue + install)
│       └── vault-discipline/
│           └── SKILL.md
```

`examples/skills/` is symmetrical with the existing `examples/presets/`. Both are opt-in resources bundled with the project, distinct from the runtime core. An operator can ignore `examples/` entirely and Gradatum still runs.

### 2.2 SKILL.md format

Each skill follows the Anthropic Skills format strictly:

```yaml
---
name: <slug>                  # kebab-case, must match directory name
description: |
  Multi-line description that drives auto-activation.
  Mentions concrete triggers: vault, gradatum tools, etc.
license: Apache-2.0
version: 0.1.0
---

# Body markdown
...
```

Required frontmatter fields:

| Field | Purpose | Required |
|---|---|---|
| `name` | Slug, kebab-case, must match directory name | Yes |
| `description` | Drives client-side auto-activation | Yes |
| `license` | Must be `Apache-2.0` for bundled skills | Yes |
| `version` | SemVer; bumped on substantive change | Yes |

Validation by CI: a small Rust test in `gradatum-admin` parses every bundled SKILL.md and rejects PRs that fail any required-field or naming check.

### 2.3 Install mechanism — `gradatum-admin skills`

A new subcommand of `gradatum-admin`:

```rust
#[derive(Parser)]
enum SkillsCommand {
    /// Install all bundled skills into the local Claude skills directory
    Install {
        /// Override the default target directory
        #[arg(long)]
        target: Option<PathBuf>,
        /// Install only specific skills (default: all)
        #[arg(long, value_delimiter = ',')]
        only: Vec<String>,
        /// Overwrite existing skills with the bundled version
        #[arg(long)]
        force: bool,
        /// Show what would be installed without writing
        #[arg(long)]
        dry_run: bool,
    },
    /// List skills currently installed in the target directory
    List {
        #[arg(long)]
        target: Option<PathBuf>,
    },
    /// Remove a previously-installed skill
    Uninstall {
        name: String,
        #[arg(long)]
        target: Option<PathBuf>,
    },
}
```

Default target resolution:

| Platform | Default target |
|---|---|
| Linux / macOS | `$HOME/.claude/skills/` |
| Windows | `%USERPROFILE%\.claude\skills\` |
| Override 1 | `--target <path>` flag |
| Override 2 | `GRADATUM_SKILLS_TARGET` env var |
| Precedence | CLI > env > default |

Idempotent: re-running `install` on an existing target without `--force` detects identical skills (compare `version` field) and skips them. Differing versions warn and require `--force` to overwrite.

### 2.4 Embedding skills in the `gradatum-admin` binary

The skills are embedded at compile time using the `include_dir` crate (workspace dep, already used for ACL presets):

```rust
use include_dir::{include_dir, Dir};

static BUNDLED_SKILLS: Dir<'_> =
    include_dir!("$CARGO_MANIFEST_DIR/../../examples/skills");

pub fn install_all(target: &Path, force: bool, dry_run: bool) -> Result<InstallReport> {
    let mut report = InstallReport::default();
    for skill_dir in BUNDLED_SKILLS.dirs() {
        let name = skill_dir.path().file_name()
            .ok_or_else(|| anyhow!("skill missing name"))?
            .to_string_lossy();
        let dest = target.join(&*name);
        match (dest.exists(), force, dry_run) {
            (true, false, _) => report.skipped.push(name.into()),
            (_, _, true) => report.would_install.push(name.into()),
            _ => {
                std::fs::create_dir_all(&dest)?;
                for file in skill_dir.files() {
                    let file_name = file.path().file_name().unwrap();
                    std::fs::write(dest.join(file_name), file.contents())?;
                }
                report.installed.push(name.into());
            }
        }
    }
    Ok(report)
}
```

This produces a self-contained binary: `gradatum-admin` ships with the skills embedded; no separate file distribution.

### 2.5 MCP discovery hint

The MCP protocol (rmcp 0.17) `initialize` response carries an optional `instructions` string that clients can surface to the LLM as a session-level hint. Gradatum populates this field:

```rust
// In gradatum-server::mcp::handler.rs
fn initialize(&self, _params: InitializeParams) -> Result<InitializeResult> {
    Ok(InitializeResult {
        protocol_version: PROTOCOL_VERSION,
        capabilities: self.capabilities.clone(),
        server_info: ServerInfo {
            name: "gradatum-server".into(),
            version: env!("CARGO_PKG_VERSION").into(),
        },
        instructions: Some(BUNDLED_INSTRUCTIONS_HINT.to_string()),
    })
}

const BUNDLED_INSTRUCTIONS_HINT: &str = "\
Gradatum is a memory backbone for AI agents. For best results, ensure the \
recommended skills are installed locally (Anthropic Skills format). The \
`vault-discipline` skill in particular guides correct retrieve-write-purge \
patterns when interacting with vault notes. \
Install via: `gradatum-admin skills install`.";
```

The hint is text only, ~250 characters. Clients that don't understand or display `instructions` ignore it harmlessly.

This is the only **server-side** mechanism. The skill itself is loaded from the **client's** local skills directory by the LLM client — the MCP server never injects skill content into prompts. This keeps the trust boundary clean.

### 2.6 Skill activation flow

```
[Operator install (one-time)]
   │
   ▼
gradatum-admin skills install
   │  → ~/.claude/skills/vault-discipline/SKILL.md
   ▼
[Per-session, automatic]
   │
   ▼
Claude client connects to gradatum-server (MCP)
   │
   ▼ initialize handshake
gradatum-server returns instructions hint
   │
   ▼
Claude client also reads its local ~/.claude/skills/ catalogue
   │
   ▼
Operator: "Show me notes about ROCm in the vault"
   │
   ▼
Claude detects context match (vault keywords + gradatum-search tool)
   │
   ▼
Claude auto-loads vault-discipline SKILL.md into the working context
   │
   ▼
Claude follows discipline: retrieves first, writes atomically, purges,
respects section scope, structures prompt for cache efficiency
```

No coupling tighter than the `instructions` hint. The skill works fine without the hint. The hint works fine without the skill. Both work better together.

### 2.7 Versioning

- Each `SKILL.md` carries `version: <semver>` in frontmatter.
- PATCH bump (`0.1.0 → 0.1.1`): typo fixes, clarifications, no semantic change.
- MINOR bump (`0.1.0 → 0.2.0`): rule additions, new sections, new triggers in description.
- MAJOR bump (`0.1.0 → 1.0.0`): rule removal, rule semantic inversion, breaking conduct change.
- The bundled skill version moves with Gradatum releases. A skill installed from Gradatum v0.1.0 keeps working with Gradatum v0.2.0 if no MAJOR upgrade happened to that skill.
- `gradatum-admin skills install` warns when an installed skill is older than the bundled one and offers `--force` for upgrade.

---

## 3. Impact downstream

| Component | Impact | Effort |
|---|---|---|
| `examples/skills/` | New top-level subdirectory; first content (Annex A + B) | — |
| `gradatum-admin` | New `skills` subcommand (install/list/uninstall) + `include_dir!` embed | ~200 LOC |
| `gradatum-server` | New `instructions` field populated in initialize response | ~10 LOC |
| `gradatum-admin` test suite | SKILL.md frontmatter validation test | ~50 LOC |
| `CONTRIBUTING.md` | New section "Contributing a skill" | ~30 lines |
| Schema | None | — |
| Default ports | None | — |
| Default LLM | None | — |

Public API surface impact: 1 new `gradatum-admin` subcommand. No breaking change. No effect on `gradatum-core` traits.

---

## 4. Migration path

N/A — additive only. Existing operators do not need to take any action.

For operators upgrading from a Gradatum that pre-dates this RFC:

```bash
# Optional one-time install of bundled skills
gradatum-admin skills install --dry-run
gradatum-admin skills install
```

Rollback: skills are pure markdown in the operator's home directory. Removal via `gradatum-admin skills uninstall vault-discipline` or simple `rm -rf`.

---

## 5. Alternatives considered

| Alternative | Pros | Cons | Reason rejected |
|---|---|---|---|
| Do nothing — let operators write their own system prompts | No effort | Discipline is reinvented per operator with varying quality; improvements don't propagate | Section 1 quantified the problem |
| Push skills via MCP `resources` channel | Server-side delivery, no install step | LLM client must know to read and hoist a specific resource as instructions; no convention exists for that; protocol mis-use | Trust boundary violated |
| Inject skill content as system prompt prefix on every tool call | Always-on | MCP server cannot add to system prompt; protocol limitation; would also bloat every request | Technically not allowed |
| Distribute skills as a separate crate published to crates.io | Reuses cargo ecosystem | Skills are markdown, not Rust; cargo is the wrong tool | Wrong distribution channel |
| Place skills in `skills/` at the repo root | More visible | Breaks symmetry with `examples/presets/`; suggests skills are runtime when they're not | Repo aesthetic + signal |
| Auto-write skills to client filesystem on MCP connect | Zero operator action | MCP server should not write to client's home dir; massive trust violation | Security |

---

## 6. Drawbacks

- **Adds another moving part.** Yet another thing operators can have wrong: skill installed but stale, skill missing, skill version mismatched. The install command tries to be idempotent and the version check tries to warn, but failures here are silent (the LLM just doesn't apply the discipline).
- **Discovery is probabilistic.** Anthropic Skills auto-activate based on description matching. If the description doesn't trigger on the right context, the skill stays inert. Tuning the description is critical and hard to validate without real-world traffic.
- **Not all MCP clients support skills.** Claude Desktop and Claude Code do. Other MCP clients (Continue.dev, Cline, Zed AI, custom integrations) consume tools but not skills. For these, the skill content has to be manually pasted into the system prompt — manual operator action.
- **Couples Gradatum loosely to Anthropic Skills format.** If Anthropic changes the format, bundled skills must follow. Currently the format is open and stable; this is a future risk.
- **Adds compile time.** `include_dir!` at build time on every PR adds a few hundred ms to `gradatum-admin` compilation. Acceptable.

> **AM4 reminder:** this section must be authored without AI assistance. The author should be able to defend it in a synchronous review without referring to generated text.

---

## 7. Unresolved questions

- [ ] Should `gradatum-admin skills install` run as part of `apt install gradatum` post-install hook, or always require explicit operator command? Default proposal: explicit only.
- [ ] Should bundled skills be language-localised? Currently English-only (matches public docs). Operators with non-English vaults may want translations. Defer to first localisation request.
- [ ] Versioning across upgrades: should `gradatum-admin skills install --force` preserve operator-edited skills, or overwrite without question? Proposal: warn on edit detection, require `--force-overwrite-edits`.
- [ ] Should skills be tenant-scoped? Different tenants may want different conventions. Currently skills are global per-client. Out of scope for this RFC.
- [ ] Public skill registry: should a future `gradatum.org/skills` directory list community-contributed skills outside the repo? Out of scope; deferred until 5+ bundled skills exist.

---

## References

- Gradatum architecture: `ARCHITECTURE.md`
- Existing presets pattern: `examples/presets/`
- Anthropic Skills format: https://docs.claude.com/en/docs/claude-code/skills
- MCP protocol initialize response: rmcp 0.17 docs
- Cross-references: `gradatum:RFC-0003` (HTTP API), `gradatum:RFC-0005` (self-improvement, references skills format in §17.7)

---

## Annex A — `examples/skills/vault-discipline/SKILL.md` (normative)

The following is the full content of the first bundled skill, to be placed at `examples/skills/vault-discipline/SKILL.md`. It is normative: any change to this annex requires a new revision of this RFC or, post-acceptance, a PR following the standard skill-contribution process documented in Annex B.

See source file in gradatum main repo: `examples/skills/vault-discipline/SKILL.md` (to be created at implementation time, content defined in this RFC — `gradatum-skills:RFC-0006`).

---

## Annex B — `examples/skills/README.md` (normative)

The catalogue README is to be placed at `examples/skills/README.md`. See this RFC (`gradatum-skills:RFC-0006`) Annex B for normative content.

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-08 | @gradatum-maintainer | Initial creation, status: Draft |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0009 → RFC-0006, table header → YAML frontmatter, refs mises à jour |

---

## License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-0006.*
