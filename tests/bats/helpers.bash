# helpers.bash — Utilitaires partagés des suites bats. Chargé par `load helpers`.
#
# Ce fichier n'est pas une suite : il ne porte aucun @test et son nom ne matche
# pas `*.bats`, donc il n'est jamais collecté comme test.

# Un skip est une propriété NON VÉRIFIÉE, pas une propriété tenue. Le TAP le
# note discrètement (`ok N # skip …`) et un lecteur pressé lit « ok ». Or les
# tests sautables sont précisément ceux qui interrogent le monde réel — le
# chargeur de plugin, le serveur MCP — c'est-à-dire les seuls à pouvoir lever un
# défaut que la forme des fichiers ne montre pas. Les taire sur un runner
# dépourvu d'un binaire ou d'une identité rendrait la suite verte sans avoir
# regardé là où ça compte.
#
# D'où deux mesures : une bannière sur le flux de sortie de bats (FD 3), et
# GRADATUM_SKILLS_STRICT=1 qui convertit toute absence de vérification en échec
# — à poser sur tout runner censé rendre un verdict complet.
#
# $1 = propriété non vérifiée (ce que le test aurait prouvé)
# $2 = raison (ce qui manque dans cet environnement)
skip_bruyant() {
  local propriete="$1" raison="$2"
  {
    echo ""
    echo "  !! PROPRIÉTÉ NON VÉRIFIÉE : $propriete"
    echo "     raison : $raison"
    echo "     ce test ne prouve RIEN dans cet environnement"
    echo "     (GRADATUM_SKILLS_STRICT=1 en fait un échec au lieu d'un saut)"
  } >&3
  if [ "${GRADATUM_SKILLS_STRICT:-0}" = "1" ]; then
    echo "STRICT — propriété non vérifiée : $propriete ($raison)" >&2
    return 1
  fi
  skip "NON VÉRIFIÉ — $propriete ($raison)"
}
