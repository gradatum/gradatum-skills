---
rfc: RFC-0004
title: "Curator: zero-loss compression and dedup with fidelity guard"
status: Draft
author: '@the operator'
created: 2026-05-08
updated: 2026-05-10
version: 1
depends_on:
  - RFC-0001
required_by: []
related_to:
  - RFC-0003
category: feature
scope: gradatum-engine
crates_touched:
  - gradatum-curator
  - gradatum-core
  - gradatum-vault
  - gradatum-storage
phase_target: "Phase 4+ (after RFC-0001 reflective curator stabilized + ≥6 months D5 dogfooding)"
tracking_issue: backlog Phase 4+
license: Apache-2.0
---

# RFC-0004 — Curator: zero-loss compression and dedup with fidelity guard

## Status note

This RFC is a **future feature proposal** captured 2026-05-08. It is **NOT in scope** for `v0.1.0-alpha.6`, `v0.1.0-rc.1`, or `v0.1.0` stable. It targets Phase 4+ once the curator's reflective improvement loop (RFC-0001) is stabilized and the operator has a track record of corrections to weight the cleaner's behavior on.

The mode `evolutionary` (genetic programming over rewrite operators) is presented but flagged experimental — Phase 4+ minimum, possibly v2.x.

---

## 1. Motivation

A vault that has been used daily for ≥6 months accumulates entropy:

- Notes that should have been merged but weren't (operator intent + timing mismatch)
- Drafts left as `status=pending_review` for months
- Verbose descriptions that paraphrase the same fact in 3 ways
- Outdated links pointing to deprecated concepts

The curator's existing `dedup` function (Phase 2.0c) handles obvious duplicates at write-time. It does NOT handle accumulated bloat. After 1000+ notes, manual cleanup becomes infeasible.

This RFC proposes a cleaner pipeline that **rewrites notes in place** while guaranteeing **zero semantic loss**:

- The original content is always preserved in `vault/cleaner-archive/` (ULID + content_hash addressable).
- The rewrite is published only if the validator confirms semantic equivalence above a threshold.
- Three modes cover the spectrum from conservative (token-only) to aggressive (concept-restructuring) to evolutionary (genetic programming on rewrite ops).
- The validator is an LLM judge (Qwen3.6-27B THINKING <inference-host> :8081 (deep on-demand, ctx 128K, pas de nouveau modèle requis — alternative Qwen3.6-35B-A3B :8080) recommended) that compares the original vs. rewrite on a recall-of-key-claims metric.

The motivation is concrete: a memory backbone that grows monotonically becomes unusable. Operators need a tool to compact without losing.

---

## 2. Design

### 2.1 Three modes

| Mode | Operations | Risk | Use case |
|---|---|---|---|
| `conservative` | Whitespace normalization, redundant header collapse, broken-link removal | Very low | Daily background sweep |
| `aggressive` | Sentence merging, redundant paragraph removal, restating-the-obvious removal | Medium | Quarterly compaction |
| `evolutionary` | Genetic programming search over rewrite ops; fitness = recall_semantic - λ * len_ratio | High (experimental) | Annual or post-major-migration |

Plus four validation modes (orthogonal):

| Validation | Method | False-positive risk |
|---|---|---|
| `strict` | Sentence-level alignment + cosine ≥ 0.95 per sentence | Very low — accepts almost no rewrites |
| `semantic` (default) | LLM judge on recall of key claims (≥ 0.90) | Low |
| `threshold` | Cosine on full embeddings ≥ 0.92 | Medium |
| `permissive` | Operator's manual review | Operator-bounded |

Combinations are pre-set via `cleaner.preset`:

| Preset | Mode | Validation |
|---|---|---|
| `safe` (default) | conservative | strict |
| `balanced` | aggressive | semantic |
| `compress_max` | evolutionary | semantic |
| `explore` | evolutionary | permissive |

### 2.2 Pipeline

```
gradatum-vault::list_notes(filter)
        │
        ▼ batch (max 50 notes per cycle)
   ① Cleaner::propose_rewrite(note, mode)
        │  → Rewrite candidate + diff
        ▼
   ② Validator::check(original, rewrite, validation_mode)
        │  → ValidationVerdict { score, accepted, rationale }
        ▼
   ③ Archive original
        │  → vault/cleaner-archive/<ulid>.<content_hash>.md
        ▼
   ④ Apply rewrite
        │  → gradatum-vault::write_rewrite(note_id, rewrite, audit_trail)
        ▼
   ⑤ Audit log entry
        │  → AuditEvent { type: 'cleaner.rewrite', note_id, scores, mode }
```

