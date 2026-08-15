---
rfc: RFC-0005
title: "gradatum-privacy: PII filtering at write-time"
status: Draft
author: '@gradatum-maintainer'
created: 2026-05-08
updated: 2026-05-10
version: 1
depends_on: []
required_by: []
related_to:
  - RFC-0003
category: feature
scope: gradatum-engine
crates_touched:
  - gradatum-privacy
  - gradatum-core
  - gradatum-curator
  - gradatum-server
  - gradatum-worker
phase_target: "Phase 3+ (after Phase 2.1 + ≥3 months D5 dogfooding)"
tracking_issue: backlog Phase 3+
license: Apache-2.0
---

# RFC-0005 — `gradatum-privacy`: PII filtering at write-time

## Status note

This RFC is a **future feature proposal** captured 2026-05-08. It is **NOT in scope** for `v0.1.0-alpha.6`, `v0.1.0-rc.1`, or `v0.1.0` stable. It targets Phase 3+ once the curator pipeline is mature and operators have characterized their PII profile.

This RFC is **distinct from `gradatum-distill`** (already reserved as Phase v1.x+ stub for k-anonymity export). The two cover different paths:

- `gradatum-privacy` (this RFC) — write-time filter on incoming notes
- `gradatum-distill` (existing stub) — export-time k-anonymity for sharing

A shared PII detection library (`pii-core`, internal) may underpin both eventually — out of scope for this RFC.

---

## 1. Motivation

A memory backbone collects sensitive information by nature: agent traces, debug sessions, SSH keys accidentally pasted, IP addresses, credentials in error logs, names, phone numbers. The current Phase 2 stack has no PII protection on the write path.

Three concrete cases observed in dogfooding:

- An agent paste of a `.env` file containing an API key into a debug note
- A traceroute output containing internal IPs in an architecture note
- A copy-paste of an email thread with personal addresses into a feedback note

Without filtering, every such write becomes a permanent record. ACL helps (only authorized bearers see the note) but does not redact. Drift detection catches modifications, not initial leaks.

This RFC proposes `gradatum-privacy`: a sidecar component sitting between `gradatum-server` (enqueue) and `gradatum-curator` (write pipeline), that detects PII in incoming notes and applies a redaction policy.

The motivation is concrete: a memory backbone that leaks private data is a security incident. Better to redact-or-reject upstream than discover after-the-fact.

---

## 2. Design

### 2.1 Five-layer pipeline

```
incoming note (from gradatum-server enqueue)
        │
        ▼
   ① Bypass check                          (frontmatter / tag / path)
        │   if bypass → skip 2-5
        ▼
   ② Strict regex layer                    (deterministic, fast)
        │   matches: emails, IPs, AWS keys, JWT tokens, phone numbers,
        │            SSH private keys, credit cards, SSN
        ▼
   ③ ML layer (Phase 1: Python sidecar)    (OpenAI Privacy Filter 1.5B/50M MoE)
        │   captures contextual PII the regex misses
        │   Phase 2: ONNX Rust port via ort
        ▼
   ④ Contextual layer (Qwen3-4B-Instruct)  (LLM judge, ambiguous cases only)
        │   only on items flagged by ② or ③ with confidence ∈ [0.5, 0.85]
        ▼
   ⑤ Redaction policy applier              (configurable)
        │   strategies: redact-inline | reject | quarantine | ack-and-store
        ▼
   ⑥ Re-audit                              (final scan post-redaction)
        │
        ▼
   gradatum-curator pipeline (existing)
```

Latency budget: ① ~2 ms, ② ~20 ms, ③ ~50-200 ms, ④ optional ~500 ms, ⑤ ~5 ms, ⑥ ~20 ms. Total typical: < 100 ms (no LLM call), < 1 s (with LLM). Acceptable for async write path.

### 2.2 Bypass mechanism

Operator can mark notes as bypassing the filter via:

- Frontmatter: `privacy: bypass` (explicit, audit-tracked)
- Tag wikilink: `[[privacy/bypass]]`
- Path prefix: notes under `loci = "human/private/*"` configurable

Bypass is an explicit opt-out. Every bypass is logged with operator identity and reason.

### 2.3 Redaction policies (configurable per tenant)

| Policy | Behavior | Audit |
|---|---|---|
| `redact-inline` | Replace match with token `[REDACTED:<type>]` | Match + token in audit log |
| `reject` | Reject entire note write, return error to caller | Reject reason in audit log |
| `quarantine` | Write to `quarantine/` directory, hold for operator review | Notification + quarantine path |
| `ack-and-store` | Store as-is, but mark with `privacy: violation_acknowledged` frontmatter | Full record in audit |

Default: `redact-inline` for `email`, `ip`, `phone`; `reject` for `api_key`, `ssh_private_key`, `aws_credentials`, `jwt_token`, `credit_card`, `ssn`.

### 2.4 New trait in `gradatum-core::privacy`

