#!/usr/bin/env bash
#
# Fabrique une image disque Debian amorçable, caisse déjà installée.
#
#   sudo ./construire-image.sh /chemin/vers/kit /chemin/de/sortie.img
#
# À lancer DANS une Debian (machine virtuelle ou conteneur privilégié), pas sur
# le Mac : il faut des périphériques loop, debootstrap et un ext4.
#
# L'image produite s'écrit ensuite telle quelle sur le SSD :
#   sudo dd if=sortie.img of=/dev/rdiskN bs=4m status=progress
#
# Deux partis pris expliquent la structure :
#
# 1. AMORÇAGE HYBRIDE. On ne sait pas si la caisse démarre en BIOS hérité ou en
#    UEFI, et se tromper signifie un disque qui ne démarre pas, sur place, sans
#    moyen d'y remédier. L'image porte donc les deux : une partition d'amorçage
#    BIOS pour GRUB en mode i386-pc, et une partition EFI contenant le chemin
#    « amovible » /EFI/BOOT/BOOTX64.EFI, qui démarre sans entrée NVRAM.
#
# 2. IMAGE COURTE, DISQUE ÉTENDU AU PREMIER DÉMARRAGE. Écrire 120 Go dont 116
#    de vide serait absurde. L'image fait 8 Gio ; un service à usage unique
#    repousse la table de partitions et le système de fichiers à la taille
#    réelle du disque, puis se désactive.

set -euo pipefail

KIT="${1:?usage: construire-image.sh <kit> <sortie.img>}"
SORTIE="${2:?usage: construire-image.sh <kit> <sortie.img>}"

TAILLE_IMAGE=8G
SUITE=bookworm
MIROIR=http://deb.debian.org/debian

