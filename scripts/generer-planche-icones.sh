#!/usr/bin/env bash
#
# Génère un jeu d'icônes de catégories en UNE seule image, puis le découpe.
#
#   ./scripts/generer-planche-icones.sh gras
#   ./scripts/generer-planche-icones.sh plein duo gras     # plusieurs styles
#
# Pourquoi une planche plutôt que six appels : demandées une par une, les icônes
# n'ont aucune raison de partager la même graisse de trait, le même niveau de
# détail ni le même équilibre — et le jeu paraît dépareillé, ce qui est
# exactement le reproche qu'on leur faisait. Sur une planche unique, le modèle
# tient un style d'une case à l'autre. C'est aussi six fois moins cher.

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
QUALITE="${QUALITE:-medium}"   # une planche porte six dessins : la qualité basse les rend mous

# Ordre de lecture, 3 colonnes × 2 lignes.
NOMS=(pain croissant patisserie sandwich boisson divers)

SUJETS="Case 1 : une miche de pain ronde avec une baguette posée en travers. \
Case 2 : un croissant. \
Case 3 : une part de gâteau triangulaire vue de côté. \
Case 4 : un sandwich triangulaire vu de côté. \
Case 5 : un gobelet de boisson à emporter avec son couvercle. \
Case 6 : un sac en papier de boulangerie avec ses deux anses."

CADRE="Planche de six icônes disposées en grille régulière de 3 colonnes et 2 lignes, \
espacement identique entre toutes les cases, chaque icône centrée dans sa case et occupant \
la majeure partie de sa case. Fond entièrement transparent. Style rigoureusement identique \
pour les six icônes : même graisse, même niveau de simplification, même famille de formes. \
Aucun texte, aucun chiffre, aucun cadre, aucune bordure, aucune ombre portée, aucun fond coloré."

style_gras() {
	echo "Icônes d'interface au trait très épais. Épaisseur de trait constante et \
volontairement grasse sur toute la planche, extrémités et angles arrondis, aucune surface \
remplie, une seule couleur brun très foncé presque noir. Géométrie radicalement simplifiée : \
deux ou trois formes par icône, pas un détail de plus. Lisible à vingt-cinq pixels. $CADRE $SUJETS"
}

style_plein() {
	echo "Icônes d'interface en silhouette pleine. Formes compactes et arrondies remplies \
d'une seule couleur brun très foncé presque noir, sans aucun contour, sans dégradé. Les \
détails intérieurs sont obtenus par de larges découpes en négatif, jamais par des traits \
fins. Silhouettes franches et massives, lisibles à vingt-cinq pixels. $CADRE $SUJETS"
}

style_duo() {
	echo "Icônes d'interface bicolores. Trait extérieur épais brun très foncé, et une seule \
zone remplie par icône en aplat ambre chaud, sans dégradé. Exactement deux valeurs par icône, \
formes larges et arrondies, géométrie très simplifiée. Style pictogramme d'application \
moderne, lisible à vingt-cinq pixels. $CADRE $SUJETS"
}

for STYLE in "$@"; do
	case "$STYLE" in
		gras|plein|duo) ;;
		*) echo "Style inconnu : $STYLE (connus : gras plein duo)" >&2; exit 1 ;;
	esac

	planche="img/essais/planche-$STYLE.png"
	dest="img/essais/icones-$STYLE"
	mkdir -p img/essais

	if [ ! -f "$planche" ]; then
		echo "→ planche « $STYLE » ($MODELE, qualité $QUALITE)…"
		reponse=$(jq -n --arg p "$("style_$STYLE")" --arg m "$MODELE" --arg q "$QUALITE" \
			'{model:$m, prompt:$p, n:1, size:"1536x1024", quality:$q,
			  background:"transparent", output_format:"png"}' \
			| curl -sS https://api.openai.com/v1/images/generations \
				-H "Authorization: Bearer $OPENAI_API_KEY" \
				-H "Content-Type: application/json" \
				--data-binary @-)

		if ! b64=$(printf '%s' "$reponse" | jq -er '.data[0].b64_json' 2>/dev/null); then
			echo "  échec" >&2
			printf '%s' "$reponse" | jq -r '.error.message // "réponse inattendue"' >&2 \
				|| echo "réponse illisible de l'API" >&2
			continue
		fi
		printf '%s' "$b64" | base64 --decode > "$planche"
	else
		echo "→ planche « $STYLE » déjà présente"
	fi

	rm -rf "$dest"
	uv run --quiet --with pillow python scripts/decouper-planche.py \
		"$planche" "$dest" 3 2 "${NOMS[@]}"
	uv run --quiet --with pillow python scripts/normaliser-icones.py "$dest"

	for f in "$dest"/*.png; do
		cwebp -quiet -q 90 -alpha_q 100 "$f" -o "${f%.png}.webp" && rm -f "$f"
	done
	echo
done

echo "Terminé."
