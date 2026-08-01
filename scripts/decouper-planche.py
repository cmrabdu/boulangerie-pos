"""Découpe une planche d'icônes en fichiers séparés.

    uv run --with pillow python scripts/decouper-planche.py planche.png dest/ 3 2 pain croissant …

Générer les six icônes d'un jeu en une seule image plutôt qu'une par une est ce
qui règle le défaut de fond des icônes générées : demandées séparément, elles
n'ont aucune raison de partager la même graisse de trait ni le même niveau de
détail, et le jeu paraît dépareillé. Sur une planche unique, le modèle tient un
style d'une case à l'autre.

Le découpage est géométrique (grille régulière), puis chaque case est recadrée
sur son dessin — le modèle ne centre jamais parfaitement dans sa case.

Les dessins débordent parfois de leur case : la coupe emporte alors une lamelle
du voisin, et l'icône se retrouve avec un bout de baguette collé au bord. Ces
résidus sont retirés avant le recadrage, sinon ils dictent la boîte de recadrage
et décentrent tout le dessin.
"""

import pathlib
import sys
from collections import deque

from PIL import Image

SEUIL_ALPHA = 24  # en deçà, le pixel est du vide

# Un résidu de voisin est petit ET plaqué contre un bord. Les deux conditions
# comptent : la vapeur au-dessus d'une tasse est petite elle aussi, mais elle
# flotte au milieu de la case, alors qu'une lamelle de voisin longe son bord.
PART_RESIDU = 0.05
BANDE_BORD = 0.15


def composantes(masque, largeur, hauteur):
    """Groupes de pixels opaques connexes (8-connexité)."""
    vus = bytearray(largeur * hauteur)
    for depart in range(largeur * hauteur):
        if masque[depart] and not vus[depart]:
            groupe, file = [], deque([depart])
            vus[depart] = 1
            while file:
                p = file.popleft()
                groupe.append(p)
                x, y = p % largeur, p // largeur
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        vx, vy = x + dx, y + dy
                        if 0 <= vx < largeur and 0 <= vy < hauteur:
                            v = vy * largeur + vx
                            if masque[v] and not vus[v]:
                                vus[v] = 1
                                file.append(v)
            yield groupe


def sans_residus(im):
    """Efface les lamelles de la case voisine emportées par la coupe."""
    largeur, hauteur = im.size
    alpha = im.getchannel("A")
    # tobytes() plutôt que getdata() : un octet par pixel en mode « L », et pas
    # d'API dépréciée.
    masque = bytearray(1 if v > SEUIL_ALPHA else 0 for v in alpha.tobytes())

    groupes = list(composantes(masque, largeur, hauteur))
    if len(groupes) < 2:
        return im, 0
    total = sum(len(g) for g in groupes)
    principal = max(groupes, key=len)

    a_effacer = []
    for groupe in groupes:
        if groupe is principal or len(groupe) >= PART_RESIDU * total:
            continue
        xs = [p % largeur for p in groupe]
        ys = [p // largeur for p in groupe]
        colle_au_bord = (
            (min(xs) == 0 and max(xs) < BANDE_BORD * largeur)
            or (max(xs) == largeur - 1 and min(xs) > (1 - BANDE_BORD) * largeur)
            or (min(ys) == 0 and max(ys) < BANDE_BORD * hauteur)
            or (max(ys) == hauteur - 1 and min(ys) > (1 - BANDE_BORD) * hauteur)
        )
        if colle_au_bord:
            a_effacer.append(groupe)

    if not a_effacer:
        return im, 0
    propre = im.copy()
    vide = (0, 0, 0, 0)
    for groupe in a_effacer:
        for p in groupe:
            propre.putpixel((p % largeur, p // largeur), vide)
    return propre, len(a_effacer)


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

        case, retires = sans_residus(case)

        boite = cadre_visible(case)
        if boite is None:
            print(f"  ! {nom:<12} case vide, ignorée")
            continue

        dessin = case.crop(boite)
        chemin = dest / f"{nom}.png"
        dessin.save(chemin)
        note = f"  ({retires} résidu(s) du voisin retiré(s))" if retires else ""
        print(f"  · {nom:<12} {dessin.size[0]}×{dessin.size[1]}{note}")


if __name__ == "__main__":
    main()
