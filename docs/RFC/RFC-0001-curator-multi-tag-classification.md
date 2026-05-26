---
rfc: RFC-0001
title: Curator — multi-tag classification with reflective improvement
status: Draft
author: '@the operator'
created: 2026-05-08
updated: 2026-05-10
version: 1
depends_on: []
required_by: []
related_to:
  - RFC-0002
category: curator
scope: gradatum-engine
crates_touched:
  - gradatum-curator
  - gradatum-core
  - gradatum-index
phase_target: Phase 3+ (post v0.1.0 stable + ≥3 months D5 dogfooding)
tracking_issue: backlog Phase 3+, post-rc.1
license: Apache-2.0
---

# RFC-0001 — Curator: multi-tag classification with reflective improvement

## Status note

This RFC is a **future feature proposal** captured 2026-05-08 during a brainstorming session on memory backbone classification. It is **NOT in scope** for `v0.1.0-alpha.6`, `v0.1.0-rc.1` or `v0.1.0` stable. It targets Phase 3+ once the curator's heuristic + Qwen3-4B-Instruct-2507 baseline (Phase 2.0c) has been observed for ≥3 months on a real vault and a corrections corpus has accumulated.

It complements RFC-0002 (which proposes enrichments to the self-improvement RFC) by upgrading the curator's classification path from one-shot to reflective-improvement.

---

## 1. Motivation

The Phase 2.0c curator classifies notes via a two-tier path: deterministic heuristic (keywords + section regex) → LLM fallback (Qwen3-4B-Instruct-2507). Phase 1 benchmarks show heuristic F1w 0.7871 / LLM F1w 0.7938. Both are above their respective thresholds (≥0.65 / ≥0.75) but the gap to operator expectation (target ≥0.85 macro-F1 on multi-tag) is significant.

The current path has two structural limits:

- **No memory of corrections.** When the operator corrects a tag or a section, the correction does not improve the next classification. Each note is classified in isolation.
- **Static prompt.** The LLM prompt is fixed at compile time. Its weak points cannot be addressed without a code change and a release.

This RFC proposes a reflective-improvement loop sitting on top of the existing curator pipeline:

1. **ExampleBank** — corrections are stored, embedded and retrieved as few-shot examples for the LLM tier on subsequent notes.
2. **GEPA** — periodic prompt evolution against a held-out gold dataset, with semver-versioned prompts and one-click rollback.
3. **LoRA (optional)** — once correction volume crosses a threshold, generate DPO pairs and train a low-rank adapter on Qwen3-4B-Instruct-2507.

The motivation is concrete: a memory backbone that classifies wrongly is worse than no classification, because operators stop trusting it. Reflective improvement is the path to durable F1.

---

## 2. Design

### 2.1 Pipeline overview

```
note (markdown + frontmatter)
        │
        ▼
   gradatum-embed::Embedder         (existing — bge-small-en-v1.5 384d)
        │
        ▼
   ExampleBank retrieval            (NEW: kNN top-K via FTS5 + cosine BLOB)
        │
        ▼
   Prompt builder                   (NEW: prompt template versioned by GEPA)
        │
        ▼
   gradatum-chat::LlmBackend        (existing)
        │
        ▼
   Calibration + gating             (existing — heuristic confidence)
        │
        ▼
   Frontmatter patch (proposed)     (existing — separate from source note)
        │
        └─► operator correction ──► ExampleBank (with embedding)
        └─► every 7d ─────────────► GEPA prompt evolution
        └─► every 90d if volume ──► LoRA training
```

### 2.2 New traits in `gradatum-core`

