#!/usr/bin/env bash
#
# Génère les icônes de catégories et de paiement.
#
#   ./scripts/generer-icones.sh                  # style « trait »
#   ./scripts/generer-icones.sh --style plein
#
# Sortie : img/essais/icones-<style>/<cle>.png
#
# Réserve : une icône matricielle affichée à 24 px perd forcément en netteté
# face à un tracé vectoriel, et deux images générées séparément n'ont aucune
# raison d'avoir la même graisse de trait ni le même équilibre. Ce script sert
# à en juger sur pièce, pas à présumer du résultat.

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

MODELE="${MODELE:-gpt-image-1.5}"
QUALITE="${QUALITE:-low}"

STYLE="trait"
[ "${1:-}" = "--style" ] && { STYLE="$2"; shift 2; }

DEST="img/essais/icones-$STYLE"
mkdir -p "$DEST"

COMMUN="Pictogramme d'interface, sujet unique parfaitement centré, cadrage carré avec \
marge égale sur les quatre côtés, fond entièrement transparent. Aucun texte, aucun cadre, \
aucun cercle autour, aucune ombre portée, aucun dégradé, aucun reflet."

prompt_trait() {
	echo "Icône au trait de $1. Contour uniquement, trait d'épaisseur constante et \
généreuse, extrémités arrondies, aucune surface remplie, une seule couleur brun foncé sur \
fond transparent, géométrie simplifiée à l'essentiel, style pictogramme d'application \
moderne lisible à 24 pixels. $COMMUN"
}

prompt_plein() {
	echo "Icône en aplat de $1. Silhouette pleine simplifiée, deux ou trois couleurs \
chaudes maximum (ambre, brun doré, brun foncé), aucun contour noir, formes arrondies et \
généreuses, style pictogramme d'application moderne lisible à 24 pixels. $COMMUN"
}

ICONES=(
	"pain|une miche de pain et une baguette"
	"croissant|un croissant vu de face, réduit à une forme de croissant de lune aux pointes effilées"
	"patisserie|un cupcake vu de face, réduit à une caissette cannelée surmontée d'un dôme de crème"
	"sandwich|un sandwich garni coupé en deux"
	"boisson|un gobelet de boisson chaude à emporter"
	"divers|un sac en papier de boulangerie"
	"cash|des billets de banque et des pièces de monnaie"
	"carte|une carte bancaire glissée dans un terminal de paiement"
)

echo "→ ${#ICONES[@]} icône(s), style « $STYLE », modèle $MODELE → $DEST/"
echo

for entree in "${ICONES[@]}"; do
	cle="${entree%%|*}"
	sujet="${entree#*|}"
	sortie="$DEST/$cle.png"

	[ -f "$sortie" ] && { echo "  = $cle (déjà là)"; continue; }

	prompt=$("prompt_$STYLE" "$sujet")
	printf '  · %-12s ' "$cle"

	reponse=$(jq -n --arg p "$prompt" --arg m "$MODELE" --arg q "$QUALITE" \
		'{model:$m, prompt:$p, n:1, size:"1024x1024", quality:$q,
		  background:"transparent", output_format:"png"}' \
		| curl -sS https://api.openai.com/v1/images/generations \
			-H "Authorization: Bearer $OPENAI_API_KEY" \
			-H "Content-Type: application/json" \
			--data-binary @-)

	if ! b64=$(printf '%s' "$reponse" | jq -er '.data[0].b64_json' 2>/dev/null); then
		echo "échec"
			printf '%s' "$reponse" | jq -r '.error.message // "réponse inattendue"' >&2 || echo "réponse illisible de l'API" >&2
		continue
	fi

	printf '%s' "$b64" | base64 --decode > "$sortie"
	command -v sips >/dev/null && sips -Z 128 "$sortie" >/dev/null 2>&1 || true
	echo "ok ($(du -h "$sortie" | awk '{print $1}'))"
done

echo
echo "Terminé."
