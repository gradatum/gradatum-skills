---
name: gradatum-vault-read
description: >
  Lit le contenu COMPLET d'une note du vault gradatum (LIVE :19090) par son chemin
  (`<section>/<ulid>`). À utiliser APRÈS /gradatum-vault-search (qui ne renvoie que des chemins +
  scores, PAS le corps des notes) ou quand un chemin est déjà connu. Ne cherche pas — exige un
  chemin exact. Output : markdown intégral + `sha256` (requis pour une mise à jour in-place
  ultérieure). Étape suivante naturelle d'un /gradatum-vault-search.
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__vault_read
---

# /gradatum-vault-read

Outil atomique de lecture d'une note gradatum par chemin. Complément naturel de
/gradatum-vault-search (qui renvoie des chemins, pas le corps).

## Quand invoquer

- Après un /gradatum-vault-search : récupérer le corps complet d'un résultat pertinent.
- Quand un chemin de note est déjà connu (cité dans le contexte, un lien `[[section:ulid]]`).
- **Avant une mise à jour in-place** : récupérer le `sha256` courant, requis par
  /gradatum-vault-write pour l'optimistic-lock.
- **Après une écriture**, pour confirmer qu'elle a bien abouti — voir la clause de vérification
  dans /gradatum-vault-write. L'écriture est asynchrone et son échec est silencieux.

## Usage

Appeler directement l'outil **`mcp__gradatum__vault_read`** avec `path = "<section>/<ulid>"`
(requis). `section` et `tenant_id` sont optionnels — voir l'inputSchema de l'outil pour leur
comportement exact ; ne pas le dupliquer ici.

Le chemin est `<section>/<ulid>`. Sections : reflet opérationnel de `Section::ALL` (le code
serveur fait foi) — liste normative dans `/gradatum-vault-write` §Sections canoniques ; la
gouvernance de cette taxonomie relève de l'installation. Inclut `project-map` (écriture
hint-only, lecture normale par ce chemin).

## Output

Réponse JSON. Champs utiles :

| Champ | Usage |
|---|---|
| `content` | le corps markdown intégral |
| `sha256` | **empreinte du corps courant** — à conserver pour une MAJ in-place |
| `title` | titre de la note (peut être absent/`null`) |
| `metadata.section` · `.status` · `.tags` · `.created` · `.updated` · `.vault_id` · `.author` | contexte |
| `size_bytes` | volume — utile pour décider de lire ou non la suite |

⚠️ **Vérifié empiriquement le 2026-07-31** (appel réel `vault_search` → `vault_read` sur
`decisions/01KYHG134JYY2GHE7KQXGXR3SN`) : le champ `path` de la réponse est renvoyé **en ULID
nu** (`"01KYHG134JYY2GHE7KQXGXR3SN"`), **sans** le préfixe de section, alors que l'appel
l'exigeait préfixé. Ne pas réinjecter cette valeur telle quelle dans un appel suivant sans
re-préfixer — reconstruire le chemin complet à partir de `metadata.section` + ce `path` nu si
besoin.

> Note (champ `title`, version-aware) : `vault_read` expose un champ `title` séparé — présent à
> partir de gradatum v0.5.2 (la ligne n'apparaît/n'est non-nulle que s'il est dérivable). Sur
> gradatum **≤ v0.4.3** ce champ est absent — le titre est alors la 1ʳᵉ ligne de titre H1 du corps
> markdown. ⚠️ Pour une MAJ in-place, le `title` de MAJ ne doit **jamais** être sourcé
> uniquement depuis ce champ — voir la règle de provenance dans les Anti-patterns de
> `/gradatum-vault-write`.

En cas de note absente : l'appel d'outil échoue (équivalent 404).

## Comment décider (interprétation)

1. Si l'ULID figure déjà dans le contexte courant **avec son contenu** → ne pas relire.
2. Le `sha256` est l'empreinte du corps courant : le conserver si une écriture in-place suivra
   (garantit qu'on n'écrase pas une modification concurrente — voir aussi le comportement réel du
   verrou optimiste documenté dans `/gradatum-vault-write`).
3. Note absente ≠ erreur fatale : le chemin peut être périmé → re-chercher via
   /gradatum-vault-search.

## Anti-patterns

- Ne pas utiliser pour CHERCHER (→ /gradatum-vault-search) : read exige un chemin exact.
- Ne pas reconstruire un chemin depuis un ULID tronqué — l'ULID fait **26 caractères**.
- Ne pas écrire via ce skill (lecture seule).
- Ne pas enchaîner plus de ~3 lectures sans nécessité : un corps complet fait couramment 5-10 KB
  et gonfle le contexte. Lire les notes strictement utiles — `size_bytes` aide à arbitrer.
- Ne pas sourcer un `title` de MAJ **uniquement** depuis ce champ `title` — règle de provenance
  dans les Anti-patterns de /gradatum-vault-write.
- Ne pas réinjecter le `path` de la réponse tel quel dans un appel suivant — il est rendu nu (voir
  §Output ci-dessus).