```rust
#[async_trait]
pub trait PrivacyFilter: Send + Sync {
    async fn scan(&self, note: &NoteCandidate) -> Result<PrivacyVerdict>;
}

pub struct NoteCandidate {
    pub body: String,
    pub frontmatter: Frontmatter,
    pub author: BearerId,
    pub tenant: TenantId,
}

pub struct PrivacyVerdict {
    pub matches: Vec<PiiMatch>,
    pub action: PrivacyAction,             // redact-inline | reject | quarantine | ack
    pub redacted_body: Option<String>,     // if redact-inline
    pub bypass_reason: Option<String>,
}

pub struct PiiMatch {
    pub kind: PiiKind,                     // email | ip | api_key | ...
    pub span_start: usize,
    pub span_end: usize,
    pub confidence: f32,
    pub source_layer: u8,                  // 1..5
}
```

### 2.5 Phase 1 architecture (Python sidecar)

To avoid blocking on a Rust ONNX port, Phase 1 ships a small Python sidecar:

```
gradatum-privacy (Rust crate)
    └─► HTTP local <port>/scan  ──► privacy-sidecar (Python)
                                       └─► OpenAI Privacy Filter ONNX model
                                       └─► transformers + torch (CPU)
```

The sidecar runs as a separate systemd service `gradatum-privacy-sidecar.service`. Communication via local HTTP (loopback only). Restart-tolerant: if sidecar is down, the filter falls back to layer 2 only (regex) and emits a `privacy.degraded` audit event.

### 2.6 Phase 2 architecture (Rust ONNX)

When ONNX model + ort runtime is reproducible in CI:

```
gradatum-privacy (Rust crate)
    └─► ort runtime (in-process)
        └─► OpenAI Privacy Filter ONNX
```

Single binary, no sidecar. Path to Phase 2 depends on `ort` availability for the target architecture (Radeon RDNA 3.5 still pending — see `POC_CANDLE_RADEON.md` for context).

### 2.7 New tables in `gradatum-index`

```sql
CREATE TABLE privacy_audit (
    id TEXT PRIMARY KEY,
    note_id TEXT,                          -- nullable: rejected notes have no note_id
    action TEXT NOT NULL,
    matches JSON NOT NULL,
    layers_triggered JSON NOT NULL,
    bypass_reason TEXT,
    actor TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    tenant_id TEXT NOT NULL
);

CREATE TABLE privacy_quarantine (
    id TEXT PRIMARY KEY,
    candidate_body TEXT NOT NULL,
    candidate_frontmatter JSON NOT NULL,
    matches JSON NOT NULL,
    quarantined_at TIMESTAMP NOT NULL,
    quarantined_by TEXT NOT NULL,
    resolved_at TIMESTAMP,
    resolution TEXT,                       -- 'released' | 'rejected' | 'redacted_and_released'
    tenant_id TEXT NOT NULL
);

CREATE INDEX idx_privacy_audit_timestamp ON privacy_audit(timestamp);
CREATE INDEX idx_privacy_quarantine_unresolved ON privacy_quarantine(resolved_at) WHERE resolved_at IS NULL;
```

Migration `0013_privacy.sql`.

---

## 3. Impact downstream

| Component | Impact | Effort |
|---|---|---|
| `gradatum-privacy` (NEW) | Full crate scaffold + 5-layer pipeline | ~1500 LOC |
| `gradatum-core` | New module `privacy` (3 traits, 4 types, all `experimental`) | ~150 LOC |
| `gradatum-curator` | New entry hook to invoke filter before novelty step | ~50 LOC |
| `gradatum-server` | New endpoints `POST /api/v1/privacy/scan` (preview), `GET /api/v1/privacy/quarantine` (admin) | ~120 LOC |
| `gradatum-worker` | Filter invocation on dequeue (before curator) | ~80 LOC |
| `gradatum-cli` | New subcommand `gradatum privacy {scan, quarantine list, release, reject}` | ~120 LOC |
| `gradatum-admin` | New subcommand `gradatum-admin privacy {test, configure}` | ~80 LOC |
| Phase 1 Python sidecar | New service, 200 LOC Python | — |
| Schema | 2 new tables + 1 migration | — |
| Default ports | NEW: 19097 (privacy sidecar, loopback only) | — |
| Default LLM | None — uses `privacy.contextual_model` config (NEW) | — |
| CI requirements | New gold dataset of PII positives + negatives (~500 entries) | — |

Public API surface impact: 1 new crate (optional via feature `privacy`), traits tagged `experimental`. No breaking change to stable surface.

---

## 4. Migration path

N/A — additive only. Existing notes are not retroactively scanned by default.

For an existing vault, an opt-in retroactive scan is provided:

```bash
gradatum-admin privacy scan-existing --tenant main --policy report-only --dry-run
gradatum-admin privacy scan-existing --tenant main --policy report-only
```