msg() { printf '\033[1m==>\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "à lancer en root" >&2; exit 1; }
[ -f "$KIT/installer.sh" ] || { echo "kit incomplet : $KIT/installer.sh absent" >&2; exit 1; }

MNT=/mnt/image-caisse
BOUCLE=""

nettoyer() {
	set +e
	for point in dev/pts dev proc sys boot/efi ""; do
		mountpoint -q "$MNT/$point" && umount -lf "$MNT/$point"
	done
	[ -n "$BOUCLE" ] && losetup -d "$BOUCLE"
	set -e
}
trap nettoyer EXIT

# --------------------------------------------------------------------------
msg "Outils de construction"
# --------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	debootstrap gdisk dosfstools e2fsprogs \
	grub-pc-bin grub-efi-amd64-bin grub2-common \
	>/dev/null

# --------------------------------------------------------------------------
msg "Image et partitions"
# --------------------------------------------------------------------------
rm -f "$SORTIE"
truncate -s "$TAILLE_IMAGE" "$SORTIE"

# 1 : amorçage BIOS (1 Mio, sans système de fichiers, lu par GRUB i386-pc)
# 2 : partition EFI (512 Mio, FAT32)
# 3 : racine (tout le reste, ext4)
sgdisk --clear \
	--new=1:2048:+1M   --typecode=1:ef02 --change-name=1:amorce-bios \
	--new=2:0:+512M    --typecode=2:ef00 --change-name=2:EFI \
	--new=3:0:0        --typecode=3:8300 --change-name=3:racine \
	"$SORTIE" >/dev/null

BOUCLE="$(losetup --find --show --partscan "$SORTIE")"
msg "image montée sur $BOUCLE"

mkfs.fat -F32 -n EFI "${BOUCLE}p2" >/dev/null
mkfs.ext4 -q -L racine "${BOUCLE}p3"

UUID_RACINE="$(blkid -s UUID -o value "${BOUCLE}p3")"
UUID_EFI="$(blkid -s UUID -o value "${BOUCLE}p2")"

mkdir -p "$MNT"
mount "${BOUCLE}p3" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "${BOUCLE}p2" "$MNT/boot/efi"

# --------------------------------------------------------------------------
msg "Système de base (debootstrap, quelques minutes)"
# --------------------------------------------------------------------------
debootstrap --arch=amd64 --variant=minbase \
	--include=systemd-sysv,udev,dbus,locales,tzdata \
	"$SUITE" "$MNT" "$MIROIR" >/dev/null

mount --bind /dev     "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc  proc  "$MNT/proc"
mount -t sysfs sysfs "$MNT/sys"

# Résolution de noms pendant la construction.
#
# Piège coûteux : le paquet systemd-resolved, installé plus bas, remplace
# /etc/resolv.conf par un lien vers /run/systemd/resolve/stub-resolv.conf — un
# fichier que seul le démon crée, et qui n'existe donc jamais dans un chroot.
# Tout ce qui suit son installation perd la résolution DNS, et la construction
# échoue sur un paquet tardif sans que la cause soit visible.
#
# On pose donc un vrai fichier, en supprimant d'abord un éventuel lien mort ;
# le lien correct sera rétabli à la toute fin, pour le système installé.
rm -f "$MNT/etc/resolv.conf"
cat > "$MNT/etc/resolv.conf" <<'RESOLV'
nameserver 1.1.1.1
nameserver 9.9.9.9
RESOLV

# --------------------------------------------------------------------------
msg "Configuration du système"
# --------------------------------------------------------------------------
cat > "$MNT/etc/fstab" <<FSTAB
# Par UUID : le disque s'appellera peut-être sda, peut-être autrement, et cela
# ne doit rien changer. noatime pour épargner des écritures inutiles au SSD.
UUID=$UUID_RACINE  /          ext4  defaults,noatime,errors=remount-ro  0 1
UUID=$UUID_EFI     /boot/efi  vfat  umask=0077                          0 1
FSTAB

echo caisse > "$MNT/etc/hostname"
cat > "$MNT/etc/hosts" <<'HOSTS'
127.0.0.1   localhost
127.0.1.1   caisse
::1         localhost ip6-localhost ip6-loopback
HOSTS

cat > "$MNT/etc/apt/sources.list" <<SOURCES
deb $MIROIR $SUITE main contrib non-free-firmware
deb $MIROIR ${SUITE}-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security ${SUITE}-security main contrib non-free-firmware
SOURCES

# Le réseau en DHCP sur toute interface filaire, sans configuration à faire.
mkdir -p "$MNT/etc/systemd/network"
cat > "$MNT/etc/systemd/network/20-filaire.network" <<'RESEAU'
[Match]
Name=en* eth*

[Network]
DHCP=yes
RESEAU

cat > "$MNT/etc/default/locale" <<'LOCALE'
LANG=fr_BE.UTF-8
LOCALE
echo "fr_BE.UTF-8 UTF-8" > "$MNT/etc/locale.gen"
ln -sf /usr/share/zoneinfo/Europe/Brussels "$MNT/etc/localtime"

cat > "$MNT/etc/default/keyboard" <<'CLAVIER'
XKBMODEL="pc105"
XKBLAYOUT="be"
XKBVARIANT=""
XKBOPTIONS=""
CLAVIER

# --------------------------------------------------------------------------
msg "Noyau, amorçage et paquets (le plus long)"
# --------------------------------------------------------------------------
mkdir -p "$MNT/root/kit"
cp -a "$KIT/." "$MNT/root/kit/"

chroot "$MNT" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -s <<'CHROOT'
set -euo pipefail
apt-get update -qq
locale-gen >/dev/null 2>&1 || true

# Le micrologiciel Intel est indispensable : sans lui, le pilote graphique du
# Bay Trail se rabat sur un affichage logiciel, et une caisse « fluide » sur un
# processeur de 2013 sans accélération, cela n'existe pas.
apt-get install -y -qq --no-install-recommends \
    linux-image-amd64 firmware-linux-free firmware-misc-nonfree intel-microcode \
    grub-pc-bin grub-efi-amd64-bin grub2-common \
    systemd-timesyncd systemd-resolved \
    sudo curl ca-certificates less nano \
    console-setup keyboard-configuration \
    cloud-guest-utils gdisk \
    >/dev/null

systemctl enable systemd-networkd systemd-resolved systemd-timesyncd >/dev/null 2>&1 || true

# Compte d'administration. Le mot de passe n'est qu'un filet : l'accès normal
# se fait par clé SSH, posée plus bas par l'installeur.
useradd -m -s /bin/bash -G sudo abdu
echo 'abdu:caisse-a-changer' | chpasswd
passwd -l root >/dev/null
CHROOT

# --------------------------------------------------------------------------
msg "GRUB — BIOS et UEFI"
# --------------------------------------------------------------------------
cat > "$MNT/etc/default/grub" <<'GRUB'
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_DISTRIBUTOR=Caisse
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 vt.global_cursor_default=0 consoleblank=0 systemd.show_status=0"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_RECOVERY=true
GRUB
sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="Caisse"|' "$MNT/etc/default/grub"

chroot "$MNT" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -s "$BOUCLE" <<'CHROOT'
set -euo pipefail
BOUCLE="$1"

# Amorçage BIOS hérité : GRUB s'écrit dans les premiers secteurs du disque et
# se prolonge dans la partition d'amorçage BIOS.
grub-install --target=i386-pc --boot-directory=/boot --recheck "$BOUCLE" >/dev/null 2>&1

# Amorçage UEFI en chemin « amovible » : /EFI/BOOT/BOOTX64.EFI est le seul
# chemin qu'un micrologiciel démarre sans qu'on ait rien inscrit dans sa NVRAM.
# C'est ce qui permet à ce disque de démarrer sur une machine qu'il n'a jamais
# vue — exactement notre cas.
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
    --bootloader-id=caisse --removable --recheck >/dev/null 2>&1

grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
CHROOT

# --------------------------------------------------------------------------
msg "Installation de la caisse dans l'image"
# --------------------------------------------------------------------------
chroot "$MNT" bash -c 'cd /root/kit && MODE_AFFICHAGE=cage bash ./installer.sh' \
	2>&1 | sed 's/^/    /'

# --------------------------------------------------------------------------
msg "Extension au premier démarrage"
# --------------------------------------------------------------------------
# L'image fait 8 Gio ; le disque en fait 120. Sans ce service, 112 Go
# resteraient inutilisables. Il s'exécute une fois puis se désactive.
cat > "$MNT/usr/local/sbin/etendre-disque.sh" <<'ETENDRE'
#!/bin/sh
set -eu
RACINE="$(findmnt -no SOURCE /)"
DISQUE="/dev/$(lsblk -no PKNAME "$RACINE")"
NUMERO="$(echo "$RACINE" | grep -o '[0-9]*$')"

# L'image ayant été copiée sur un disque plus grand, la copie de secours de la
# table de partitions se trouve au mauvais endroit. sgdisk -e la replace à la
# fin du disque réel ; sans cela, agrandir la partition échoue.
sgdisk -e "$DISQUE" >/dev/null 2>&1 || true
partprobe "$DISQUE" >/dev/null 2>&1 || true

growpart "$DISQUE" "$NUMERO" >/dev/null 2>&1 || true
resize2fs "$RACINE" >/dev/null 2>&1 || true

systemctl disable etendre-disque.service >/dev/null 2>&1 || true
ETENDRE
chmod 755 "$MNT/usr/local/sbin/etendre-disque.sh"

cat > "$MNT/etc/systemd/system/etendre-disque.service" <<'UNIT'
[Unit]
Description=Étendre la racine à la taille réelle du disque (une seule fois)
DefaultDependencies=no
After=local-fs.target
Before=caisse.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/etendre-disque.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
chroot "$MNT" systemctl enable etendre-disque.service >/dev/null 2>&1

# --------------------------------------------------------------------------
msg "Finition"
# --------------------------------------------------------------------------
chroot "$MNT" apt-get clean >/dev/null
rm -rf "$MNT/root/kit" "$MNT/var/lib/apt/lists/"* "$MNT/tmp/"*

# Rendre la résolution de noms au système installé : sur la machine réelle,
# systemd-resolved tournera et créera bien le fichier visé par ce lien.
rm -f "$MNT/etc/resolv.conf"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"

# La base créée pendant la construction porterait la date et l'heure de la
# construction. On la retire : la caisse la recréera au premier démarrage à
# partir du catalogue.
rm -f "$MNT/var/lib/caisse/caisse.db"* "$MNT/var/backups/caisse/"*

sync
nettoyer
trap - EXIT

msg "Image prête : $SORTIE ($(du -h "$SORTIE" | cut -f1))"
