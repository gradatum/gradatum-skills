---
rfc: RFC-0003
title: "gradatum-consolidate: knowledge consolidation (atomic facts, concepts, dedup)"
status: Draft
author: '@the operator'
created: 2026-05-08
updated: 2026-05-10
version: 1
depends_on: []
required_by: []
related_to:
  - gradatum:RFC-0005
  - RFC-0001
category: feature
scope: gradatum-engine
crates_touched:
  - gradatum-consolidate
  - gradatum-core
  - gradatum-index
  - gradatum-worker
  - gradatum-server
  - gradatum-search
phase_target: "Phase 3+ (after Phase 2.1 migrate-from-v0 + ≥3 months D5 dogfooding)"
tracking_issue: backlog Phase 3+, post-rc.1
license: Apache-2.0
---

# RFC-0003 — `gradatum-consolidate`: knowledge consolidation (atomic facts, concepts, dedup)

## Status note

This RFC is a **future feature proposal** captured 2026-05-08. It is **NOT in scope** for `v0.1.0-alpha.6`, `v0.1.0-rc.1`, or `v0.1.0` stable. It targets Phase 3+ once enough notes have accumulated to justify a structured-knowledge layer on top of the raw Markdown.

The proposal is included now to:

- Anchor the long-term direction for derived-knowledge storage
- Inform Phase 2 architectural decisions where they impact future feasibility (frontmatter richness, audit granularity, multi-tenant scope)
- Provide a foundation that `gradatum:RFC-0005` Phase 2 (Analyze) can consume — cluster detection over consolidated concepts is more precise than over raw notes

---

## 1. Motivation

The Markdown source-of-truth model gives Gradatum its readability and resilience. It does not, however, give it a structured representation of the knowledge contained in notes. As the KB grows past ~500 notes, three problems become measurable:

- **Same fact restated.** « Le swap zvol ZFS est 32 GB sur nvme_pool » appears in 4 distinct notes, with minor wording variations. None is canonical.
- **Concepts diluted.** A concept like « ZFS swap configuration » exists implicitly across notes but cannot be queried as such.
- **Relations invisible.** Notes mention « ROCm » and « Vulkan » in the same breath dozens of times, but no edge in the search graph reflects that.

`gradatum:RFC-0005` (self-improvement) tries to detect patterns directly in note text. It works, but the noise floor is high because notes are written for humans, not for analyzers.

This RFC proposes `gradatum-consolidate`: a worker job that distills raw notes into a layered structured KB:

- **Atomic facts** — short triples or short statements with provenance
- **Concepts** — clusters of facts about the same entity, canonicalized
- **Relations** — edges between concepts, derived from co-occurrence and explicit wikilinks
- **Dedup** — multi-pass equivalence detection (hash → FTS5 → cosine BLOB → LLM judge)

Storage is SQLite-only (rebuildable from notes). The original `.md` files remain authoritative. Consolidation is read-only on notes, append-only on its own tables.

---

## 2. Design

### 2.1 Pipeline overview

```
gradatum-vault (read-only)
        │
        ▼ note traversal (incremental, content_hash diff)
   ① Atomic fact extractor (Qwen3-4B-Instruct-2507)
        │  → produces short statements with note_id provenance
        ▼
   ② Canonicalizer
        │  → maps surface forms to canonical concept IDs
        ▼
   ③ Dedup pipeline (3 passes)
        │  Pass 1: SHA-256 over normalized form
        │  Pass 2: FTS5 BM25 candidate retrieval (top-K)
        │  Pass 3: cosine BLOB similarity (bge-small-en 384d)
        │  Pass 4: LLM judge on ambiguous pairs
        ▼
   ④ Persistence
        │  SQLite: concepts, facts, relations, sources, consolidation_log
        │  Markdown: optional concept-level digest (separate space)
        ▼
   gradatum-search (NEW: concept-level retrieval channel)
   gradatum:RFC-0005, Phase 2 (consumer of consolidated concepts)
```

### 2.2 New tables in `gradatum-index`

