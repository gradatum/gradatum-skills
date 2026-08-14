---
name: gradatum-vault-search
description: >
  Recherche dans le vault gradatum (LIVE :19090) — invoquer en réflexion
  ("ai-je déjà une note sur X ?", "on a tranché ce sujet ?", "je vais proposer/décider/écrire"),
  recherche explicite ("trouve les notes sur Y"), planification, brainstorming,
  avant toute écriture vault (anti-doublon). Composable par /gradatum-skill-reminder.
compatibility: claude-code (>= 2.1.0)
allowed-tools: mcp__gradatum__vault_search
---

# /gradatum-vault-search

Outil atomique de recherche dans le vault gradatum. Réutilisable par n'importe quel skill L1
(reminder, memorize) ou agent en réflexion.

## Quand invoquer

- Réflexion sur un sujet potentiellement déjà traité (avant proposition / décision / planification)
- Recherche explicite demandée par l'utilisateur ou un autre skill
- Vérification anti-doublon avant écriture vault (obligatoire avant `/gradatum-vault-write` create)
- Composition par /gradatum-skill-reminder sur prompt utilisateur non trivial

## Usage

Appeler directement l'outil **`mcp__gradatum__vault_search`** — seul `query` est requis. Les
autres paramètres (filtres, fenêtre temporelle, pagination…), leurs défauts et leurs règles de
validation sont documentés par l'inputSchema de l'outil — ne pas les recopier ici, un paramètre
dupliqué dérive dès que le serveur évolue.

Deux réflexes que le schéma seul ne donne pas :

- **Ne jamais glisser un nom de section dans la `query` texte** pour filtrer — ça pollue le
  ranking. Utiliser le paramètre de filtrage dédié.
- **Cet outil ne renvoie jamais le corps intégral de la note.** L'étape suivante naturelle est
  `mcp__gradatum__vault_read` sur le résultat pertinent.

## Mode compact — activer `compact: true`

Le paramètre `compact: true` fait remonter la réponse sous forme d'un objet unique
`{ "compact": "<texte>" }` — une projection texte optimisée pour un consommateur LLM, rendue
directement par le service (elle ne dépend plus d'un script côté client). Par défaut
(`compact` absent ou `false`), la réponse complète historique est inchangée.

Le texte compact liste chaque résultat sous la forme `<ulid> [<score>]`, et — **seulement si le
paramètre de comptage corpus a été activé sur la même requête** — ajoute une mention explicite :

- comptage à `0` ⇒ le texte énonce que l'absence de match lexical est **prouvée** et que les
  résultats affichés ne sont que des voisins sémantiques ;
- comptage `> 0` ⇒ le texte indique le nombre de matchs lexicaux dans le corpus (avec un
  marqueur si la valeur est plafonnée).

Activer `compact: true` ne suffit donc pas à obtenir cette preuve d'absence — les deux paramètres
sont indépendants et doivent être posés ensemble quand le besoin est celui du §4 ci-dessous.

## Comment décider (interprétation par l'agent)

1. **Vérifier « déjà connu »** : si le résultat figure déjà dans le contexte conversationnel
   courant, ne pas relire.

2. **Action de lecture** : `mcp__gradatum__vault_read` sur le résultat pertinent pour récupérer
   le corps complet.

3. **Résultat vide** : pas d'historique vault **classé** sur ce sujet — ce n'est pas un échec.

4. **Preuve d'absence** — usage avancé, off par défaut. La recherche est **hybride** (lexicale
   ∪ sémantique) : les résultats incluent **toujours** des voisins sémantiques. Conséquence
   attendue — cas nominal, pas une anomalie : sur une requête dont aucun mot n'est dans le
   corpus, on observe des résultats non vides **avec** un comptage lexical à zéro. Un nombre de
   résultats non nul ne prouve donc **jamais** qu'une note traite réellement du sujet.

   N'activer le comptage corpus que quand le besoin est strict : avant d'affirmer « on n'a jamais
   écrit le terme X », ou pour un anti-doublon sur un terme court/ambigu (acronyme, nom propre).
   Pour un titre descriptif normal, les résultats + scores suffisent.

   - comptage `= 0` ⇒ absence du terme prouvée. Les résultats affichés sont exclusivement des
     voisins sémantiques → à écarter pour un « a-t-on déjà ce terme ? ».
   - comptage `> 0` mais absent du haut de classement rendu ⇒ déclassé par le ranking. Relancer
     une **nouvelle** recherche explicite (fenêtre de résultats plus large, requête affinée, ou
     filtre plus précis) — ce n'est pas un retour automatique.

## Anti-patterns

- Ne pas filtrer par section en polluant la `query` — utiliser le paramètre dédié.
- Ne pas conclure « sujet absent » sur un résultat vide sans le comptage corpus activé : ça
  prouve seulement qu'aucune note n'a été **classée**, dans la surface scannée.
- Ne pas conclure « sujet présent » sur des résultats non vides : voir §4, les voisins sémantiques
  sont toujours là.
- Ne pas supposer que `compact: true` active seul la preuve d'absence — les deux paramètres sont
  indépendants (voir §Mode compact).
- Ne pas gonfler la limite de résultats par réflexe — ce skill est invoqué à chaque réponse
  substantielle par `/gradatum-skill-reminder`, l'injection de contexte est multipliée par la
  fréquence.
