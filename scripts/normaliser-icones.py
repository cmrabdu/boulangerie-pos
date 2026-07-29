"""Ramène un jeu d'icônes à une emprise visuelle homogène.

    uv run --with pillow python scripts/normaliser-icones.py img/icons

Deux corrections, qui répondent à deux défauts distincts du rendu brut :

1. Le recadrage se fait sur un seuil d'opacité, pas sur `getbbox()`. Les images
   générées portent un halo de pixels presque transparents ; `getbbox()` les
   compte, si bien que la boîte trouvée déborde le dessin réellement visible et
   que le centrage part de travers.

2. La mise à l'échelle vise une AIRE constante, non le plus grand côté. Une
   miche large et plate et un gobelet haut et étroit ont beau tenir tous deux
   dans le même carré, celui qui n'en remplit qu'une bande paraît deux fois
   plus petit. Égaliser l'aire égalise ce que l'œil perçoit.
"""

import pathlib
import sys

from PIL import Image

COTE = 256          # côté de la toile finale, en pixels
SEUIL_ALPHA = 24    # en deçà, le pixel est considéré comme du vide
AIRE_CIBLE = 0.62   # part de la toile que doit occuper l'aire du dessin
BORD_MAX = 0.94     # jamais plus de 94 % d'un côté, pour garder une marge


def cadre_visible(im: Image.Image):
    """Boîte du dessin réellement visible, halo transparent exclu."""
    alpha = im.getchannel("A").point(lambda v: 255 if v >= SEUIL_ALPHA else 0)
    return alpha.getbbox()


def normaliser(chemin: pathlib.Path) -> str:
    im = Image.open(chemin).convert("RGBA")
    boite = cadre_visible(im)
    if boite is None:
        return f"  ! {chemin.stem} : aucun pixel visible"

    avant_l = (boite[2] - boite[0]) / im.width
    avant_h = (boite[3] - boite[1]) / im.height

    dessin = im.crop(boite)
    l, h = dessin.size

    # Facteur qui amène l'aire du dessin à la part visée de la toile…
    facteur = ((AIRE_CIBLE * COTE * COTE) / (l * h)) ** 0.5
    # …puis bridé pour qu'aucun côté ne dépasse la marge autorisée.
    facteur = min(facteur, BORD_MAX * COTE / l, BORD_MAX * COTE / h)

    dessin = dessin.resize(
        (max(1, round(l * facteur)), max(1, round(h * facteur))), Image.LANCZOS
    )

    toile = Image.new("RGBA", (COTE, COTE), (0, 0, 0, 0))
    toile.paste(
        dessin,
        ((COTE - dessin.width) // 2, (COTE - dessin.height) // 2),
        dessin,
    )

    if chemin.suffix.lower() == ".webp":
        toile.save(chemin, "WEBP", quality=92, lossless=False)
    else:
        toile.save(chemin)

    apres_l = dessin.width / COTE
    apres_h = dessin.height / COTE
    return (
        f"  {chemin.stem:<12} "
        f"{avant_l:>4.0%}×{avant_h:<4.0%} → {apres_l:>4.0%}×{apres_h:<4.0%}"
    )


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    dossier = pathlib.Path(sys.argv[1])
    fichiers = sorted(
        f for f in dossier.iterdir() if f.suffix.lower() in {".png", ".webp"}
    )
    if not fichiers:
        print(f"Aucune icône dans {dossier}")
        return 1

    for f in fichiers:
        print(normaliser(f))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
