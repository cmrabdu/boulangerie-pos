#!/usr/bin/env bash
#
# Démarre l'image de la caisse dans QEMU et photographie l'écran.
#
#   ./tester-image.sh caisse.img bios   > capture-bios.png
#   ./tester-image.sh caisse.img uefi   > capture-uefi.png
#
# À lancer sur le Mac. Le but n'est pas de se servir de la caisse mais de
# répondre à une seule question : ce disque démarre-t-il, et jusqu'où ?
#
# On teste les DEUX modes d'amorçage parce qu'on ignore celui du PC de la
# boulangerie, et qu'un disque qui ne démarre pas se découvre sur place, sans
# recours.
#
# L'écran est capturé par le moniteur QMP de QEMU plutôt qu'affiché : il n'y a
# pas d'utilisateur devant, et une image vaut mieux qu'un journal pour dire si
# la caisse est bien à l'écran.

set -euo pipefail

IMAGE="${1:?usage: tester-image.sh <image> <bios|uefi> [secondes]}"
MODE="${2:-bios}"
ATTENTE="${3:-90}"

FIRMWARE=/opt/homebrew/share/qemu/edk2-x86_64-code.fd
VARS_MODELE=/opt/homebrew/share/qemu/edk2-i386-vars.fd

TRAVAIL="$(mktemp -d)"
QMP="$TRAVAIL/qmp.sock"
PPM="$TRAVAIL/ecran.ppm"
trap 'rm -rf "$TRAVAIL"; [ -n "${QPID:-}" ] && kill "$QPID" 2>/dev/null || true' EXIT

ARGS=(
	-machine q35
	-m 2048
	-smp 2
	-drive "file=$IMAGE,format=raw,if=virtio"
	# virtio-vga expose un vrai périphérique DRM au noyau : sans lui, cage n'a
	# aucune carte graphique à ouvrir et l'écran resterait noir pour une raison
	# qui n'existe pas sur le matériel réel.
	-device virtio-vga
	-device virtio-tablet-pci      # pointeur absolu, comme un écran tactile
	-net none
	-display none
	-qmp "unix:$QMP,server,nowait"
)

if [ "$MODE" = "uefi" ]; then
	cp "$VARS_MODELE" "$TRAVAIL/vars.fd"
	ARGS+=(
		-drive "if=pflash,format=raw,readonly=on,file=$FIRMWARE"
		-drive "if=pflash,format=raw,file=$TRAVAIL/vars.fd"
	)
fi

qemu-system-x86_64 "${ARGS[@]}" >"$TRAVAIL/qemu.log" 2>&1 &
QPID=$!

echo "démarrage en mode $MODE, capture dans ${ATTENTE}s…" >&2
sleep "$ATTENTE"

kill -0 "$QPID" 2>/dev/null || { echo "QEMU s'est arrêté :" >&2; cat "$TRAVAIL/qemu.log" >&2; exit 1; }

python3 - "$QMP" "$PPM" <<'PY'
import json, socket, sys

chemin, sortie = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(chemin)
f = s.makefile("rwb")
f.readline()                                   # bannière de bienvenue
for requete in ({"execute": "qmp_capabilities"},
                {"execute": "screendump", "arguments": {"filename": sortie}}):
    f.write((json.dumps(requete) + "\n").encode())
    f.flush()
    while True:
        reponse = json.loads(f.readline())
        if "return" in reponse or "error" in reponse:
            if "error" in reponse:
                sys.exit(f"QMP : {reponse['error']}")
            break
PY

sips -s format png "$PPM" --out "${PPM%.ppm}.png" >/dev/null 2>&1
cat "${PPM%.ppm}.png"
