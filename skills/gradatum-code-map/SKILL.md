---
name: gradatum-code-map
description: >
  Interroge la carte de code dérivée d'un projet (vault `code-<projet>`) via gradatum (LIVE :19090) —
  signatures et corps de symboles (fonctions, structs, traits…) extraits par tree-sitter, sans LLM.
  Invoquer pour COMPRENDRE/NAVIGUER du code sans lire des fichiers entiers : « où est défini X ? »,
  « quelle est la signature de Y ? », « quels symboles matchent Z ? ». Économise des tokens vs la
  lecture brute. 3 modes : `query` (mots-clés), `symbol` (nom exact), `path` (par fichier). Option
  corps exact. Composable par /gradatum-skill-reminder.
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "<vault:code-X> <query|symbol|path> <value> [body]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/scope.sh *)
---

# /gradatum-code-map

Carte de code à la demande : interroge un index dérivé (tree-sitter, zéro-LLM, régénérable) plutôt
que de relire des fichiers entiers. La vérité reste le code source ; l'index est un dérivé tenu frais.

## Prérequis — ingérer le projet (une fois, puis rafraîchir)

L'index d'un projet vit dans un vault logique `code-<projet>`. Avant d'interroger :

```bash
# Ingestion initiale (git → tree-sitter → index dérivé, zéro LLM)
gradatum-admin code ingest --vault code-myproject /chemin/vers/repo

# Rafraîchir après des commits (O(diff) git — rapide)
gradatum-admin code update --vault code-myproject /chemin/vers/repo
```

Un symbole marqué `⚠️STALE` = le fichier source a changé depuis le dernier `code update` → rafraîchir.

> Si le vault `code-<projet>` n'a pas encore été ingéré, l'appel retourne une erreur — lancer
> `gradatum-admin code ingest` d'abord.

## Quand invoquer

- « Où est défini `X` ? Quelle est sa signature ? » → mode `symbol`.
- « Quels symboles concernent `Z` ? » → mode `query` (mots-clés).
- « Que contient `src/auth.rs` ? » → mode `path`.
- Comprendre une implémentation sans charger le fichier entier (économie de tokens).

## Usage

```bash
/gradatum-code-map code-myproject symbol parse_config
/gradatum-code-map code-myproject query "auth middleware"
/gradatum-code-map code-myproject path src/auth.rs
# avec le corps exact des symboles :
/gradatum-code-map code-myproject symbol parse_config body
```

Le 4e argument `body` (optionnel) inclut le **corps exact** du symbole (span tree-sitter) — utile
pour lire une implémentation précise sans charger tout le fichier.

## Output

```
🗺️ N symbole(s) [symbol=parse_config] dans code-myproject :
  src/config.rs:Config::parse_config(path: &str) -> Result<Config>
  ----
  <corps exact si `body`>
  ----
```

`⚠️STALE` après un symbole = index périmé pour ce fichier (faire `gradatum-admin code update`).

## Comment décider (interprétation)

1. **Signatures d'abord** (sans `body`) : trier les symboles pertinents à coût minimal.
2. **Corps ensuite** (`body`) : sur les symboles RETENUS uniquement (pattern 2 passes — éviter
   `body` sur une requête large, le gain tokens s'annule). **Règle** : ≤ 3 symboles ciblés →
   `body` en 1 passe OK ; > 3 → signatures d'abord, puis `body` sur les 1-3 retenus. Si l'output
   signale « corps omis par budget » → augmenter `GRADATUM_BUDGET_TOKENS` ou réduire la cible.
3. `⚠️STALE` → rafraîchir l'index avant de te fier au corps (la vérité = le source).
4. Pour de la cohérence inter-fichiers (trait ↔ impl éparpillés) ou < 3 fichiers, lire le source
   directement reste parfois préférable.

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier de la clé API |
| `GRADATUM_BUDGET_TOKENS` | `1200` (`2500` en mode `body`) | Budget tokens de la réponse |

## Anti-patterns

- Ne pas interroger un vault non préfixé `code-` (rejeté — sécu §3.3 gradatum).
- Ne pas faire `body` sur une requête `query` large (gain tokens annulé — trier par signature d'abord).
- Ne pas se fier à un corps `⚠️STALE` — rafraîchir l'index ou lire le source.
