"""Découpe une planche d'icônes en fichiers séparés.

    uv run --with pillow python scripts/decouper-planche.py planche.png dest/ 3 2 pain croissant …

Générer les six icônes d'un jeu en une seule image plutôt qu'une par une est ce
qui règle le défaut de fond des icônes générées : demandées séparément, elles
n'ont aucune raison de partager la même graisse de trait ni le même niveau de
détail, et le jeu paraît dépareillé. Sur une planche unique, le modèle tient un
style d'une case à l'autre.

Le découpage est géométrique (grille régulière), puis chaque case est recadrée
sur son dessin — le modèle ne centre jamais parfaitement dans sa case.
"""

import pathlib
import sys

from PIL import Image

SEUIL_ALPHA = 24  # en deçà, le pixel est du vide


def cadre_visible(im):
    """Boîte du dessin réellement visible, halo presque transparent exclu."""
    alpha = im.getchannel("A").point(lambda v: 255 if v > SEUIL_ALPHA else 0)
    return alpha.getbbox()


def main():
    if len(sys.argv) < 6:
        sys.exit(__doc__)

    source = pathlib.Path(sys.argv[1])
    dest = pathlib.Path(sys.argv[2])
    colonnes = int(sys.argv[3])
    lignes = int(sys.argv[4])
    noms = sys.argv[5:]

    if len(noms) != colonnes * lignes:
        sys.exit(f"{len(noms)} noms pour {colonnes}×{lignes} cases")

    dest.mkdir(parents=True, exist_ok=True)
    planche = Image.open(source).convert("RGBA")
    largeur, hauteur = planche.size
    pas_x, pas_y = largeur // colonnes, hauteur // lignes

    for index, nom in enumerate(noms):
        cx, cy = index % colonnes, index // colonnes
        case = planche.crop((cx * pas_x, cy * pas_y, (cx + 1) * pas_x, (cy + 1) * pas_y))

        boite = cadre_visible(case)
        if boite is None:
            print(f"  ! {nom:<12} case vide, ignorée")
            continue

        dessin = case.crop(boite)
        chemin = dest / f"{nom}.png"
        dessin.save(chemin)
        print(f"  · {nom:<12} {dessin.size[0]}×{dessin.size[1]}")


if __name__ == "__main__":
    main()
