# Déploiement sur la caisse

Cible : Celeron J1900, 8 Go, écran tactile, SSD SATA 120 Go.

## Avant de partir — préparer la clé

Depuis ce dépôt, sur le Mac :

```bash
make kit
```

Cela produit `dist/kit/`, à copier tel quel sur une clé USB. Il contient le
binaire Linux, les illustrations, l'installeur et la clé publique SSH.

Il faut aussi une **clé d'installation Debian** : image `netinst` de Debian 12
amd64, écrite sur une seconde clé USB (Raspberry Pi Imager, balenaEtcher, ou
`dd`). Copier `preseed.cfg` à la racine de cette clé si l'installation non
assistée est souhaitée.

## Sur place

### 1. Le disque

**Débrancher le disque d'origine et le mettre de côté.** Brancher le SSD à sa
place.

C'est la seule garantie qui ne dépende d'aucun réglage : un disque absent ne
peut être ni effacé, ni écrit, ni rendu démarrable par erreur. Et le retour
arrière tient en un tournevis — si la caisse ne convient pas, on remet
l'ancien disque et tout est exactement comme avant, logiciel et données
comprises.

### 2. Le BIOS

Démarrer sur la clé Debian. Vérifier au passage le mode d'amorçage, **BIOS
hérité ou UEFI** : il faudra le même pour le SSD ensuite.

### 3. Debian

Installation minimale : pas d'environnement de bureau, uniquement `ssh-server`
et les utilitaires standard. Avec `preseed.cfg`, tout se fait sans question.

### 4. La caisse

Copier le kit depuis la clé USB, puis :

```bash
sudo ./installer.sh
```

Environ cinq minutes, le temps de télécharger Chromium. À la fin, l'installeur
affiche sur quel disque il a écrit et liste ceux auxquels il n'a pas touché.

```bash
sudo reboot
```

La machine doit démarrer directement sur la caisse : ni menu, ni invite de
connexion, ni ligne de journal.

## Vérifications

```bash
systemctl status caisse caisse-ecran
journalctl -u caisse -u caisse-ecran -f
```

**Si l'écran reste noir**, la pile Wayland n'a pas démarré sur ce GPU de 2013.
Les deux piles sont installées, la bascule ne demande aucun téléchargement :

```bash
sudo systemctl disable --now caisse-ecran
sudo systemctl enable --now caisse-ecran-x11
```

## Au quotidien

Mettre le catalogue à jour, depuis n'importe quel poste du réseau :

```bash
scp catalogue.csv caisse.local:/var/lib/caisse/catalogue.csv
```

La caisse le reprend en quelques secondes, sans redémarrage et sans que
personne n'ait à toucher l'écran.

Ajouter une illustration :

```bash
scp baguette.webp caisse.local:/var/lib/caisse/img/products/
```

Récupérer le journal des ventes :

```bash
ssh caisse.local 'curl -s http://127.0.0.1:8080/api/sales/export.csv' > ventes.csv
```

Mettre à jour le logiciel :

```bash
scp dist/boulangerie-pos-linux-amd64 caisse.local:/tmp/
ssh caisse.local 'sudo install -m755 /tmp/boulangerie-pos-linux-amd64 /opt/caisse/boulangerie-pos && sudo systemctl restart caisse'
```

## Ce qui est installé où

| Chemin | Contenu |
|---|---|
| `/opt/caisse/` | le binaire et les scripts |
| `/var/lib/caisse/` | base de données, catalogue, illustrations |
| `/var/backups/caisse/` | sauvegardes quotidiennes, trente jours |
| `/etc/systemd/system/caisse*.service` | les services |

Le serveur n'écoute que sur `127.0.0.1` : rien n'est joignable depuis le
réseau, sauf SSH.

## Choix expliqués

**Deux services séparés**, le serveur et l'écran. Chromium peut planter et
redémarrer sans que la base de données soit touchée ; le serveur peut
redémarrer sans éteindre l'écran.

**Redémarrage sans limite de tentatives.** Par défaut, systemd abandonne au
bout de cinq redémarrages rapprochés. Sur une caisse, abandonner signifie
laisser la boulangerie sans moyen d'encaisser : on préfère qu'elle réessaie
indéfiniment.

**Mises à jour automatiques désactivées.** Une mise à jour surprise qui casse
Chromium un samedi matin coûte plus cher que le retard de correctifs sur une
machine qui n'écoute rien depuis le réseau. Elles se font à la main, par SSH,
un jour de fermeture.

**L'horloge, elle, reste synchronisée** : elle horodate les ventes.

**`GRUB_DISABLE_OS_PROBER=true`.** Sans cette ligne, GRUB explore les autres
disques au démarrage pour y chercher des systèmes à proposer. On ne veut ni
qu'il les lise, ni qu'un menu apparaisse.

**Aucun `swap`.** 8 Go pour un navigateur et un binaire de 10 Mo : l'échange
n'userait que le SSD.
