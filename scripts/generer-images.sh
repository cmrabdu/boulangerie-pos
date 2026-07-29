#!/usr/bin/env bash
#
# Génère les illustrations de produits pour la caisse.
#
# La clé est lue depuis OPENAI_API_KEY, chargée depuis .env s'il existe. Sa
# valeur n'est ni affichée, ni journalisée, ni recopiée, et n'est envoyée qu'à
# l'API OpenAI.
#
#   ./scripts/generer-images.sh                        # style retenu, vers img/products/
#   ./scripts/generer-images.sh --style plat           # un style précis
#   ./scripts/generer-images.sh --essai croissant …    # comparatif vers img/essais/<style>/
#   ./scripts/generer-images.sh --liste                # styles et produits connus
#
# Modèle : gpt-image-1.5 par défaut. gpt-image-2 est volontairement écarté —
# il ne gère pas les fonds transparents, or c'est la transparence qui permet à
# un produit de se poser sur la carte sans rectangle blanc autour.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
	set -a
	# shellcheck disable=SC1091
	. ./.env
	set +a
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
	echo "La variable OPENAI_API_KEY est vide ou absente." >&2
	echo "Voir le README, section « Images des produits »." >&2
	exit 1
fi

command -v jq >/dev/null || { echo "jq est requis : brew install jq" >&2; exit 1; }

MODELE="${MODELE:-gpt-image-1.5}"
QUALITE="${QUALITE:-low}"
TAILLE="${TAILLE:-1024x1024}"

# --------------------------------------------------------------------------
# Styles
#
# Le sujet est décrit à part ; le style, lui, est ce qu'on fait varier. Les
# trois familles ci-dessous sont volontairement éloignées : on ne compare pas
# trois nuances d'une même idée, on compare trois partis pris.
#
# Contrainte commune à tous : objet seul, fond transparent, aucun texte. Sur une
# caisse, une assiette ou une main dans l'image ajoute du bruit sans rien
# apprendre à la personne qui sert.
# --------------------------------------------------------------------------

COMMUN="Objet unique, centré, entier et non coupé. Fond entièrement transparent. \
Aucun texte, aucun logo, aucune main, aucune assiette, aucun couvert, aucun emballage, \
aucune miette, aucun décor autour."

style_photo() {
	echo "Photographie culinaire professionnelle de $1. Lumière naturelle douce et \
rasante, légère profondeur de champ, couleurs chaudes et fidèles, texture de la croûte \
et du feuilletage nettement visibles, vue de trois quarts légèrement plongeante. $COMMUN"
}

style_plat() {
	echo "Illustration vectorielle plate de $1. Formes simples et généreuses, aplats de \
couleur sans dégradé ni ombre portée, palette chaude et restreinte (beige, ambre, brun \
doré, touches de brun foncé), contours doux, style pictogramme éditorial très lisible en \
petit. Vue de trois quarts. $COMMUN"
}

style_gouache() {
	echo "Illustration peinte à la gouache de $1. Touches de pinceau visibles, matière et \
grain de papier légers, couleurs chaudes et terreuses légèrement désaturées, contours \
irréguliers faits main, esprit carnet de recettes artisanal. Vue de trois quarts. $COMMUN"
}

STYLES="photo plat gouache"

# --------------------------------------------------------------------------
# Produits : slug|description du sujet
# --------------------------------------------------------------------------

PRODUITS=(
	"croissant|un croissant au beurre doré et feuilleté"
	"couque-au-chocolat|un pain au chocolat feuilleté avec ses deux barres de chocolat"
	"pain-aux-raisins|un pain aux raisins en spirale"
	"baguette|une baguette de pain française dorée et croustillante"
	"pain-gris-500g|une miche de pain gris rustique à la croûte farinée"
	"eclair-chocolat|un éclair au chocolat au glaçage brillant"
	"couque-au-beurre|une couque au beurre briochée et dorée"
	"chausson-aux-pommes|un chausson aux pommes doré"
	"cafe|une tasse de café expresso en porcelaine blanche"
)