### 2.3 New traits in `gradatum-core::cleaner`

```rust
#[async_trait]
pub trait Cleaner: Send + Sync {
    async fn propose_rewrite(&self, note: &Note, mode: CleanerMode) -> Result<Option<Rewrite>>;
}

#[async_trait]
pub trait CleanerValidator: Send + Sync {
    async fn check(
        &self,
        original: &Note,
        rewrite: &Rewrite,
        mode: ValidationMode,
    ) -> Result<ValidationVerdict>;
}

pub struct Rewrite {
    pub body_after: String,
    pub frontmatter_after: Frontmatter,
    pub ops_applied: Vec<RewriteOp>,
    pub len_ratio: f32,
}

pub struct ValidationVerdict {
    pub accepted: bool,
    pub recall_score: f32,
    pub embedding_similarity: f32,
    pub rationale: String,
}
```

### 2.4 Genetic programming mode (experimental)

For `mode = evolutionary`:

```
RewriteOp ::= MergeSentences(i, j)
            | RemoveRedundantParagraph(i)
            | InlineWikilink(target)
            | ReorderSections([i, j, ...])
            | TighteningPass(percentile)
            | ExtractToReference(span)

Genome = [RewriteOp; <variable>]

Fitness(genome) = w1 * recall_semantic(original, apply(genome, original))
                - w2 * len_ratio(apply(genome, original))
                - w3 * structural_disruption(genome)
```

Defaults: `w1 = 1.0`, `w2 = 0.3`, `w3 = 0.1`. K = 8 candidates × G = 5 generations. Mutation rate 0.15, crossover rate 0.6.

### 2.5 Archive directory

```
~/.gradatum/vaults/main/cleaner-archive/
└── 01HX7P9.../                       (ULID-prefixed by year-month)
    ├── note-original.md              (full original)
    └── meta.json                     (rewrite ops + scores + timestamp)
```

The archive is `read-only` to all operators except `admin`. Restoration command:

```bash
gradatum-admin cleaner restore --note-id 01HX... --version archive
```

### 2.6 New tables in `gradatum-index`

```sql
CREATE TABLE cleaner_rewrites (
    id TEXT PRIMARY KEY,
    note_id TEXT NOT NULL,
    archive_path TEXT NOT NULL,
    mode TEXT NOT NULL,
    validation_mode TEXT NOT NULL,
    recall_score REAL NOT NULL,
    embedding_similarity REAL NOT NULL,
    len_ratio REAL NOT NULL,
    ops_applied JSON NOT NULL,
    rationale TEXT,
    applied_at TIMESTAMP NOT NULL,
    applied_by TEXT NOT NULL,
    tenant_id TEXT NOT NULL
);

CREATE INDEX idx_cleaner_rewrites_note ON cleaner_rewrites(note_id);
```

Migration `0012_cleaner.sql`.

---

## 3. Impact downstream

| Component | Impact | Effort |
|---|---|---|
| `gradatum-curator` | New module `cleaner` with `Cleaner` + `CleanerValidator` impls | ~1500 LOC |
| `gradatum-core` | New types in `cleaner` submodule (experimental) | ~120 LOC |
| `gradatum-vault` | New method `write_rewrite()` (archives original + applies rewrite atomically) | ~80 LOC |
| `gradatum-storage` | New reserved directory `cleaner-archive/` | ~30 LOC |
| `gradatum-index` | Migration `0012_cleaner.sql` + repository accessor | ~150 LOC |
| `gradatum-worker` | New job type `CleanerSweepJob` | ~150 LOC |
| `gradatum-server` | New endpoints `POST /api/v1/cleaner/dry-run`, `GET /api/v1/cleaner/archive/:note_id` | ~120 LOC |
| `gradatum-cli` | New subcommand `gradatum cleaner {dry-run, run, restore, status}` | ~150 LOC |
| Schema | 1 new table + 1 migration + 1 reserved directory | — |
| Default LLM | None — uses `cleaner.validator_model` config (NEW) | — |
| CI requirements | Cleaner gold set (~50 hand-rewritten note pairs) | — |

Public API surface impact: 2 new traits in `gradatum-core::cleaner` tagged `experimental`. No breaking change.

---

## 4. Migration path

