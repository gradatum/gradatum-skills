---
name: gradatum-code-map
description: >
  Interroge la carte de code dérivée d'un projet (vault logique `code-<projet>`) via gradatum
  (LIVE :19090) — signatures et corps de symboles (fonctions, structs, traits…) extraits par
  tree-sitter, sans LLM. Invoquer pour COMPRENDRE/NAVIGUER du code sans lire des fichiers
  entiers : « où est défini X ? », « quelle est la signature de Y ? », « quels symboles
  matchent Z ? », « qui appelle X ? ». Économise des tokens vs la lecture brute. Composable par
  /gradatum-skill-reminder.
type: gradatum
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__code_scope
---

# /gradatum-code-map

Carte de code à la demande : interroge un index dérivé (tree-sitter, zéro-LLM, régénérable) plutôt
que de relire des fichiers entiers. La vérité reste le code source ; l'index est un dérivé tenu
frais.

## Prérequis — ingérer le projet (une fois, puis rafraîchir)

L'index d'un projet vit dans un vault logique `code-<projet>`. Cette ingestion et son
rafraîchissement sont une opération d'administration CLI, distincte de l'outil MCP interrogé par
ce skill — ils ne passent pas par `mcp__gradatum__code_scope`. Si le vault `code-<projet>` n'a
jamais été ingéré, l'appel de l'outil échoue : lancer l'ingestion (puis le rafraîchissement après
des commits) avant d'interroger.

## Quand invoquer

- « Où est défini `X` ? Quelle est sa signature ? » → recherche par nom de symbole.
- « Quels symboles concernent `Z` ? » → recherche par mots-clés.
- « Que contient `src/auth.rs` ? » → recherche par chemin de fichier.
- « Qui appelle `X` ? » → dépendance inverse (voir §Corps et appelants).
- Comprendre une implémentation sans charger le fichier entier (économie de tokens).

## Usage

Appeler directement l'outil **`mcp__gradatum__code_scope`** — requis : le vault cible et un
critère de recherche. Le vault cible doit désigner un projet indexé (préfixe `code-`) — un vault
qui ne le porte pas est rejeté, c'est une invariant de sécurité, pas une option. Les autres
paramètres (forme du critère, budget de réponse, inclusion du corps exact, inclusion des
appelants…), leurs défauts et leurs règles de validation sont documentés par l'inputSchema de
l'outil — ne pas les recopier ici.

## Comment décider (interprétation)

1. **Signatures d'abord** (sans le corps exact) : trier les symboles pertinents à coût minimal.
2. **Corps ensuite**, sur les symboles **retenus** uniquement — pattern deux passes obligatoire :
   activer le corps exact sur une requête large annule le gain de tokens que l'index apporte.
   Passe 1 large sans corps → passe 2 ciblée avec corps sur les seuls symboles sélectionnés.
3. Une entrée marquée **périmée** (le fichier source a changé depuis le dernier index) ne doit
   jamais être utilisée comme vérité — une régénération est déjà déclenchée côté serveur ; ne pas
   te fier à son corps, relire le fichier source directement si besoin immédiat.
4. Si la réponse signale que des entrées ou des corps ont été omis par dépassement du budget de
   réponse, resserrer le critère de recherche plutôt que d'élargir aveuglément le budget.

## Corps et appelants — deux capacités additives, off par défaut

- **Corps exact** : le corps d'un symbole n'est jamais renvoyé silencieusement s'il est périmé —
  une entrée périmée n'a jamais de corps, même si demandé.
- **Appelants** (dépendance inverse) : liste les symboles qui dépendent du symbole ciblé —
  répond directement à « qui appelle X ? » sans grep manuel. La liste peut être tronquée pour un
  symbole massivement utilisé (ex. une fonction utilitaire commune) ; un signal dédié l'indique
  quand c'est le cas — ne pas présenter une liste tronquée comme exhaustive.

Ces deux capacités sont indépendantes l'une de l'autre et du budget de signatures — les activer
n'affecte pas le nombre de symboles retournés en tête.

## Anti-patterns

- Ne pas interroger un vault qui ne porte pas le préfixe réservé aux projets de code — rejeté.
- Ne pas activer le corps exact sur une requête large (mots-clés non ciblés) — trier par
  signature d'abord, corps ensuite sur la sélection.
- Ne pas se fier au corps d'une entrée périmée — le corps est de toute façon absent dans ce cas ;
  lire le fichier source si la fraîcheur immédiate importe.
- Ne pas présenter une liste d'appelants tronquée comme exhaustive sans vérifier le signal de
  troncature.
- Pour de la cohérence inter-fichiers étroite (trait ↔ impl éparpillés) ou un très petit nombre de
  fichiers concernés, lire le source directement reste parfois plus simple que cet outil.
