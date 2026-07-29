#!/usr/bin/env bash
#
# Génère les illustrations de produits pour la caisse.
#
# La clé API est lue depuis OPENAI_API_KEY, chargée depuis .env s'il existe.
# Sa valeur n'est ni affichée, ni journalisée, ni recopiée nulle part, et n'est
# envoyée qu'à l'API OpenAI.
#
#   cp .env.example .env    puis y mettre la clé
#   ./scripts/generer-images.sh                    # les quelques produits de démonstration
#   ./scripts/generer-images.sh baguette croissant # des produits précis
#
# Les fichiers atterrissent dans img/products/<slug>.png, ce qui est exactement
# ce que la caisse va chercher. Un produit sans image s'affiche normalement,
# sans trou : rien n'oblige à toutes les générer.

set -euo pipefail

cd "$(dirname "$0")/.."

# Chargement de .env s'il est là. `set -a` exporte automatiquement tout ce que
# le fichier définit ; aucune valeur n'est affichée au passage.
if [ -f .env ]; then
	set -a
	# shellcheck disable=SC1091
	. ./.env
	set +a
fi

# Volontairement un test explicite plutôt que ${VAR:?message} : dans cette
# forme, bash interprète les quotes du message, et la moindre apostrophe
# française y ouvre une chaîne qui ne se referme jamais.
if [ -z "${OPENAI_API_KEY:-}" ]; then
	echo "La variable OPENAI_API_KEY est vide ou absente." >&2
	echo "Voir le README, section « Images des produits »." >&2
	exit 1
fi

command -v jq   >/dev/null || { echo "jq est requis : brew install jq" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl est requis" >&2; exit 1; }

DEST="img/products"
mkdir -p "$DEST"

# Style commun à toutes les images. L'homogénéité compte plus que le réalisme :
# des illustrations qui se ressemblent forment une grille lisible, des photos
# hétéroclites font une grille brouillonne.
STYLE="Illustration produit simple et appétissante, vue de trois quarts, objet unique centré, \
style plat et épuré aux couleurs chaudes et naturelles, fond entièrement transparent, \
sans texte, sans emballage, sans main, sans assiette, sans ombre portée."

# slug|description du produit
PRODUITS=(
	"baguette|une baguette de pain française dorée et croustillante"
	"croissant|un croissant au beurre doré et feuilleté"
	"pain-gris-500g|une miche de pain gris rustique"
	"eclair-chocolat|un éclair au chocolat glacé"
	"couque-au-chocolat|un pain au chocolat feuilleté"
	"cafe|une tasse de café expresso"
)

# Si des slugs sont passés en argument, on ne garde que ceux-là.
if [ $# -gt 0 ]; then
	FILTRE=("$@")
	SELECTION=()
	for entree in "${PRODUITS[@]}"; do
		slug="${entree%%|*}"
		for voulu in "${FILTRE[@]}"; do
			[ "$slug" = "$voulu" ] && SELECTION+=("$entree")
		done
	done
	if [ ${#SELECTION[@]} -eq 0 ]; then
		echo "Aucun produit connu parmi : $*" >&2
		echo "Slugs disponibles : $(printf '%s ' "${PRODUITS[@]%%|*}")" >&2
		exit 1
	fi
	PRODUITS=("${SELECTION[@]}")
fi

echo "→ ${#PRODUITS[@]} image(s) à générer, qualité basse (la moins coûteuse)."
echo

for entree in "${PRODUITS[@]}"; do
	slug="${entree%%|*}"
	desc="${entree#*|}"
	sortie="$DEST/$slug.png"

	if [ -f "$sortie" ]; then
		echo "  = $slug (déjà présent, ignoré)"
		continue
	fi

	printf '  · %s … ' "$slug"

	reponse=$(jq -n \
		--arg prompt "$desc. $STYLE" \
		'{model:"gpt-image-1", prompt:$prompt, n:1, size:"1024x1024",
		  quality:"low", background:"transparent", output_format:"png"}' \
		| curl -sS https://api.openai.com/v1/images/generations \
			-H "Authorization: Bearer $OPENAI_API_KEY" \
			-H "Content-Type: application/json" \
			--data-binary @-)

	if ! b64=$(printf '%s' "$reponse" | jq -er '.data[0].b64_json' 2>/dev/null); then
		echo "échec"
		# On affiche le message d'erreur de l'API, jamais la requête (qui porte la clé).
		printf '%s' "$reponse" | jq -r '.error.message // "réponse inattendue"' >&2
		continue
	fi

	printf '%s' "$b64" | base64 --decode > "$sortie"

	# Réduction : la caisse tourne sur un Celeron de 2013, décoder du 1024×1024
	# pour l'afficher dans une vignette serait du gaspillage pur.
	if command -v sips >/dev/null; then
		sips -Z 320 "$sortie" >/dev/null 2>&1 || true
	fi

	echo "ok ($(du -h "$sortie" | cut -f1))"
done

echo
echo "Terminé. Rechargez la page de la caisse pour voir le résultat."
