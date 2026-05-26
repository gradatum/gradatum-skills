---
name: gradatum-skill-reminder
description: >
  Recall pré-action métamémoire — sur prompt utilisateur (question, recherche, brainstorming,
  diagnostic, amorce de tâche substantielle, décision, planification), détermine si une
  recherche vault gradatum est pertinente et invoque /gradatum-vault-search avec les mots-clés
  extraits. SKIP si validation/négation seule ("oui", "go", "ok"), exécution commande directe,
  slash-command, salutation, ou prompt trivial (<10 caractères utiles).
  Stateless. Zéro script propre — pure logique de décision.
type: gradatum
compatibility: claude-code (>= 2.1.0)
---

# /gradatum-skill-reminder

Déclencheur métamémoire — détermine si le prompt courant nécessite une recherche vault,
et délègue à /gradatum-vault-search. Pure logique de décision, zéro script propre.

## Règles de décision (évaluées sur le prompt utilisateur courant)

### CHERCHE — invoquer /gradatum-vault-search si le prompt est :

- **Question** ("comment", "pourquoi", "que fait", "qu'est-ce que", "on a déjà", "c'est quoi")
- **Recherche / exploration** ("on creuse", "analyse", "étudie", "compare", "cherche")
- **Brainstorming** ("réfléchis", "propose", "imagine", "design", "idées", "options")
- **Diagnostic** ("ça plante", "erreur", "comprends pas", "pourquoi ça fail", "debug")
- **Décision / planification** ("on va", "je veux", "plan", "on commence", "étape", "roadmap")
- **Amorce de tâche substantielle** (≥ 1 verbe métier + objet concret identifiable)
- **Mots-clés vault-mem / gradatum** ("vault_search", "écrire note", "récupérer décision",
  "architecture", "décisions", "council", "retrospective", "lessons-learned", "memo")

### SKIP — ne rien invoquer, traiter normalement si le prompt est :

- **Validation / négation seule** ("oui", "go", "valide", "non", "stop", "ok", "c'est ça",
  "continue", "parfait", "bien", "merci")
- **Exécution commande directe** ("lance X", "exécute Y", "run Z", "fais X")
- **Slash command** (/gradatum-vault-search, /memo, etc.)
- **Salutation / social** ("bonjour", "merci", "à plus", "bonne journée")
- **Trivial** (< 10 caractères utiles dans le prompt)

## Action si CHERCHE

1. Extraire 3 à 7 mots-clés sémantiques du prompt courant
   (verbes métier + objets concrets ; exclure les mots-vides)
2. Invoquer `/gradatum-vault-search "<keywords concaténés>"`
3. L'agent reçoit l'output et décide selon la doctrine portée par /gradatum-vault-search

## Action si SKIP

Ne rien faire. Pas d'output. Traiter le prompt normalement.

## Sections canoniques gradatum (NOMENCLATURE §10)

Les 11 sections disponibles dans le vault gradatum pour orienter les recherches :

| Section | Contenu typique |
|---|---|
| `decisions` | Choix structurels actés — architecture, services, orientations |
| `council` | Verdicts council Art.19 / Art.15bis / Art.18 |
| `commits` | Traces événements git significatifs |
| `debug` | Bugs résolus, anomalies, diagnostics |
| `lessons-learned` | Apprentissages post-mortem, patterns terrain |
| `architecture` | Cartographies, schémas, ADRs techniques |
| `agent-issues` | Comportements agents problématiques, résolutions |
| `roadmap` | Plans, backlog, jalons futurs |
| `retrospectives` | Bilans de phase, retours d'expérience |
| `reasoning` | Patterns de raisonnement, modèles mentaux |
| `project-bootstrap` | Création projets, scaffolding initial |

## Convention titre vault (anti-doublon)

Format strict : `[CATÉGORIE][PROJET] Verbe objet — date`

Exemples valides :
- `[DECISIONS][gradatum] Choix reranker BGE-v2-m3 — 2026-05-10`
- `[COUNCIL][homelab] Art.19 v3 GO renommage skills — 2026-05-10`
- `[RETRO][nexus-library] Phase M2 LIVRÉE — 2026-03-07`

## Anti-patterns

- Ne pas se substituer à /gradatum-vault-search pour la recherche effective
- Ne pas interpréter les résultats de /gradatum-vault-search (délégué à l'agent appelant)
- Ne pas mémoriser d'état entre invocations (stateless par design)
