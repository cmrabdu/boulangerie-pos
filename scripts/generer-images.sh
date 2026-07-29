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

# Les slugs doivent correspondre à ceux que calcule internal/db.Slugify à partir
# du nom du produit, sans quoi la caisse ne trouvera pas l'image.
PRODUITS=(
	# Pains
	"baguette|une baguette de pain française dorée et croustillante"
	"baguette-tradition|une baguette de tradition française à la croûte très craquelée"
	"pistolet|un petit pain rond belge fendu au milieu, doré"
	"sandwich|un petit pain long et moelleux à sandwich"
	"pain-gris-500g|une miche de pain gris rustique à la croûte farinée"
	"pain-blanc-500g|un pain de mie blanc en miche rectangulaire dorée"
	"pain-complet|un pain complet rond à la croûte foncée"
	"pain-multicereales|un pain aux céréales couvert de graines"
	"pain-aux-noix|un pain rustique aux noix"
	"ciabatta|une ciabatta italienne allongée et farinée"
	"pain-d-epeautre|un pain d'épeautre rond et rustique"
	"demi-gris|une demi-miche de pain gris"

	# Viennoiseries
	"croissant|un croissant au beurre doré et feuilleté"
	"couque-au-beurre|une couque au beurre briochée en escargot, dorée"
	"couque-au-chocolat|un pain au chocolat feuilleté avec ses deux barres de chocolat"
	"couque-suisse|une couque suisse à la crème pâtissière et aux pépites de chocolat"
	"pain-aux-raisins|un pain aux raisins en spirale"
	"chausson-aux-pommes|un chausson aux pommes doré"
	"croissant-amandes|un croissant aux amandes couvert d'amandes effilées et de sucre glace"
	"donut|un donut glacé au sucre rose avec des vermicelles"
	"cramique|un cramique belge, brioche aux raisins secs, tranché"
	"craquelin|un craquelin belge, brioche au sucre perlé"

	# Pâtisseries
	"eclair-chocolat|un éclair au chocolat au glaçage brillant"
	"eclair-vanille|un éclair à la vanille au glaçage blanc nacré"
	"merveilleux|un merveilleux belge, meringue et crème fouettée couverte de copeaux de chocolat"
	"tarte-au-riz-part|une part de tarte au riz belge, crème dorée"
	"tarte-aux-pommes-part|une part de tarte aux pommes aux lamelles apparentes"
	"tarte-au-sucre-part|une part de tarte au sucre dorée et caramélisée"
	"millefeuille|un millefeuille à la crème pâtissière et au glaçage marbré"
	"tiramisu|une part de tiramisu saupoudrée de cacao"
	"moelleux-chocolat|un moelleux au chocolat au cœur fondant"
	"gateau-6-pers|un gâteau rond entier décoré à la crème, pour six personnes"
	"gateau-8-pers|un grand gâteau rond entier décoré à la crème et aux fruits"

	# Sandwichs
	"fromage|un sandwich au fromage dans un petit pain, garniture visible"
	"jambon|un sandwich au jambon dans un petit pain, garniture visible"
	"jambon-fromage|un sandwich jambon-fromage dans un petit pain, garniture visible"
	"thon|un sandwich au thon et crudités dans un petit pain"
	"poulet-curry|un sandwich au poulet curry dans un petit pain"
	"americain|un sandwich à l'américain, préparation de viande hachée, dans un petit pain"
	"crabe|un sandwich au surimi et crudités dans un petit pain"
	"club-sandwich|un club sandwich en triangles superposés avec pics"
	"panini|un panini grillé aux marques de gril bien visibles"

	# Boissons
	"eau-50cl|une bouteille d'eau plate de 50 cl en plastique transparent"
	"eau-petillante-50cl|une bouteille d'eau pétillante de 50 cl aux bulles visibles"
	"coca-33cl|une canette de soda au cola rouge de 33 cl"
	"ice-tea-33cl|une canette de thé glacé jaune de 33 cl"
	"jus-d-orange|un verre de jus d'orange frais"
	"cafe|une tasse de café expresso en porcelaine blanche"
	"cappuccino|un cappuccino en tasse avec sa mousse de lait"
	"chocolat-chaud|une tasse de chocolat chaud avec de la crème fouettée"
	"the|une tasse de thé clair avec son sachet"

	# Divers
	"sac|un petit sac en papier kraft de boulangerie"
	"grand-sac|un grand sac en papier kraft de boulangerie avec anses"
	"bougies|un paquet de bougies d'anniversaire colorées"
	"oeufs-6|une boîte de six œufs frais, ouverte"
	"chocolats-250g|un ballotin de pralines belges assorties"
	"confiture|un pot de confiture de fraises avec son couvercle en tissu"
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

# appeler_api affiche la réponse brute sur stdout, ou rien en cas d'échec
# réseau. Jamais la requête, qui porte la clé.
#
# --http1.1 : l'API ferme parfois un flux HTTP/2 en cours de route sur ces
# requêtes longues, ce que curl signale par le code 92. HTTP/1.1 n'a pas ce
# mode de défaillance.
appeler_api() {
	jq -n --arg p "$1" --arg m "$MODELE" --arg q "$QUALITE" --arg s "$TAILLE" \
		'{model:$m, prompt:$p, n:1, size:$s, quality:$q,
		  background:"transparent", output_format:"png"}' \
		| curl -sS --http1.1 --max-time 300 \
			https://api.openai.com/v1/images/generations \
			-H "Authorization: Bearer $OPENAI_API_KEY" \
			-H "Content-Type: application/json" \
			--data-binary @- || true
}

ECHECS=()

for entree in "${PRODUITS[@]}"; do
	slug="${entree%%|*}"
	sujet="${entree#*|}"
	sortie="$DEST/$slug.png"

	# On teste les deux extensions : le fichier finit converti en .webp, et sans
	# ce test le script régénérerait — et refacturerait — tout ce qui existe.
	if [ -f "$sortie" ] || [ -f "$DEST/$slug.webp" ]; then
		echo "  = $slug (déjà là)"
		continue
	fi

	prompt=$("style_$STYLE" "$sujet")
	printf '  · %-22s ' "$slug"

	# La plupart des échecs sont passagers : on réessaie avant d'abandonner.
	b64=""
	for tentative in 1 2 3; do
		reponse=$(appeler_api "$prompt")
		if b64=$(printf '%s' "$reponse" | jq -er '.data[0].b64_json' 2>/dev/null); then
			break
		fi
		b64=""
		[ "$tentative" -lt 3 ] && { printf '↻'; sleep 3; }
	done

	if [ -z "$b64" ]; then
		echo " échec"
		printf '%s' "$reponse" | jq -r '.error.message // empty' 2>/dev/null >&2 || true
		ECHECS+=("$slug")
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
if [ ${#ECHECS[@]} -gt 0 ]; then
	echo "Terminé, avec ${#ECHECS[@]} échec(s) : ${ECHECS[*]}"
	echo "Relancer la commande les reprendra : ce qui existe déjà est ignoré."
else
	echo "Terminé."
fi
