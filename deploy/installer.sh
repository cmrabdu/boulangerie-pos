#!/usr/bin/env bash
#
# Transforme une Debian fraîchement installée en caisse de boulangerie.
#
#   sudo ./installer.sh
#
# À poser dans un dossier contenant aussi :
#   boulangerie-pos-linux-amd64   le binaire (make linux)
#   img/                          les illustrations et icônes (facultatif)
#   catalogue.csv                 le catalogue (facultatif)
#   cle-publique.pub              clé SSH à autoriser (facultatif)
#
# Le script est idempotent : le relancer ne casse rien et reprend la
# configuration là où elle en est.
#
# Ce qu'il fait, dans l'ordre : un utilisateur dédié sans droits, le logiciel
# dans /opt, les données dans /var/lib, deux services systemd (le serveur et
# l'écran), une sauvegarde quotidienne, puis le durcissement du démarrage pour
# qu'on ne voie jamais autre chose que la caisse.

set -euo pipefail

ICI="$(cd "$(dirname "$0")" && pwd)"
UTILISATEUR=caisse
RACINE=/opt/caisse
DONNEES=/var/lib/caisse
SAUVEGARDES=/var/backups/caisse
PORT=8080

MODE_AFFICHAGE="${MODE_AFFICHAGE:-cage}"   # cage (Wayland) ou x11

msg()    { printf '\033[1m==>\033[0m %s\n' "$*"; }
erreur() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || erreur "à lancer avec sudo"
[ -f /etc/debian_version ] || erreur "prévu pour Debian"

BINAIRE="$ICI/boulangerie-pos-linux-amd64"
[ -f "$BINAIRE" ] || erreur "binaire absent : $BINAIRE (le produire avec « make linux »)"

# --------------------------------------------------------------------------
msg "Disques"
# --------------------------------------------------------------------------
# Tout doit rester sur le SSD. Le disque d'origine de la caisse, s'il est encore
# branché, ne doit être ni monté, ni écrit, ni même référencé par le démarrage.
# On établit ici, avant toute écriture, sur quel disque physique on travaille,
# et lesquels on laisse tranquilles.

DISQUE_RACINE=""
if command -v lsblk >/dev/null 2>&1; then
	SOURCE_RACINE="$(findmnt -no SOURCE / 2>/dev/null || true)"
	DISQUE_RACINE="$(lsblk -no PKNAME "$SOURCE_RACINE" 2>/dev/null | head -1 || true)"

	if [ -n "$DISQUE_RACINE" ]; then
		TAILLE="$(lsblk -dno SIZE "/dev/$DISQUE_RACINE" 2>/dev/null | tr -d ' ')"
		MODELE="$(lsblk -dno MODEL "/dev/$DISQUE_RACINE" 2>/dev/null | sed 's/ *$//')"
		echo "    système installé sur : /dev/$DISQUE_RACINE  ($TAILLE  $MODELE)"
	fi

	AUTRES="$(lsblk -dno NAME,SIZE,MODEL 2>/dev/null \
		| grep -vE "^(${DISQUE_RACINE:-__aucun__}|loop|sr|ram)" || true)"
	if [ -n "$AUTRES" ]; then
		echo
		printf '\033[1;33m    Autres disques présents — AUCUNE écriture n'"'"'y sera faite :\033[0m\n'
		echo "$AUTRES" | sed 's/^/      /'
		echo
		echo "    Si l'un d'eux est le disque Windows d'origine, le plus sûr reste"
		echo "    de le débrancher : un disque absent ne peut pas être abîmé."
		echo
	fi
fi

# --------------------------------------------------------------------------
msg "Paquets"
# --------------------------------------------------------------------------
# On installe les DEUX piles d'affichage. Wayland/cage est la pile retenue,
# mais si elle refuse de démarrer sur ce GPU de 2013, la bascule vers X11 doit
# pouvoir se faire sur place sans réseau ni téléchargement.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
	chromium \
	cage \
	xserver-xorg-core xserver-xorg-video-intel xserver-xorg-input-libinput xinit x11-xserver-utils \
	fonts-dejavu-core \
	openssh-server \
	avahi-daemon \
	ca-certificates \
	>/dev/null

