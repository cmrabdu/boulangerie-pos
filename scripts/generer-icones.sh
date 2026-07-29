#!/usr/bin/env bash
#
# Génère les icônes de catégories.
#
#   ./scripts/generer-icones.sh                 # vers img/icons/, style « trait »
#   ./scripts/generer-icones.sh --style plein
#   ./scripts/generer-icones.sh --dest img/essais/icones-test
#   ./scripts/generer-icones.sh pain croissant  # seulement celles-là
#
# Les icônes de PAIEMENT ne sont pas ici : elles sont dessinées à la main dans
# web/index.html, parce qu'elles doivent virer au blanc sur un fond saturé.
#
# Après génération, chaque icône est RECADRÉE sur son dessin puis recentrée
# dans un carré. Sans cette étape, le modèle laisse une marge transparente
# arbitraire — mesurée à un tiers de la hauteur sur le premier lot — et les
# icônes paraissent petites et de tailles inégales alors que leurs boîtes CSS
# font toutes la même taille.

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
	exit 1
fi

command -v jq >/dev/null || { echo "jq est requis : brew install jq" >&2; exit 1; }
command -v uv >/dev/null || { echo "uv est requis pour le recadrage : brew install uv" >&2; exit 1; }

MODELE="${MODELE:-gpt-image-1.5}"
QUALITE="${QUALITE:-low}"

STYLE="trait"
DEST="img/icons"
CIBLES=()

while [ $# -gt 0 ]; do
	case "$1" in
		--style) STYLE="$2"; shift 2 ;;
		--dest)  DEST="$2";  shift 2 ;;
		-*) echo "Option inconnue : $1" >&2; exit 1 ;;
		*)  CIBLES+=("$1"); shift ;;
	esac
done

mkdir -p "$DEST"

# --------------------------------------------------------------------------
# Consignes
#
# Une icône de caisse est vue à un mètre, du coin de l'œil, pendant qu'on rend
# la monnaie. Tout ce qui demande à être déchiffré est du poids mort. D'où
# l'insistance, répétée trois fois, sur l'épaisseur du trait et le nombre de
# formes : le modèle a une tendance naturelle à ajouter du détail décoratif.
# --------------------------------------------------------------------------

COMMUN="Le dessin remplit tout le cadre, en le touchant presque, avec une marge minimale. \
Sujet unique et centré. Fond entièrement transparent. Aucun texte, aucun cadre, aucun cercle \
autour, aucune ombre, aucun dégradé, aucun reflet, aucun détail décoratif."

prompt_trait() {
	echo "Icône d'interface extrêmement simplifiée représentant $1. \
TRAIT TRÈS ÉPAIS ET UNIFORME, comme tracé au marqueur large : l'épaisseur du trait doit valoir \
environ un dixième de la largeur de l'image. Extrémités arrondies. TROIS FORMES MAXIMUM, \
aucun détail intérieur, aucune texture, aucune hachure. Contour seul, sans remplissage. \
Une seule couleur brun très foncé. Lisibilité absolue à 24 pixels. $COMMUN"
}

prompt_plein() {
	echo "Icône d'interface extrêmement simplifiée représentant $1. \
SILHOUETTE PLEINE ET COMPACTE, formes larges et arrondies, aucun trait fin nulle part. \
TROIS FORMES MAXIMUM, aucun détail intérieur. Une seule couleur brun très foncé, aplat uni. \
Lisibilité absolue à 24 pixels. $COMMUN"
}

ICONES=(
	"pain|une miche de pain ronde vue de face"
	# Un croissant réduit à sa seule silhouette arquée se lit « lune ». Les deux
	# séparations sont le minimum qui le rende reconnaissable comme viennoiserie.
	"croissant|un croissant de boulangerie vu de face, forme arquée épaisse aux pointes effilées, avec deux séparations franches marquant les segments"
	"patisserie|un cupcake, réduit à une caissette trapézoïdale surmontée d'un dôme"
	"sandwich|un sandwich triangulaire vu de face, deux tranches de pain et une garniture"
	"boisson|un gobelet de boisson à emporter, vu de face, avec son couvercle"
	"divers|un sac en papier vu de face, avec ses deux anses"
)

if [ ${#CIBLES[@]} -gt 0 ]; then
	SELECTION=()
	for e in "${ICONES[@]}"; do
		for v in "${CIBLES[@]}"; do [ "${e%%|*}" = "$v" ] && SELECTION+=("$e"); done
	done
	[ ${#SELECTION[@]} -eq 0 ] && { echo "Aucune icône connue parmi : ${CIBLES[*]}" >&2; exit 1; }
	ICONES=("${SELECTION[@]}")
fi

appeler_api() {
	jq -n --arg p "$1" --arg m "$MODELE" --arg q "$QUALITE" \
		'{model:$m, prompt:$p, n:1, size:"1024x1024", quality:$q,
		  background:"transparent", output_format:"png"}' \
		| curl -sS --http1.1 --max-time 300 \
			https://api.openai.com/v1/images/generations \
			-H "Authorization: Bearer $OPENAI_API_KEY" \
			-H "Content-Type: application/json" \
			--data-binary @- || true
}

echo "→ ${#ICONES[@]} icône(s), style « $STYLE », modèle $MODELE → $DEST/"
echo

ECHECS=()

for entree in "${ICONES[@]}"; do
	cle="${entree%%|*}"
	sujet="${entree#*|}"
	brut="$DEST/$cle.png"

	if [ -f "$brut" ] || [ -f "$DEST/$cle.webp" ]; then
		echo "  = $cle (déjà là)"
		continue
	fi

	prompt=$("prompt_$STYLE" "$sujet")
	printf '  · %-12s ' "$cle"

	b64=""
	for tentative in 1 2 3; do
		reponse=$(appeler_api "$prompt")
		if b64=$(printf '%s' "$reponse" | jq -er '.data[0].b64_json' 2>/dev/null); then break; fi
		b64=""
		[ "$tentative" -lt 3 ] && { printf '↻'; sleep 3; }
	done

	if [ -z "$b64" ]; then
		echo " échec"
		printf '%s' "$reponse" | jq -r '.error.message // empty' 2>/dev/null >&2 || true
		ECHECS+=("$cle")
		continue
	fi

	printf '%s' "$b64" | base64 --decode > "$brut"
	echo "ok"
done

# --------------------------------------------------------------------------
# Recadrage : chaque icône est ramenée à la même emprise visuelle.
# --------------------------------------------------------------------------

echo
echo "Recadrage et normalisation…"

uv run --quiet --with pillow python scripts/normaliser-icones.py "$DEST"

# WebP : quelques kilo-octets par icône, transparence conservée.
if command -v cwebp >/dev/null; then
	for f in "$DEST"/*.png; do
		[ -e "$f" ] || continue
		cwebp -quiet -q 90 -alpha_q 100 "$f" -o "${f%.png}.webp" && rm -f "$f"
	done
fi

echo
if [ ${#ECHECS[@]} -gt 0 ]; then
	echo "Terminé, avec ${#ECHECS[@]} échec(s) : ${ECHECS[*]}"
else
	echo "Terminé."
fi
