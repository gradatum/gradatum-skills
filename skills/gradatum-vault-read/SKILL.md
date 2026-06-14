---
name: gradatum-vault-read
description: >
  Lit le contenu COMPLET d'une note du vault gradatum (LIVE :19090) par son chemin
  (`<section>/<ulid>`). À utiliser APRÈS /gradatum-vault-search (qui ne renvoie que des
  ULID + score, PAS le corps des notes) ou quand un chemin est déjà connu. Ne cherche
  pas — exige un chemin exact. Output : markdown intégral + sha256 (requis pour une mise
  à jour in-place ultérieure). Étape suivante naturelle d'un /gradatum-vault-search.
type: gradatum
compatibility: claude-code (>= 2.1.0)
argument-hint: "<section>/<ulid>"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/read.sh *)
---

# /gradatum-vault-read

Outil atomique de lecture d'une note gradatum par chemin. Complément naturel de
/gradatum-vault-search (qui renvoie des ULID, pas le corps).

## Quand invoquer

- Après un /gradatum-vault-search : récupérer le corps complet d'un ULID pertinent.
- Quand un chemin de note est déjà connu (cité dans le contexte, un lien `[[section:ulid]]`).
- Avant une mise à jour in-place d'une note : récupérer son `sha256` courant (requis pour
  l'écriture concurrente-safe via /gradatum-vault-write).

## Usage

```bash
/gradatum-vault-read "decisions/01KV2P38DTQ0V9H9581GF0RVTQ"
```

Le chemin est `<section>/<ulid>`. Les sections canoniques : `architecture`, `decisions`,
`council`, `debug`, `reasoning`, `feedback`, `lessons-learned`, `retrospectives`,
`experiments`, `agent-issues`, `reference`.

## Output

```
📄 <path>  [section: <section>]
sha256: <hash>   (à fournir à vault_write pour une MAJ in-place)
---
<contenu markdown intégral>
```

> Note : `vault_read` ne renvoie pas de champ `title` séparé — le titre est la 1ʳᵉ ligne de
> titre du corps markdown. L'en-tête affiche le `path` + la `section`.

En cas de note absente : `📄 note introuvable : <path>` (exit ≠ 0).

## Comment décider (interprétation)

1. Si l'ULID figure déjà dans le contexte conversationnel courant avec son contenu → pas
   besoin de relire.
2. Le `sha256` retourné est l'empreinte du corps courant : le conserver si une écriture
   in-place suivra (garantit qu'on n'écrase pas une modification concurrente).
3. Note absente (404) ≠ erreur fatale : le chemin peut être périmé — re-chercher via search.

## Variables d'environnement

| Variable | Défaut | Description |
|---|---|---|
| `GRADATUM_SERVER_URL` | `http://<gradatum-server>` | URL du serveur gradatum |
| `GRADATUM_API_KEY_FILE` | `/etc/gradatum/claude-code.api-key` | Fichier de la clé API |

## Anti-patterns

- Ne pas utiliser pour CHERCHER (→ /gradatum-vault-search) : read exige un chemin exact.
- Ne pas reconstruire un chemin à partir d'un ULID tronqué — utiliser l'ULID 26 caractères complet.
- Ne pas écrire via ce skill (lecture seule).
- Ne pas lire plus de ~3 notes en cascade sans nécessité : le corps complet peut être volumineux
  (5-10 KB) et gonfler le contexte. Lire les notes strictement utiles.