# Inter est la police du dessin d'origine ; DejaVu prend le relais si le paquet
# n'existe pas dans cette version de Debian.
apt-get install -y -qq --no-install-recommends fonts-inter >/dev/null 2>&1 \
	&& msg "police Inter installée" \
	|| msg "police Inter indisponible, DejaVu utilisée"

# --------------------------------------------------------------------------
msg "Utilisateur $UTILISATEUR"
# --------------------------------------------------------------------------
# Compte système sans mot de passe et sans droits : la caisse n'a aucune raison
# de pouvoir administrer la machine.
if ! id "$UTILISATEUR" >/dev/null 2>&1; then
	useradd --system --create-home --home-dir "/home/$UTILISATEUR" \
		--shell /usr/sbin/nologin "$UTILISATEUR"
fi
# video et render : accès à la carte graphique. input : à l'écran tactile.
usermod -aG video,render,input,tty "$UTILISATEUR"

# --------------------------------------------------------------------------
msg "Logiciel dans $RACINE"
# --------------------------------------------------------------------------
install -d -m 755 "$RACINE"
install -m 755 "$BINAIRE" "$RACINE/boulangerie-pos"

install -d -o "$UTILISATEUR" -g "$UTILISATEUR" -m 755 "$DONNEES" "$DONNEES/img"
install -d -o "$UTILISATEUR" -g "$UTILISATEUR" -m 755 "$SAUVEGARDES"

# Les illustrations vivent dans les données, pas dans le logiciel : en ajouter
# une ne doit jamais demander de réinstaller quoi que ce soit.
if [ -d "$ICI/img" ]; then
	cp -a "$ICI/img/." "$DONNEES/img/"
	chown -R "$UTILISATEUR:$UTILISATEUR" "$DONNEES/img"
	msg "illustrations copiées ($(find "$DONNEES/img" -type f | wc -l | tr -d ' ') fichiers)"
fi

if [ -f "$ICI/catalogue.csv" ] && [ ! -f "$DONNEES/catalogue.csv" ]; then
	install -o "$UTILISATEUR" -g "$UTILISATEUR" -m 644 "$ICI/catalogue.csv" "$DONNEES/catalogue.csv"
	msg "catalogue installé"
fi

