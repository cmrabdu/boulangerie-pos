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
#
# Deux garde-fous contre le cas où un même mot désigne deux choses :
#
#  - le « + » d'un supplément se traduit par « supplement- » (« + Fromage » →
#    « supplement-fromage »), si bien qu'une garniture ne pioche jamais le dessin
#    du sandwich du même nom ;
#  - un slug peut en plus être préfixé par sa catégorie (« pains-fleur ») : la
#    caisse cherche d'abord le nom préfixé, puis le nom nu.
#
# Sans ça, le supplément « Fromage » et le sandwich « Fromage » partagent un seul
# dessin, et l'un des deux est forcément faux : une tranche là où il fallait un
# sandwich, ou l'inverse.
PRODUITS=(
	# Pains
	"baguette|une baguette de pain française dorée et croustillante"
	"pain-carre-blanc|une miche de pain de mie blanc carrée et dorée"
	"simit-istanbul|un simit turc, anneau de pain couvert de graines de sésame"
	"pistolet|un petit pain rond belge fendu au milieu, doré"
	"mitraillette|un petit pain long et étroit, doré"
	"pain-turc|un pain turc plat et ovale, doré, saupoudré de sésame"
	"pain-de-campagne|une grande miche de pain de campagne à la croûte farinée"
	"piccolo|un tout petit pain rond doré"
	"fleur|un pain rond dont la croûte est fendue en pétales, en forme de fleur"
	"pitta|un pain pitta rond et plat"
	"pain-carre-cereales|une miche de pain de mie carrée aux céréales, couverte de graines"
	"mitraillettes-5|cinq petits pains longs et étroits alignés"
	"pain-carre-gris|une miche de pain de mie gris carrée"
	"tresse|un pain brioché tressé, doré"
	"pistolets-5|cinq petits pains ronds belges groupés"
	"petit-carre-blanc|un petit pain de mie blanc carré"
	"pittas-5|cinq pains pitta ronds empilés"
	"baguette-grise|une baguette de pain gris"
	"petit-carre-cereales|un petit pain de mie carré aux céréales"
	"simit-bagel|un simit turc en forme de bagel, couvert de sésame"
	"petit-carre-gris|un petit pain de mie gris carré"
	"pistolet-gris|un petit pain rond gris fendu au milieu"
	"pain-ramadan|un pain plat rond turc de ramadan, quadrillé et doré, aux graines de sésame et de nigelle"

	# Viennoiseries
	"croissant|un croissant au beurre doré et feuilleté"
	"pain-au-chocolat|un pain au chocolat feuilleté avec ses deux barres de chocolat"
	"croissant-nutella|un croissant fourré à la pâte de noisettes, coulée de chocolat visible"
	"croissant-aux-amandes|un croissant aux amandes couvert d'amandes effilées et de sucre glace"
	"donut|un donut glacé au sucre rose avec des vermicelles"
	"pain-chocolat-creme|une viennoiserie feuilletée rectangulaire à la crème pâtissière et aux pépites de chocolat"
	"muffin-milka|un muffin au chocolat dans sa caissette en papier"
	"donut-chocolat|un donut glacé au chocolat"
	"croissant-a-la-creme|un croissant fourré à la crème pâtissière"
	"beignet-nutella|un petit beignet rond fourré à la pâte de noisettes, saupoudré de sucre"

	# Boissons chaudes
	"cafe|une tasse de café expresso en porcelaine blanche"
	"the|une tasse de thé clair avec son sachet"
	"cafe-au-lait|une tasse de café au lait"
	"chocolat-chaud|une tasse de chocolat chaud avec de la crème fouettée"
	"cappuccino|un cappuccino en tasse avec sa mousse de lait"
	"deca|une tasse de café décaféiné en porcelaine blanche"

	# Boissons froides
	"fanta|une canette de soda à l'orange de 33 cl"
	"eau|une bouteille d'eau plate de 50 cl en plastique transparent"
	"aquarius|une bouteille de boisson isotonique claire"
	"coca-light|une canette de cola light argentée de 33 cl"
	"coca-cola|une canette de soda au cola rouge de 33 cl"
	"tropico|une bouteille de boisson aux fruits tropicaux orangée"
	"eau-petillante|une bouteille d'eau pétillante de 50 cl aux bulles visibles"
	"ice-tea|une canette de thé glacé jaune de 33 cl"
	"coca-bouteille|une bouteille de soda au cola de 50 cl"
	"fanta-bouteille|une bouteille de soda à l'orange de 50 cl"
	"ayran|un gobelet de boisson lactée turque au yaourt"
	"fuze-tea|une bouteille de thé glacé"
	"capri-sun|une pochette souple de jus de fruits avec sa paille"
	"ice-tea-peche|une canette de thé glacé à la pêche"
	"fanta-light|une canette de soda à l'orange light"

	# Pâtisseries
	"eclair|un éclair au chocolat au glaçage brillant"
	"merveilleux|un merveilleux belge, meringue et crème fouettée couverte de copeaux de chocolat"
	"baklava|deux baklavas en losange, pâte filo dorée et pistaches concassées"
	"tiramisu-speculoos|une part de tiramisu au spéculoos dans une coupelle"
	"tiramisu-chocolat|une part de tiramisu au chocolat saupoudrée de cacao"
	"parfait|un parfait glacé dans une coupe"
	"tarte-au-riz|une tarte au riz belge entière, crème dorée"
	"tarte-aux-fraises|une tarte aux fraises entière, fraises rangées et brillantes"
	"tarte-aux-pommes|une tarte aux pommes entière, lamelles apparentes"
	"tarte-au-sucre|une tarte au sucre belge entière, dorée et caramélisée"

	# Sandwichs
	"americain|un sandwich à l'américain, préparation de viande hachée, dans un petit pain"
	"thon-mayo|un sandwich au thon mayonnaise dans un petit pain"
	"poulet-mayo|un sandwich au poulet mayonnaise dans un petit pain"
	"thon-piquant|un sandwich au thon sauce piquante rouge dans un petit pain"
	"poulet-curry|un sandwich au poulet curry dans un petit pain"
	"thon-cocktail|un sandwich au thon sauce cocktail rosée dans un petit pain"
	"poulet-andalouse|un sandwich au poulet sauce andalouse dans un petit pain"
	"jambon-fromage|un sandwich jambon-fromage dans un petit pain, garniture visible"
	"poulet-piquant|un sandwich au poulet sauce piquante dans un petit pain"
	"thon-portugais|un sandwich au thon et aux poivrons grillés dans un petit pain"
	"poulet-brazil|un sandwich au poulet sauce brésilienne dans un petit pain"
	"fromage|un sandwich au fromage dans un petit pain, garniture visible"

	# Suppléments — la garniture seule, jamais le sandwich qui la contient.
	"supplement-salade|quelques feuilles de salade verte fraîches"
	"supplement-tomate|deux rondelles de tomate fraîche"
	"supplement-oeuf|deux rondelles d'œuf dur"
	"supplement-oignon|quelques rondelles d'oignon cru"
	"supplement-mayonnaise|une cuillerée de mayonnaise"
	"supplement-carotte|une petite portion de carottes râpées"
	"supplement-cornichon|deux cornichons entiers"
	"supplement-concombre|trois rondelles de concombre"
	"supplement-mais|une petite portion de grains de maïs doux"
	"supplement-jambon|une tranche de jambon roulée, seule"
	"supplement-fromage|deux tranches de fromage empilées, seules"

	# Salés
	"roule-a-la-viande|un roulé de pâte feuilletée à la viande hachée, doré"
	"pide-feta|une pide turque ovale garnie de fromage blanc fondu"
	"pide-viande|une pide turque ovale garnie de viande hachée"
	"pizza|une part de pizza à la tomate et au fromage"
	"borek-epinards|un börek turc roulé aux épinards, pâte filo dorée"
	"borek-feta|un börek turc roulé à la feta, pâte filo dorée"
	"borek-pomme-de-terre|un börek turc roulé à la pomme de terre, pâte filo dorée"
	"panini-poulet-pane|un panini grillé au poulet pané, marques de gril visibles"
	"brioche-feta|un petit pain brioché turc fourré à la feta, doré"
	"pizza-viande|une part de pizza à la viande hachée"
	"pizza-poivrons|une part de pizza aux poivrons"
	"brioche-viande|un petit pain brioché turc fourré à la viande, doré"
	"panini-tomate-mozzarella|un panini grillé à la tomate et à la mozzarella"

	# Divers
	"sac|un petit sac en papier kraft de boulangerie"
	"bougies|un paquet de bougies d'anniversaire colorées"
)

# --------------------------------------------------------------------------

# La gouache est la direction arrêtée le 29/07 pour les produits (voir CLAUDE.md,
# qui promet justement « generer-images.sh sans argument »). Le défaut était resté
# sur « plat », le style de la phase de comparaison : lancé tel quel sur le vrai
# catalogue, il aurait produit quatre-vingt-huit images dans le mauvais style.
STYLE="gouache"
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

	# Réduction à 384 px puis WebP, en un seul passage de cwebp.
	#
	# La caisse tourne sur un Celeron de 2013 : décoder du 1024×1024 pour
	# l'afficher dans une tuile de 221×123 px serait du gaspillage pur. La
	# réduction passait autrefois par `sips`, qui n'existe que sur macOS — sur
	# Linux la ligne était silencieusement sautée et les images restaient à
	# 1024 px, soit 250 Ko pièce au lieu de 30. `cwebp -resize` fait le même
	# travail partout, et en une seule compression plutôt que deux.
	#
	# Le 0 en hauteur dit à cwebp de la calculer en gardant les proportions.
	if command -v cwebp >/dev/null; then
		if cwebp -quiet -q 82 -alpha_q 90 -resize 384 0 "$sortie" -o "${sortie%.png}.webp"; then
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
