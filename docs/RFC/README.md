# RFCs — gradatum-skills

Index of design proposals for the Gradatum memory backbone engine and related gradatum-skills plugin features.

RFCs in this repo cover features and processes for the Gradatum engine (`gradatum`, `gradatum-www`), the gradatum-skills Claude Code distributable plugin, and the cross-cutting meta-processes applying to Gradatum RFC governance.

Conventions for this repo — RFC vs ADR, header format, cross-repo refs — are defined below under **Templates and guidance**.

## Current RFCs

| Number | Title | Status | Date | Phase target |
|---|---|---|---|---|
| [RFC-0001](RFC-0001-curator-multi-tag-classification.md) | Curator: multi-tag classification with reflective improvement | `Draft` | 2026-05-08 | Phase 3+ |
| [RFC-0002](RFC-0002-apport-skills.md) | Contribution enrichments to gradatum self-improvement RFC | `Draft` | 2026-05-08 | meta (proposal layer) |
| [RFC-0003](RFC-0003-consolidate-knowledge-distillation.md) | gradatum-consolidate: knowledge consolidation | `Draft` | 2026-05-08 | Phase 3+ |
| [RFC-0004](RFC-0004-curator-zero-loss-compression.md) | Curator: zero-loss compression and dedup with fidelity guard | `Draft` | 2026-05-08 | Phase 4+ |
| [RFC-0005](RFC-0005-privacy-write-time-filter.md) | gradatum-privacy: PII filtering at write-time | `Draft` | 2026-05-08 | Phase 3+ |
| [RFC-0006](RFC-0006-skills-distribution-and-discovery.md) | Skills distribution and discovery (with vault-discipline reference skill) | `Draft` | 2026-05-08 | Phase 3 |
| [RFC-0007](RFC-0007-curator-confidence-ladder.md) | Curator confidence ladder — pending → confirmed → canonical | `Draft` | 2026-05-09 | Phase 3 |
| [RFC-0008](RFC-0008-audit-noise-allowlist.md) | Audit-noise allowlist appliquée à Gradatum CI | `Draft` | 2026-05-09 | Phase 2 |
| [RFC-0009](RFC-0009-success-criteria-measurable.md) | Success criteria measurable in RFCs — boomerang plan vs reality | `Draft` | 2026-05-09 | meta-process |
| [RFC-0010](RFC-0010-dynamic-category-proposal.md) | Dynamic category proposal & promotion | `Draft` (orientation amont à clarifier opérateur — 3 options A/B/C dans §2 UNRESOLVED) | 2026-05-10 | TBD (fonction orientation) |

**Note** : RFC-0009 (Success criteria measurable) is `required_by` all future RFCs — it defines the pattern for adding chiffered success criteria and validation reports that future RFCs must follow.

**Note RFC-0010** : ce RFC est en `Draft` initial, **orientation amont non encore validée** (sections canoniques du serveur vs tags libres vs sous-catégories per-projet). Il ne passera `Discussion` qu'après clarification §2.

## Process

1. **Draft:** Author creates a PR adding a new RFC markdown file, numbered sequentially.
2. **Discussion:** Minimum 7 days for maintainer comment. Non-maintainers may comment; only maintainers block/approve.
3. **Resolution:** Marked `Accepted`, `Postponed`, or `Rejected`. Rejected RFCs remain in the repo for historical reference.
4. **Implementation:** Tracked issue created; implementation PRs cross-reference the RFC number.
5. **Validation:** At exit of implementation phase, a validation report is committed to `docs/rfc-validation/<rfc>-phase-N.md` (per RFC-0009).

**RFC numbering is monotonic and never reused.**

## Templates and guidance

- Use [`../../RFC-TEMPLATE.md`](../../RFC-TEMPLATE.md) as the skeleton.
- Header format: YAML frontmatter — see [`../../RFC-TEMPLATE.md`](../../RFC-TEMPLATE.md) for the field set.
- Cross-repo refs: `<repo>:RFC-XXXX` (e.g. `libskills:RFC-0001`, `gradatum:RFC-0005`).
- Intra-repo refs: `RFC-XXXX` direct (no prefix needed).
- Focus on **why** (motivation) and **what** (design). Implementation follows.
- Include alternatives, drawbacks, and unresolved questions.
- Include **chiffered success criteria** (required since RFC-0009).

## Cross-repo dependencies

Several gradatum-skills RFCs depend on or are related to RFCs in other repos:

| This RFC | Depends on / Related to | Cross-repo |
|---|---|---|
| RFC-0002 | Self-improvement RFC | `gradatum:RFC-0005` |
| RFC-0003 | Self-improvement RFC | `gradatum:RFC-0005` |
| RFC-0006 | HTTP API RFC, Self-improvement RFC | `gradatum:RFC-0003`, `gradatum:RFC-0005` |
| RFC-0007 | Quarantaine pattern, Gradatum versioning | `libskills:RFC-0001`, `gradatum:RFC-0001` |
| RFC-0007 | Cross-platform, HTTP API | `gradatum:RFC-0002`, `gradatum:RFC-0003` |
| RFC-0008 | Audit-noise allowlist source pattern | `libskills:RFC-0008` |
| RFC-0009 | Gradatum versioning RFC | `gradatum:RFC-0001` |
| RFC-0010 | Quarantaine pattern (libskills), reflective curator | `libskills:RFC-0001`, RFC-0001 + RFC-0007 (intra-repo) |

## Historical RFCs (future)

As the project grows, accepted and rejected RFCs will accumulate here.