# --------------------------------------------------------------------------

STYLE="plat"
DEST="img/products"
MODE="normal"
CIBLES=()

while [ $# -gt 0 ]; do
	case "$1" in
		--style)  STYLE="$2"; shift 2 ;;
		--essai)  MODE="essai"; shift ;;
		--dest)   DEST="$2"; shift 2 ;;
		--liste)
			echo "Styles   : $STYLES"
			echo "Produits : $(printf '%s ' "${PRODUITS[@]%%|*}")"
			exit 0 ;;
		-*) echo "Option inconnue : $1" >&2; exit 1 ;;
		*)  CIBLES+=("$1"); shift ;;
	esac
done

case " $STYLES " in
	*" $STYLE "*) ;;
	*) echo "Style inconnu : $STYLE (connus : $STYLES)" >&2; exit 1 ;;
esac

[ "$MODE" = "essai" ] && DEST="img/essais/$STYLE"
mkdir -p "$DEST"

# Filtrage sur les slugs demandés.
if [ ${#CIBLES[@]} -gt 0 ]; then
	SELECTION=()
	for entree in "${PRODUITS[@]}"; do
		slug="${entree%%|*}"
		for voulu in "${CIBLES[@]}"; do
			[ "$slug" = "$voulu" ] && SELECTION+=("$entree")
		done
	done
	[ ${#SELECTION[@]} -eq 0 ] && { echo "Aucun produit connu parmi : ${CIBLES[*]}" >&2; exit 1; }
	PRODUITS=("${SELECTION[@]}")
fi

echo "→ ${#PRODUITS[@]} image(s), style « $STYLE », modèle $MODELE, qualité $QUALITE → $DEST/"
echo

for entree in "${PRODUITS[@]}"; do
	slug="${entree%%|*}"
	sujet="${entree#*|}"
	sortie="$DEST/$slug.png"

	if [ -f "$sortie" ]; then
		echo "  = $slug (déjà là)"
		continue
	fi

	prompt=$("style_$STYLE" "$sujet")
	printf '  · %-22s ' "$slug"

	reponse=$(jq -n --arg p "$prompt" --arg m "$MODELE" --arg q "$QUALITE" --arg s "$TAILLE" \
		'{model:$m, prompt:$p, n:1, size:$s, quality:$q,
		  background:"transparent", output_format:"png"}' \
		| curl -sS https://api.openai.com/v1/images/generations \
			-H "Authorization: Bearer $OPENAI_API_KEY" \
			-H "Content-Type: application/json" \
			--data-binary @-)

	if ! b64=$(printf '%s' "$reponse" | jq -er '.data[0].b64_json' 2>/dev/null); then
		echo "échec"
		# Le message d'erreur de l'API, jamais la requête (qui porte la clé).
			printf '%s' "$reponse" | jq -r '.error.message // "réponse inattendue"' >&2 || echo "réponse illisible de l'API" >&2
		continue
	fi

	printf '%s' "$b64" | base64 --decode > "$sortie"

	# La caisse tourne sur un Celeron de 2013 : décoder du 1024×1024 pour
	# l'afficher dans une vignette serait du gaspillage pur.
	command -v sips >/dev/null && sips -Z 384 "$sortie" >/dev/null 2>&1 || true

	# Puis WebP, qui divise le poids par cinq à qualité équivalente en gardant
	# la transparence. Sur neuf produits, 1,4 Mo deviennent 260 Ko — autant de
	# lecture disque et de décodage en moins au démarrage de la caisse.
	if command -v cwebp >/dev/null; then
		if cwebp -quiet -q 82 -alpha_q 90 "$sortie" -o "${sortie%.png}.webp"; then
			rm -f "$sortie"
			sortie="${sortie%.png}.webp"
		fi
	fi

	echo "ok ($(du -h "$sortie" | awk '{print $1}'))"
done

echo
echo "Terminé."
