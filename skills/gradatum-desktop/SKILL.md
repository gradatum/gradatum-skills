---
name: gradatum-desktop
description: >
  À déclencher quand l'utilisateur veut retrouver une décision/note/bug passé,
  mémoriser ou archiver une information, ou interroge sa base de connaissance
  gradatum via le connecteur MCP (Claude Desktop, pure MCP — aucun script local).
  Couvre : search-before-write, triage des sections, format de titre, anti-rejet
  gatekeeper, prudence outils destructifs. Mots-clés : vault, gradatum, mémoire,
  chercher, note, décision, souviens-toi, archive.
type: gradatum
compatibility: claude-desktop (connecteur MCP Streamable HTTP)
---

# gradatum-desktop — Vault gradatum via MCP (Claude Desktop)

> Variante **Claude Desktop** des skills `gradatum-*` de ce dépôt. Tous, celui-ci
> compris, passent exclusivement par les outils du serveur MCP gradatum : le dépôt
> ne contient aucun script, et aucun skill ne déclare d'outil `Bash`. Ce qui
> distingue celui-ci est le **harnais cible**, déclaré en frontmatter — les autres
> portent `compatibility: claude-code`, celui-ci `claude-desktop`. Conséquence
> concrète et unique raison de son existence : ce runtime n'a pas accès au système
> de fichiers du dépôt, donc pas aux autres `SKILL.md` ; ce fichier doit se
> suffire à lui-même là où les autres peuvent renvoyer à une autorité voisine.
> claude.ai web : non supporté à ce jour — les custom connectors web exigent
> OAuth ou une URL sans header, et gradatum est Bearer-only.

## Pré-requis (une fois, nécessite Node ≥ 18 pour `npx`)

Le serveur gradatum expose son endpoint MCP (Streamable HTTP) sur `/mcp`,
authentifié par clé API. L'interface « custom connector » ne permettant pas
d'ajouter des headers, passez par le bridge `mcp-remote` dans
`claude_desktop_config.json` (forme `env` — évite le bug de split d'arguments
sur espaces, notamment sous Windows) :

```json
{
  "mcpServers": {
    "gradatum": {
      "command": "npx",
      "args": [
        "mcp-remote", "https://<votre-hote-gradatum>/mcp",
        "--header", "Authorization:${AUTH_HEADER}"
      ],
      "env": { "AUTH_HEADER": "Bearer <votre-cle-api>" }
    }
  }
}
```

Créez une clé **dédiée** à ce poste (`gradatum-admin api-key create`) : elle est
révocable indépendamment et les écritures porteront son identité (auditables).

## Réflexe n°1 — chercher AVANT de répondre ou d'écrire

Toute question sur un projet, une décision passée, un bug déjà vu →
`vault_search` d'abord. Toute écriture → `vault_search` d'abord (si une note
similaire existe : enrichir, pas dupliquer).

- La recherche est **hybride** (lexicale + sémantique) : elle renvoie toujours
  des voisins, même hors sujet — juger par score et titre, ne pas conclure
  « ça existe » sur la seule présence de résultats.
- Une note reflète ce qui était vrai à sa date : en cas d'enjeu, signaler l'âge
  de l'information.
- Lecture complète : `vault_read` (par `note_id` ULID) · chronologie :
  `vault_timeline` · graphe de liens : `vault_links` / `vault_trace` ·
  code indexé : `code_scope` (vaults `code-<projet>`).

## Écrire — via `vault_write`, triage section (copie locale MCP-only — resynchroniser depuis `/gradatum-vault-write` à chaque extension de la taxonomie ; ce runtime n'a pas accès filesystem à cette autorité)

Écriture via **`vault_write`** — passez la section choisie en `section_hint`
(évite la re-classification serveur) :

| Signal | Section |
|---|---|
| « on a tranché X / arbitrage validé » | `decisions` |
| Verdict multi-experts / délibération | `council` |
| Choix d'architecture, pattern structurel | `architecture` |
| Bug spécifique + fix (première occurrence) | `debug` |
| Plan réutilisable qui a fonctionné | `reasoning` |
| Retour/validation/correction de l'opérateur | `feedback` |
| Pattern récurrent (≥ 2 occurrences) | `lessons-learned` |
| Bilan de fin de phase/milestone | `retrospectives` |
| Hypothèse testée + résultat (positif OU négatif) | `experiments` |
| Erreur récurrente d'un agent | `agent-issues` |
| Pointeur vers un système externe | `reference` |
| Unité de travail à cycle de vie, statut → `DONE`, rattachée à une version | `project-map` (**hint-only** — `section_hint` explicite requis, jamais par heuristique ; **writer dédié côté installation**, hors d'atteinte depuis ce runtime) |

⚠️ **`project-map` est une carte, pas une note** : insupprimable (`PROTECTED_DELETE`, sans
bypass), et son cycle de vie est tenu par un writer dédié côté installation — écrire à côté de
lui désynchronise la carte sans erreur. Depuis ce runtime **MCP-only, ne pas écrire directement
dans `project-map`** : **escalader** à l'opérateur, pour que la carte soit créée par ce writer.

> Reflet opérationnel de `Section::ALL` (code serveur, source publique) — liste normative
> détaillée dans `/gradatum-vault-write`. La gouvernance de cette taxonomie relève de
> l'installation, pas de ce fichier.

Distinctions : `debug` = 1er incident, `lessons-learned` = consolidation ≥ 2× ;
`decisions` = arbitrage ponctuel, `retrospectives` = bilan multi-tâches.

## Format d'une note

- **Titre** : `[CATÉGORIE][projet] Verbe-passé + objet concret — date ISO`
  (ex. `[DECISIONS][mon-projet] Choisi reranker BGE-v2-m3 — 2026-05-10`).
  Test : un titre applicable à deux projets sans modification est trop générique.
- **Body** : constat factuel + condition de réapplication + référence concrète
  (commit, event, mesure). ≤ 500 mots. Dates absolues ISO 8601.
- **Wikilinks** vers les notes référencées — deux formes résolues par le moteur :
  `[[section:ULID]]` (préférée, déterministe — l'ULID vient des résultats de
  `vault_search`) ou `[[titre de la note]]` (match exact puis fuzzy).
- **Tags** : 3-5, `[projet, scope, outcome]`, minuscules-avec-tirets.
- `occurred_at` si la date de l'événement diffère d'aujourd'hui.
- L'écriture est **asynchrone** : l'outil renvoie un `note_id` immédiatement,
  la note est visible quelques secondes plus tard — ne pas ré-émettre.

## Maximiser l'acceptation (gatekeeper)

Le vault peut être configuré avec un gatekeeper LLM qui rejette les notes
prescriptives non ancrées. Pour maximiser l'acceptation :
1. **Composant/projet nommé** dans le body (ancre concrète) ;
2. **Constat daté** (ISO + référence : commit, event, mesure) ;
3. **Tag de processus ou de domaine** spécifique.

❌ « Il faut toujours tester avant de déployer » (directive pure).
✅ « [FEEDBACK][mon-projet] Validation absente 2026-07-05 post-commit abc1234 →
règle process-discipline : … »

## Prudence — outils destructifs

`vault_forget`, `vault_downgrade`, `vault_restore` : uniquement sur demande
explicite de l'opérateur, jamais d'initiative. Ne jamais écrire de secrets
(clés, tokens, mots de passe) dans une note. En cas de « non authentifié »
persistant : la clé a pu être révoquée — le signaler, ne pas réessayer en boucle.