`report-only` policy adds a `privacy.violation_observed` event to audit but does not modify any note. The operator can then run targeted redactions.

Phase 1 → Phase 2 migration:

- Phase 1 (Python sidecar): `gradatum-privacy.service` + `gradatum-privacy-sidecar.service`
- Phase 2 (Rust ONNX): `gradatum-privacy.service` only; sidecar is removed
- Migration: stop sidecar, install Phase 2 binary, restart privacy service. No data migration; the audit log is preserved.

---

## 5. Alternatives considered

| Alternative | Pros | Cons | Reason rejected |
|---|---|---|---|
| Do nothing | No effort | Permanent leak risk | Section 1 quantified the cases observed |
| Regex-only | Single-binary, fast | Misses contextual PII (names, paraphrased emails) | Below operator quality bar |
| LLM-only | Best contextual recall | High latency on every write | Unacceptable for write path |
| External SaaS (Microsoft Presidio cloud, Google DLP) | Mature | External dependency; conflicts with self-hosted invariant | Self-hosted invariant non-negotiable |
| Embed inside `gradatum-curator` | One less crate | Curator already 5 functions; bundling violates SRP (lesson from gatekeeper rename) | Single-responsibility preserved |
| Audit-only (no redaction) | Simpler | Doesn't prevent the leak, only records it | Section 1 motivation rejects this |

---

## 6. Drawbacks

- **Adds a Python sidecar in Phase 1.** This violates the "no external service" invariant in spirit. Mitigation: sidecar bundled in the install package, no operator action; runs as systemd service alongside the others. Still: an extra moving part to monitor.
- **False positives interrupt operator flow.** A regex matching an IP address such as `198.51.100.1` in a note about networking is technically PII but contextually fine. Mitigation: per-tenant whitelist + bypass mechanism. Operators will need a tuning period.
- **LLM latency on contextual cases.** Worst case ~1 s on an ambiguous note. Mitigation: contextual layer is opt-in; default config skips it for layer-2 high-confidence matches.
- **Audit log growth.** Every write produces a privacy event (even pass). At 50 writes/day, ~18k events/year. Mitigation: log rotation + compaction policy.
- **Operator surprise on rejection.** A `reject` policy stops the write; the agent needs to handle it. Without good error messages, this looks like a bug. Mitigation: detailed `PrivacyVerdict` returned to caller + `gradatum-cli privacy explain` command.
- **GGUF impossible.** OpenAI Privacy Filter is bidirectional non-generative; it cannot be deployed via llama.cpp/GGUF. Phase 1 must use Python ONNX; Phase 2 depends on `ort` viability.

> **AM4 reminder:** this section must be authored without AI assistance. The author should be able to defend it in a synchronous review without referring to generated text.

---

## 7. Unresolved questions

- [ ] Default policy stringency: `redact-inline` for emails seems permissive. Should default for emails be `quarantine` to force operator awareness?
- [ ] Quarantine TTL: how long does an unresolved quarantine entry stay? 30 days default? Forever?
- [ ] Cross-tenant whitelist sharing: operators in different tenants might benefit from a shared baseline whitelist. Conflict with tenant isolation.
- [ ] Phase 1 sidecar OS coverage: Python + ONNX + transformers on Windows? Tier 2 platform support per the cross-platform RFC — needs validation.
- [ ] Interaction with `gradatum-consolidate` (RFC-0003): consolidation extracts facts from notes — should facts be re-scanned for PII before persistence? Default proposal: yes, lighter scan (regex only).
- [ ] Operator override: can an operator override a `reject` decision in real-time, or must they edit policy and retry? Real-time override needs careful audit.

---

## References

- Gradatum architecture: `ARCHITECTURE.md`
- Security caveats: `PROJECT-CONTEXT.md` §12 (C9 — k-anonymity distillation in curator, deferred v1.x)
- 5 invariants: `PROJECT-CONTEXT.md` §9
- POC Radeon ONNX: `POC_CANDLE_RADEON.md`
- OpenAI Privacy Filter (Apr 2026 release) — 1.5B/50M MoE, bidirectional non-generative
- `gradatum-distill` stub (export-time k-anonymity, Phase v1.x+) — distinct from this RFC
- Companion RFC consolidation: RFC-0003
- Source: ex-spec #4 (2026-05-08) `gradatum-spec-04-privacy-filter.docx` — initial draft repositioned in this RFC

---

## Changelog

| Date | Author | Change |
|---|---|---|
| 2026-05-08 | @gradatum-maintainer | Initial creation from ex-spec #4, status: Draft |
| 2026-05-10 | opérateur | Migration NAS → gradatum-skills public repo, renumérotation RFC-SKILL-GRADATUM-0008 → RFC-0005, table header → YAML frontmatter, refs mises à jour |

---

## License

This RFC is published under Apache-2.0, aligned with the Gradatum project.

---

*End RFC-0005.*