```rust
#[async_trait]
pub trait ExampleBank: Send + Sync {
    async fn record_correction(
        &self,
        note_id: NoteId,
        previous_tags: Vec<Wikilink>,
        corrected_tags: Vec<Wikilink>,
        corrected_by: BearerId,
    ) -> Result<()>;

    async fn retrieve_top_k(
        &self,
        embedding: &[f32],
        k: usize,
    ) -> Result<Vec<ExampleHit>>;
}

pub struct ExampleHit {
    pub note_excerpt: String,
    pub tags: Vec<Wikilink>,
    pub justification: Option<String>,
    pub similarity: f32,
}

#[async_trait]
pub trait PromptStore: Send + Sync {
    async fn current(&self, scope: PromptScope) -> Result<PromptVersion>;
    async fn promote(&self, scope: PromptScope, candidate: PromptCandidate) -> Result<()>;
    async fn rollback(&self, scope: PromptScope, target: SemVer) -> Result<()>;
    async fn list(&self, scope: PromptScope) -> Result<Vec<PromptVersionMeta>>;
}
```

Both traits live in `gradatum-core::curator_ext` (new submodule, AM1 = `experimental`).
Their default implementations live in `gradatum-curator`.

### 2.3 New tables in `gradatum-index`

```sql
CREATE TABLE curator_examples (
    id TEXT PRIMARY KEY,                    -- ULID
    note_excerpt TEXT NOT NULL,             -- max 500 tokens
    embedding BLOB NOT NULL,                -- 384 * 2 bytes (FP16)
    tags JSON NOT NULL,
    justification TEXT,
    source_note_id TEXT NOT NULL,
    validated_at TIMESTAMP NOT NULL,
    weight REAL NOT NULL DEFAULT 1.0,
    excerpt_hash TEXT NOT NULL UNIQUE,
    tenant_id TEXT NOT NULL                 -- D10 multi-tenant invariant
);

CREATE VIRTUAL TABLE curator_examples_fts USING fts5(
    note_excerpt, content=curator_examples, content_rowid=rowid
);

CREATE TABLE curator_prompt_versions (
    scope TEXT NOT NULL,                    -- 'classification' | 'tagging' | ...
    version TEXT NOT NULL,                  -- semver
    template TEXT NOT NULL,
    f1_macro REAL,
    promoted_at TIMESTAMP NOT NULL,
    promoted_by TEXT NOT NULL,
    parent_version TEXT,
    PRIMARY KEY (scope, version)
);

CREATE TABLE curator_corrections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id TEXT NOT NULL,
    previous_tags JSON,
    corrected_tags JSON,
    corrected_by TEXT NOT NULL,
    corrected_at TIMESTAMP NOT NULL,
    used_for_gepa BOOLEAN DEFAULT FALSE,
    tenant_id TEXT NOT NULL
);
```

Migration `0010_curator_reflective.sql`. All tables carry `tenant_id` to comply with D10 invariant.

### 2.4 GEPA pipeline (gradatum-worker job)

```rust
pub struct GepaJob {
    scope: PromptScope,
    error_sample_size: usize,        // 50 default
    candidate_count: usize,          // 8 default
    generations: usize,              // 5 default
    holdout_test_set_path: PathBuf,
    judge_model: String,             // "qwen3-30b" recommended
    promotion_delta_threshold: f64,  // 1.0 absolute F1 point default
}
```

Triggered weekly by `gradatum-worker` maintenance job. Reads recent unused corrections, calls the judge LLM, evaluates candidates against held-out test set (locked, never seen during evolution), promotes if `delta > threshold`.

### 2.5 Frontmatter contract

The curator already produces a frontmatter patch (see RFC-0002 §4 Phase 1 reference). Reflective improvement extends it with two fields:

```yaml
classification:
  confidence: 0.87
  model: qwen3-4b-instruct-2507
  prompt_version: v0.4.2          # NEW — versioned by GEPA
  example_bank_hits: 5            # NEW — observability
  generated_at: 2026-05-08T14:32:00Z
  emerging_tags: []
  review_required: false
```

---

## 3. Impact downstream