```sql
CREATE TABLE consolidate_concepts (
    id TEXT PRIMARY KEY,                    -- ULID
    canonical_label TEXT NOT NULL,
    aliases JSON NOT NULL DEFAULT '[]',
    section TEXT,                            -- canonical section if dominant
    embedding BLOB,                          -- 384 * 2 bytes (FP16)
    fact_count INTEGER NOT NULL DEFAULT 0,
    first_seen_at TIMESTAMP NOT NULL,
    last_updated_at TIMESTAMP NOT NULL,
    tenant_id TEXT NOT NULL                  -- D10 invariant
);

CREATE TABLE consolidate_facts (
    id TEXT PRIMARY KEY,                    -- ULID
    concept_id TEXT NOT NULL REFERENCES consolidate_concepts(id) ON DELETE CASCADE,
    statement TEXT NOT NULL,                -- normalized atomic statement
    statement_hash TEXT NOT NULL UNIQUE,
    confidence REAL NOT NULL,
    extracted_by TEXT NOT NULL,             -- 'heuristic' | 'qwen3-4b' | 'qwen3-30b-judge'
    extracted_at TIMESTAMP NOT NULL,
    tenant_id TEXT NOT NULL
);

CREATE TABLE consolidate_fact_sources (
    fact_id TEXT NOT NULL REFERENCES consolidate_facts(id) ON DELETE CASCADE,
    note_id TEXT NOT NULL,
    excerpt_offset INTEGER,                 -- byte offset in note body
    excerpt_length INTEGER,
    PRIMARY KEY (fact_id, note_id)
);

CREATE TABLE consolidate_relations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_concept TEXT NOT NULL REFERENCES consolidate_concepts(id),
    to_concept TEXT NOT NULL REFERENCES consolidate_concepts(id),
    relation_type TEXT NOT NULL,            -- 'co-occurs' | 'depends-on' | 'instance-of' | ...
    weight REAL NOT NULL DEFAULT 1.0,
    source_count INTEGER NOT NULL DEFAULT 1,
    tenant_id TEXT NOT NULL,
    UNIQUE(from_concept, to_concept, relation_type)
);

CREATE TABLE consolidate_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation TEXT NOT NULL,                -- 'extract' | 'canonicalize' | 'dedup' | 'merge' | 'split'
    payload JSON NOT NULL,
    decided_by TEXT NOT NULL,               -- 'heuristic' | 'llm' | 'operator'
    timestamp TIMESTAMP NOT NULL,
    tenant_id TEXT NOT NULL
);

CREATE INDEX idx_concepts_label ON consolidate_concepts(canonical_label);
CREATE INDEX idx_facts_concept ON consolidate_facts(concept_id);
CREATE INDEX idx_relations_from ON consolidate_relations(from_concept);
CREATE INDEX idx_relations_to ON consolidate_relations(to_concept);
```

Migration `0011_consolidate.sql`. All tables carry `tenant_id` per D10.

### 2.3 New crate `gradatum-consolidate` (Layer L3)

```rust
#[async_trait]
pub trait Consolidator: Send + Sync {
    async fn extract_facts(&self, note: &Note) -> Result<Vec<AtomicFact>>;
    async fn canonicalize(&self, fact: &AtomicFact) -> Result<ConceptId>;
    async fn dedup(&self, candidates: &[FactId]) -> Result<DedupReport>;
    async fn run_incremental(&self, since: DateTime<Utc>) -> Result<ConsolidateReport>;
    async fn run_full_rebuild(&self, tenant: TenantId) -> Result<ConsolidateReport>;
}

pub struct AtomicFact {
    pub statement: String,             // < 200 chars
    pub source_note: NoteId,
    pub confidence: f32,
}

pub struct DedupReport {
    pub clusters: Vec<DedupCluster>,
    pub unmerged_pairs: Vec<(FactId, FactId, f32)>,   // ambiguous, deferred to LLM judge
}
```

Default impl in `gradatum-consolidate`. Reads from `gradatum-vault::Vault` and `gradatum-embed::Embedder`. Writes only to its own tables.

### 2.4 Job scheduling

`gradatum-worker` runs three job types from this crate:

| Job | Trigger | Frequency |
|---|---|---|
| `ConsolidateExtractFactsJob` | Note write event | per-note, async, debounced 30 s |
| `ConsolidateDedupSweepJob` | Cron | daily at 03:00 |
| `ConsolidateFullRebuildJob` | Operator command | on demand only |

The extract job runs at write-time but its failure does NOT block the note write. The note is the source of truth; consolidation is best-effort.

### 2.5 Markdown digest (optional)

For operators who want a human-readable view of consolidation, an optional Markdown digest is produced:

```
~/.gradatum/vaults/main/consolidate/
├── concepts/
│   ├── concept-zfs-swap-configuration.md
│   ├── concept-rocm-vulkan-stack.md
│   └── ...
└── relations/
    └── 2026-05-week-19.md      (weekly snapshot of relation graph)
```

These digests are generated, not authoritative. They MUST NOT be edited by operators (any edit is overwritten on next run). The path `consolidate/` is reserved.

### 2.6 LLM judge usage

Dedup pass 4 invokes a judge LLM only on ambiguous pairs (pass 3 cosine similarity in `[0.85, 0.92]`). The judge model is configurable; recommended default: `qwen3-8b` per `gradatum:RFC-0005` §17.5. Below 0.85, treat as distinct facts. Above 0.92, auto-merge with `decided_by = 'llm'` audit entry.

---

## 3. Impact downstream