# --------------------------------------------------------------------------
msg "Accès SSH"
# --------------------------------------------------------------------------
if [ -f "$ICI/cle-publique.pub" ]; then
	for cible in /root /home/*; do
		[ -d "$cible" ] || continue
		compte="$(basename "$cible")"
		[ "$compte" = "$UTILISATEUR" ] && continue   # la caisse ne se connecte pas
		install -d -m 700 -o "$compte" -g "$compte" "$cible/.ssh" 2>/dev/null || continue
		touch "$cible/.ssh/authorized_keys"
		grep -qxF "$(cat "$ICI/cle-publique.pub")" "$cible/.ssh/authorized_keys" \
			|| cat "$ICI/cle-publique.pub" >> "$cible/.ssh/authorized_keys"
		chmod 600 "$cible/.ssh/authorized_keys"
		chown "$compte:$compte" "$cible/.ssh/authorized_keys" 2>/dev/null || true
	done
	msg "clé publique autorisée"
fi
systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true

# Le nom de la machine sert à la joindre sans connaître son adresse :
# « ssh caisse.local » depuis n'importe quel poste du réseau.
hostnamectl set-hostname caisse 2>/dev/null || echo caisse > /etc/hostname
# Motif ancré, et pas un simple « caisse » : sur une machine nommée
# « caisse-neuve », la recherche approximative trouvait une correspondance, la
# ligne n'était jamais ajoutée, et le nom devenait irrésolvable — sudo mettait
# alors dix secondes à répondre à chaque commande.
grep -qE '^127\.0\.1\.1[[:space:]]+caisse([[:space:]]|$)' /etc/hosts \
	|| echo "127.0.1.1 caisse" >> /etc/hosts

# --------------------------------------------------------------------------
msg "Service du serveur"
# --------------------------------------------------------------------------
cat > /etc/systemd/system/caisse.service <<UNIT
[Unit]
Description=Caisse — serveur
Documentation=https://github.com/cmrabdu/boulangerie-pos
After=network.target
# Ces deux clés vont dans [Unit], pas dans [Service] : systemd les y ignore
# silencieusement, et la limite de redémarrages resterait active — au bout de
# cinq plantages rapprochés il abandonnerait, laissant la boulangerie sans
# caisse. Vérifié : « Unknown key » dans le journal quand elles sont mal placées.
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
User=$UTILISATEUR
Group=$UTILISATEUR
WorkingDirectory=$DONNEES
ExecStart=$RACINE/boulangerie-pos \\
    -addr 127.0.0.1:$PORT \\
    -db $DONNEES/caisse.db \\
    -img $DONNEES/img \\
    -catalogue $DONNEES/catalogue.csv

# Une caisse qui plante doit revenir seule, et vite. Sans limite de tentatives :
# abandonner au bout de cinq essais laisserait la boulangerie sans caisse.
Restart=always
RestartSec=2

# Le serveur n'écoute que sur la boucle locale et ne touche qu'à son dossier.
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$DONNEES $SAUVEGARDES
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

[Install]
WantedBy=multi-user.target
UNIT

# --------------------------------------------------------------------------
msg "Service de l'écran ($MODE_AFFICHAGE)"
# --------------------------------------------------------------------------
# Les options de Chromium, une par une :
#   --kiosk                        plein écran sans aucun ornement
#   --noerrdialogs                 aucune boîte de dialogue d'erreur
#   --disable-session-crashed-bubble  pas de « Restaurer les pages ? » après
#                                  une coupure de courant — personne ne saurait
#                                  quoi en faire à 7 h du matin
#   --disable-infobars             aucun bandeau
#   --check-for-update-interval    une fois par an, autant dire jamais
#   --disable-pinch                le zoom à deux doigts rendrait l'écran
#                                  inutilisable et indéréglable
#   --overscroll-history-navigation=0  un glissement ne revient pas en arrière
#   --disable-features=Translate   pas de proposition de traduction
CHROME_OPTS="--kiosk \
--noerrdialogs \
--disable-infobars \
--disable-session-crashed-bubble \
--disable-features=Translate,TranslateUI,AutofillServerCommunication \
--disable-component-update \
--check-for-update-interval=31536000 \
--no-first-run \
--no-default-browser-check \
--disable-pinch \
--overscroll-history-navigation=0 \
--hide-scrollbars \
--password-store=basic \
--touch-events=enabled \
--force-device-scale-factor=1"

cat > "$RACINE/lancer-ecran.sh" <<LANCEUR
#!/bin/sh
# Lancé par systemd au démarrage. Séparé de l'unité pour rester lisible et
# modifiable sans toucher à systemd.
set -eu

PROFIL="\$HOME/.config/chromium"

# Après une coupure de courant, Chromium retient qu'il s'est mal arrêté et
# propose de restaurer les onglets. On efface cette trace avant chaque
# démarrage : la caisse doit toujours repartir dans le même état.
if [ -f "\$PROFIL/Default/Preferences" ]; then
    sed -i 's/"exit_type":"[^"]*"/"exit_type":"Normal"/' "\$PROFIL/Default/Preferences" || true
fi

# On attend que le serveur réponde avant d'afficher quoi que ce soit, sinon
# l'écran s'ouvre sur une page d'erreur pendant une seconde.
i=0
while [ \$i -lt 60 ]; do
    if command -v curl >/dev/null 2>&1; then
        curl -sf -o /dev/null "http://127.0.0.1:$PORT/" && break
    else
        (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break
    fi
    i=\$((i + 1))
    sleep 0.5
done

exec chromium $CHROME_OPTS --app="http://127.0.0.1:$PORT/"
LANCEUR
chmod 755 "$RACINE/lancer-ecran.sh"

# --- pile Wayland (retenue) ---
cat > /etc/systemd/system/caisse-ecran.service <<UNIT
[Unit]
Description=Caisse — écran (Wayland, cage)
After=caisse.service systemd-user-sessions.service
Wants=caisse.service
Conflicts=getty@tty1.service caisse-ecran-x11.service
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
User=$UTILISATEUR
# PAMName=login ouvre une vraie session : sans elle, ni XDG_RUNTIME_DIR ni
# l'accès au siège graphique ne sont accordés, et cage refuse de démarrer.
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
Environment=XDG_SESSION_TYPE=wayland
Environment=MOZ_ENABLE_WAYLAND=1
ExecStart=/usr/bin/cage -d -- $RACINE/lancer-ecran.sh
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
UNIT

# --- pile X11 (secours) ---
cat > /etc/systemd/system/caisse-ecran-x11.service <<UNIT
[Unit]
Description=Caisse — écran (X11, secours)
After=caisse.service systemd-user-sessions.service
Wants=caisse.service
Conflicts=getty@tty1.service caisse-ecran.service
StartLimitIntervalSec=0
StartLimitBurst=0

[Service]
Type=simple
User=$UTILISATEUR
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
ExecStart=/usr/bin/xinit $RACINE/lancer-ecran.sh -- :0 vt1 -nolisten tcp -novtswitch
Restart=always
RestartSec=2

[Install]
WantedBy=graphical.target
UNIT

# Sous X11, l'écran s'éteindrait au bout de dix minutes d'inactivité. Une caisse
# reste allumée toute la journée sans qu'on la touche entre deux clients.
install -d -m 755 /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-veille.conf <<'CONF'
Section "ServerFlags"
    Option "BlankTime"   "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime"     "0"
EndSection
CONF

# --------------------------------------------------------------------------
msg "Sauvegarde quotidienne"
# --------------------------------------------------------------------------
cat > "$RACINE/sauvegarder.sh" <<SAUV
#!/bin/sh
# Copie cohérente de la base, caisse allumée (VACUUM INTO), puis rotation.
set -eu
DEST="$SAUVEGARDES/caisse-\$(date +%F).db"
rm -f "\$DEST"
$RACINE/boulangerie-pos -db $DONNEES/caisse.db -backup "\$DEST"
# On garde trente jours. Une caisse de boulangerie tient dans quelques
# mégaoctets : c'est gratuit, et ça couvre un retour de vacances.
ls -1t "$SAUVEGARDES"/caisse-*.db 2>/dev/null | tail -n +31 | xargs -r rm -f
SAUV
chmod 755 "$RACINE/sauvegarder.sh"

cat > /etc/systemd/system/caisse-sauvegarde.service <<UNIT
[Unit]
Description=Caisse — sauvegarde de la base

[Service]
Type=oneshot
User=$UTILISATEUR
ExecStart=$RACINE/sauvegarder.sh
UNIT

cat > /etc/systemd/system/caisse-sauvegarde.timer <<'UNIT'
[Unit]
Description=Caisse — sauvegarde quotidienne

[Timer]
OnCalendar=*-*-* 03:30:00
# La caisse est éteinte la nuit : sans ça, la sauvegarde ne partirait jamais.
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# --------------------------------------------------------------------------
msg "Démarrage silencieux"
# --------------------------------------------------------------------------
# Objectif : entre l'appui sur le bouton et la caisse, on ne doit rien voir
# d'autre. Pas de menu, pas de lignes de journal, pas de curseur clignotant.
if [ -f /etc/default/grub ]; then
	sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
	grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub \
		&& sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub \
		|| echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
	sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 vt.global_cursor_default=0 consoleblank=0 systemd.show_status=0"/' \
		/etc/default/grub

	# Confinement au SSD : sans cette ligne, GRUB explore les autres disques au
	# démarrage pour y chercher des systèmes à proposer. On ne veut ni qu'il les
	# lise, ni qu'un menu apparaisse, ni qu'un Windows resté branché devienne
	# démarrable par erreur.
	grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub \
		&& sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' /etc/default/grub \
		|| echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub

	update-grub >/dev/null 2>&1 || true
fi

# Aucun autre disque ne doit être monté automatiquement. On vérifie que /etc/fstab
# ne référence rien d'autre que le disque du système et les pseudo-systèmes.
if [ -n "${DISQUE_RACINE:-}" ] && command -v lsblk >/dev/null 2>&1; then
	SUSPECTS=""
	while read -r peripherique _; do
		case "$peripherique" in
			""|\#*|proc|sysfs|tmpfs|devpts|none|UUID=*|PARTUUID=*|LABEL=*) continue ;;
			/dev/*)
				parent="$(lsblk -no PKNAME "$peripherique" 2>/dev/null | head -1 || true)"
				[ -n "$parent" ] && [ "$parent" != "$DISQUE_RACINE" ] \
					&& SUSPECTS="$SUSPECTS $peripherique"
				;;
		esac
	done < /etc/fstab
	[ -n "$SUSPECTS" ] && printf '\033[1;33m!!\033[0m /etc/fstab monte des partitions hors du disque système :%s\n' "$SUSPECTS"
fi

# La caisse démarre sur l'écran, pas sur une invite de connexion.
systemctl set-default graphical.target >/dev/null 2>&1 || true
systemctl disable getty@tty1.service >/dev/null 2>&1 || true

# --------------------------------------------------------------------------
msg "Allègement"
# --------------------------------------------------------------------------
# Sur un Celeron de 2013, chaque service inutile se paie au démarrage.
for inutile in \
	bluetooth.service \
	ModemManager.service \
	cups.service cups-browsed.service \
	NetworkManager-wait-online.service \
	apt-daily.timer apt-daily-upgrade.timer \
	man-db.timer \
	e2scrub_all.timer
do
	systemctl disable --now "$inutile" >/dev/null 2>&1 || true
done

# Les mises à jour automatiques sont désactivées volontairement : sur une
# caisse, une mise à jour surprise qui casse Chromium un samedi matin coûte
# plus cher que le retard de correctifs. Elles se font à la main, par SSH.
systemctl disable --now unattended-upgrades.service >/dev/null 2>&1 || true

# L'horloge, en revanche, reste synchronisée : elle horodate les ventes.
systemctl enable --now systemd-timesyncd.service >/dev/null 2>&1 || true

# SSD : découpe hebdomadaire, et pas d'écriture de date d'accès à chaque
# lecture de fichier.
systemctl enable fstrim.timer >/dev/null 2>&1 || true
if ! grep -q 'noatime' /etc/fstab; then
	sed -i 's|\(\s/\s\+ext4\s\+\)defaults|\1defaults,noatime|' /etc/fstab || true
fi

# 8 Go de mémoire pour un navigateur et un binaire de 15 Mo : on ne veut pas
# que le noyau parte échanger sur le disque sans raison.
echo 'vm.swappiness=10' > /etc/sysctl.d/99-caisse.conf

# --------------------------------------------------------------------------
msg "Activation"
# --------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable caisse.service >/dev/null
# --now, sinon le minuteur n'existe qu'au prochain démarrage et la première
# nuit passe sans sauvegarde.
systemctl enable --now caisse-sauvegarde.timer >/dev/null

if [ "$MODE_AFFICHAGE" = "x11" ]; then
	systemctl disable caisse-ecran.service >/dev/null 2>&1 || true
	systemctl enable caisse-ecran-x11.service >/dev/null
else
	systemctl disable caisse-ecran-x11.service >/dev/null 2>&1 || true
	systemctl enable caisse-ecran.service >/dev/null
fi

systemctl restart caisse.service

echo
msg "Installation terminée."
cat <<FIN

  Serveur      : systemctl status caisse
  Écran        : systemctl status caisse-ecran
  Journal      : journalctl -u caisse -u caisse-ecran -f
  Données      : $DONNEES
  Sauvegardes  : $SAUVEGARDES

  Mettre le catalogue à jour, depuis n'importe quel poste :
      scp catalogue.csv caisse.local:$DONNEES/catalogue.csv
  La caisse le reprend en quelques secondes, sans redémarrage.

  Si l'écran reste noir au redémarrage, basculer sur X11 :
      systemctl disable --now caisse-ecran
      systemctl enable --now caisse-ecran-x11

  Redémarrer maintenant pour vérifier le démarrage complet : reboot

FIN