| Component | Impact | Effort |
|---|---|---|
| `gradatum-core` | New module `curator_ext` (3 traits, 5 types). All `experimental` per AM1. | ~80 LOC |
| `gradatum-curator` | New default impls of `ExampleBank` + `PromptStore`. New retrieval step in classify path. | ~600 LOC |
| `gradatum-index` | New migration `0010_curator_reflective.sql`. New repository accessors. | ~200 LOC |
| `gradatum-worker` | New job type `GepaJob`. | ~150 LOC |
| `gradatum-server` | New endpoint `POST /api/v1/curator/correction`, new endpoint `GET /api/v1/curator/prompt/versions`. | ~100 LOC |
| `gradatum-cli` | New subcommand `gradatum curator correction`. | ~80 LOC |
| External SDK consumers | Additive only. Frontmatter additions are backward-compatible. | None |
| Schema | 3 new tables + 1 migration | — |

Public API surface impact: 3 new trait additions in `gradatum-core::curator_ext` tagged `experimental`. No breaking change to stable surface.

---

## 4. Migration path

N/A — additive only. Existing notes do not need re-classification. The reflective loop activates on the first correction recorded post-deployment.

For operators who want to bootstrap the ExampleBank from existing manually-edited notes, a one-shot import command is provided:

```bash
gradatum-admin curator import-corrections \
    --since 2026-01-01 \
    --confidence-threshold 0.9 \
    --dry-run
```

---

## 5. Alternatives considered

| Alternative | Pros | Cons | Reason rejected |
|---|---|---|---|
| Do nothing — keep static curator | No effort | F1 plateaus at ~0.79; operator trust erodes over time | Section 1 quantified the gap to target ≥0.85 |
| Direct fine-tuning every week | Could push F1 higher | GPU compute requirement; conflicts with self-improvement "explicit validation" | Cost-benefit unfavorable for ~200-2000 notes scale |
| Hand-curate prompt only (no GEPA) | Simplest | Operator burden grows with KB; subjective | GEPA replaces the operator's intuition with held-out F1 measurement |
| External tool (DSPy, Outlines) | Mature ecosystem | Python dependency; conflicts with no-vendor-SDK invariant (R10) | Gradatum philosophy: minimal dependencies |
| Per-tenant prompt evolution (instead of global) | Better fit per vault | Coordination cost ~5x; slower convergence | Phase 1 single-tenant; multi-tenant prompt deferred to Phase 4+ |

---

## 6. Drawbacks

- **Compute cost.** GEPA weekly runs require ~50 LLM calls per cycle. At Qwen3-30B local inference cost: ~5 minutes wall-clock on Radeon 8060S.
- **Test set discipline.** Held-out test set must be locked and audited. If it leaks into the training/correction loop, F1 measurements become meaningless.
- **Cold start.** Below ~50 corrections in the bank, retrieval is statistically irrelevant.
- **Prompt rollback complexity.** A buggy GEPA promotion can degrade F1 silently. Mitigation: every promotion logs the F1 delta.
- **Schema growth.** 3 new tables + per-correction embedding (~700 bytes each) means a vault with 5000 corrections grows by ~3.5 MB.

---

## 7. Unresolved questions

- [ ] Should ExampleBank retrieval also cross-tenant for shared examples (e.g., a `gold` tenant)? Privacy implications.
- [ ] Should GEPA be allowed to modify the heuristic regex (deterministic tier), or only the LLM prompt?
- [ ] Auto-promote vs operator-approve: default value? Conservative draft says `--auto-promote=false`.
- [ ] Interaction with the self-improvement RFC Phase 1 (Observe): boundary with RFC-0001 needs clarification.
- [ ] LoRA path: drop entirely, defer to v2.x, or keep as optional Phase 4+?

---

## References

- Gradatum architecture: `ARCHITECTURE.md`
- Curator current scope: `PROJECT-CONTEXT.md` §5 — `gradatum-curator`
- Companion RFC enriching self-improvement: RFC-0002
- DSPy paper: Khattab et al. — DSPy: Compiling Declarative Language Model Calls (2024)
- GEPA: Agrawal et al. — Reflective Prompt Evolution (2025)

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-08 | @the operator | Initial creation from brainstorming session, status: Draft |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0004 → RFC-0001, table header → YAML frontmatter, refs mises à jour |

---

## License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-0001.*