| Component | Impact | Effort |
|---|---|---|
| `gradatum-consolidate` (NEW) | Full crate scaffold + 4 trait methods | ~2000 LOC |
| `gradatum-core` | New types `AtomicFact`, `ConceptId`, `DedupReport` (experimental) | ~150 LOC |
| `gradatum-index` | Migration `0011_consolidate.sql` + 5 repository accessors | ~400 LOC |
| `gradatum-worker` | 3 new job types | ~250 LOC |
| `gradatum-server` | New endpoints `GET /api/v1/concepts`, `GET /api/v1/concepts/:id`, `GET /api/v1/concepts/:id/relations` | ~150 LOC |
| `gradatum-cli` | New subcommand `gradatum consolidate {status, rebuild}` | ~80 LOC |
| `gradatum-search` | Optional new channel: search by concept (vs by note text) | ~100 LOC |
| Schema | 5 new tables + 1 migration | — |
| Default LLM | None — uses existing `consolidate.model` config field (NEW in `gradatum.toml`) | — |
| CI requirements | New gold dataset (`gradatum-bench/fixtures/consolidate-gold/`) | — |

Public API surface impact: 1 new optional crate, types tagged `experimental`. No breaking change.

---

## 4. Migration path

N/A — additive only. Existing notes do not need modification.

A one-shot full rebuild command is provided for first activation:

```bash
gradatum-admin consolidate rebuild --tenant main --dry-run
gradatum-admin consolidate rebuild --tenant main
```

For a vault of ~2000 notes, rebuild is estimated at ~1 hour wall-clock on local Qwen3-4B-Instruct-2507. The job is interruptible and resumable from `consolidate_log`.

Rollback: `DROP TABLE consolidate_*` is safe — no source data is touched.

---

## 5. Alternatives considered

| Alternative | Pros | Cons | Reason rejected |
|---|---|---|---|
| Do nothing — keep raw notes only | No effort | Self-improvement Phase 2 noisier; concept-level search impossible | Section 1 quantified the gap |
| Embed consolidation IN curator | Simpler crate count | Curator already has 5 functions; bundling a 6th violates single-responsibility (a recurring lesson from `gatekeeper` → `curator` rename Phase 0bis-bis) | Decoupling preserved |
| Use an external knowledge graph (Neo4j, RDF) | Mature ecosystem | External service dependency; conflicts with embedded invariant | Embedded invariant non-negotiable |
| Store consolidated facts as notes in section `reference` | Reuses existing storage | Pollutes the note space; confuses operators on what is human-authored vs derived | Separate tables preserve clarity |
| Real-time consolidation (synchronous with note write) | Always fresh | Blocks write path; LLM latency unacceptable | Async consolidation is best-effort by design |

---

## 6. Drawbacks

- **Storage growth.** A 2000-note vault with average 5 facts/note generates ~10000 fact rows + ~2000 concept rows + ~5000 relation rows. With embeddings, ~7-10 MB additional storage. Acceptable.
- **LLM cost.** Extraction calls Qwen3-4B-Instruct on every note write. At ~30 tokens output per note, this is non-trivial over a session of intense writing. Mitigation: debounce 30 s + batch within debounce window.
- **Drift between notes and consolidation.** When a note is edited, its derived facts become stale. Mitigation: `content_hash` watch on notes triggers re-extraction. Worst case: stale facts marked with a `superseded_by` flag.
- **Concept canonicalization is fragile.** Two distinct concepts can share canonical labels (e.g., « python » as language vs. « python » as snake). Mitigation: per-concept `disambiguator` field; LLM judge on ambiguity. But edge cases remain.
- **Adds a new crate to maintain.** The workspace already has 22 crates. A 23rd has compile-time and review overhead.

> **AM4 reminder:** this section must be authored without AI assistance. The author should be able to defend it in a synchronous review without referring to generated text.

---

## 7. Unresolved questions

- [ ] Should consolidation be tenant-scoped or cross-tenant? Default proposal: tenant-scoped (D10). But shared infra concepts (`tokio`, `axum`) might benefit from cross-tenant. Privacy implications.
- [ ] Concept stable identity: when a concept's fact set evolves significantly, should the ULID change? Argument for stable: traceability. Argument for change: prevents staleness of relations referring to it.
- [ ] Granularity of relations: only `co-occurs` v1, or also `depends-on`, `instance-of`, `contradicts`? More relation types = richer graph, but more LLM judging.
- [ ] Interaction with `gradatum migrate-from-v0` (Phase 2.1): should consolidation run on pre-migration vault-mem notes, or wait for full re-classification? Current draft says wait.
- [ ] Should the consolidator generate Markdown digests by default, or only on operator request? Generating creates clutter; not generating reduces visibility.

---

## References

- Gradatum architecture: `ARCHITECTURE.md`
- Self-improvement RFC: `gradatum:RFC-0005`
- Curator reflective improvement: RFC-0001 (gradatum-skills:RFC-0001)
- Curator scope: `PROJECT-CONTEXT.md` §5
- 5 invariants: `PROJECT-CONTEXT.md` §9
- Source: ex-spec #2 (2026-05-08) `gradatum-spec-02-consolidation-kb.docx` — initial draft repositioned in this RFC

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-08 | @the operator | Initial creation from ex-spec #2, status: Draft |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0006 → RFC-0003, table header → YAML frontmatter, refs mises à jour |

---

## License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-0003.*