N/A — additive only. Default mode is `safe` (conservative + strict) which has near-zero risk.

For a first activation, operators run dry-run first:

```bash
gradatum-admin cleaner dry-run --tenant main --preset safe --limit 10
gradatum-admin cleaner run --tenant main --preset safe --limit 10
```

Restoration of any rewrite:

```bash
gradatum-admin cleaner restore --note-id 01HX...
```

Rollback per cycle is supported. Bulk rollback via `gradatum-admin cleaner restore-since --date YYYY-MM-DD`.

---

## 5. Alternatives considered

| Alternative | Pros | Cons | Reason rejected |
|---|---|---|---|
| Do nothing — accept entropy | No effort | KB becomes unwieldy after 1-2 years | Quantified problem |
| Manual cleanup only | No code | Doesn't scale beyond ~1000 notes | Quantified problem |
| Hard delete with no archive | Simpler | No recovery from bad rewrites | Markdown-source-of-truth invariant requires reversibility |
| In-place edit without validator | Faster | High risk of semantic drift | Validation is the whole point |
| Soft-delete with TTL | Simple | Doesn't reclaim space; clutters listing | Archive is functionally equivalent + cleaner |

---

## 6. Drawbacks

- **LLM cost — significant.** Each rewrite calls the validator. At ~3 calls per rewrite × ~5% of notes per sweep × 1000 notes → ~150 calls per cycle. At Qwen3.6-27B THINKING <inference-host> :8081 (deep on-demand, ctx 128K, pas de nouveau modèle requis — alternative Qwen3.6-35B-A3B :8080): ~30 minutes wall-clock weekly.
- **Risk of false-accept.** A validator with imperfect recall metric can let through a rewrite that looks similar but loses a key claim. Mitigation: `safe` preset uses `strict` validation. But operators using `compress_max` accept higher risk.
- **Storage doubles in archive.** Every rewrite preserves the original. After 1 year of weekly cycles, archive may exceed live KB size. Mitigation: archive compaction (tar.gz monthly) — but adds complexity.
- **Evolutionary mode is exotic.** GP over rewrite ops is research-grade. The fitness function is hand-tuned. False optima are common. Should be flagged experimental and gated behind `gradatum-admin cleaner enable-experimental`.
- **Operator surprise.** A note that was edited last week is now slightly different. Audit trail mitigates this, but operator surprise is real. Mitigation: `cleaner.notify_operator = true` default sends a weekly digest of rewrites.

> **AM4 reminder:** this section must be authored without AI assistance. The author should be able to defend it in a synchronous review without referring to generated text.

---

## 7. Unresolved questions

- [ ] Validator model choice: Qwen3.6-27B THINKING <inference-host> :8081 (deep on-demand, ctx 128K, pas de nouveau modèle requis — alternative Qwen3.6-35B-A3B :8080) is recommended but slow. Should `cleaner.fast_path` allow Qwen3-4B-Instruct-2507 with stricter threshold? Trade-off latency vs accuracy.
- [ ] Archive retention policy: indefinite, or N years configurable? Operator expectation may vary.
- [ ] Cross-tenant cleaner: does a `safe` sweep behave the same on every tenant? Default proposal: yes, per-tenant configuration possible.
- [ ] Interaction with `gradatum-consolidate` (RFC-0003): should the cleaner refuse to rewrite notes that are heavily referenced by consolidated facts (high `fact_count`)? Or rewrite + invalidate consolidation? Default proposal: refuse if `fact_count > 5`, force operator override.
- [ ] Evolutionary mode access: gated behind `enable-experimental`, or available from start with warning? Council discussion needed.

---

## References

- Gradatum architecture: `ARCHITECTURE.md`
- Curator scope: `PROJECT-CONTEXT.md` §5
- Companion RFC reflective curator: RFC-0001
- Companion RFC consolidation: RFC-0003
- Genetic programming: Koza, J.R. — Genetic Programming: On the Programming of Computers by Means of Natural Selection (1992)
- FunSearch (DeepMind, 2024) — programmatic search via LLM, conceptually adjacent
- Source: ex-spec #3 (2026-05-08) `gradatum-spec-03-cleaner-zero-loss.docx` — initial draft repositioned in this RFC

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-08 | @the operator | Initial creation from ex-spec #3, status: Draft |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0007 → RFC-0004, table header → YAML frontmatter, refs mises à jour |

---

## License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-0004.*
