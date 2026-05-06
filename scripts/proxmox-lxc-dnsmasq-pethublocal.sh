#!/usr/bin/env bash
#
# Proxmox (host): создать лёгкий LXC с dnsmasq — только подмена hub.api.surehub.io → IP Home Assistant.
# Запускать на НОДЕ Proxmox от root:   bash proxmox-lxc-dnsmasq-pethublocal.sh
#
# Перед первым запуском (один раз на ноду):
#   pveam update
#   pveam available | grep -E 'alpine-.*-default.*amd64'
#   pveam download local <имя_файла_шаблона>
#
# После скрипта: в ASUS DHCP укажи DNS Server 1 = CT_DNS_IP (по умолчанию 192.168.50.52).
#
set -euo pipefail

### --- правь под свою сеть (см. hardware-and-env.md) ---
CTID="${CTID:-103}"
CT_HOSTNAME="${CT_HOSTNAME:-dns-pethublocal}"
CT_DNS_IP="${CT_DNS_IP:-192.168.50.52}"
CT_CIDR="${CT_CIDR:-24}"
ROUTER_GW="${ROUTER_GW:-192.168.50.1}"
HA_IP="${HA_IP:-192.168.50.51}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-local-lvm}"
DISK_GB="${DISK_GB:-2}"
MEMORY_MB="${MEMORY_MB:-256}"
CORES="${CORES:-1}"
UPSTREAM1="${UPSTREAM1:-1.1.1.1}"
UPSTREAM2="${UPSTREAM2:-9.9.9.9}"

# Полный путь шаблона, например: local:vztmpl/alpine-3.20-default_3.20.3-1_amd64.tar.zst
# Если пусто — скрипт попробует выбрать последний alpine *-default amd64 из pveam available.
TEMPLATE="${TEMPLATE:-}"

### ----------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root on Proxmox node"

command -v pct >/dev/null || die "pct not found — not a Proxmox node?"

if pct status "${CTID}" &>/dev/null; then
  die "container ${CTID} already exists — change CTID or remove CT first"
fi

pick_template() {
  if [[ -n "${TEMPLATE}" ]]; then
    echo "${TEMPLATE}"
    return
  fi
  local line
  line="$(pveam available 2>/dev/null | grep -E 'alpine-[0-9].*default' | grep -E 'amd64.*\.tar\.' | tail -1)" || true
  [[ -n "${line}" ]] || return 1
  echo "local:vztmpl/$(echo "${line}" | awk '{print $NF}')"
}

if [[ -z "${TEMPLATE}" ]]; then
  TEMPLATE="$(pick_template)" || TEMPLATE=""
  if [[ -z "${TEMPLATE}" ]]; then
    die "set TEMPLATE, e.g. TEMPLATE=local:vztmpl/alpine-3.20-default_XXX_amd64.tar.zst (after pveam update && pveam available)"
  fi
fi

echo "Using template: ${TEMPLATE}"
echo "Creating CT ${CTID} (${CT_HOSTNAME}) ${CT_DNS_IP}/${CT_CIDR} gw ${ROUTER_GW} -> hub.api.surehub.io = ${HA_IP}"

TMP_CONF="$(mktemp)"
trap 'rm -f "${TMP_CONF}"' EXIT

cat > "${TMP_CONF}" <<EOF
# PetHubLocal / dnsmasq — без фильтрации, только подмена имени хаба
no-resolv
domain-needed
bogus-priv
bind-interfaces
listen-address=${CT_DNS_IP}
server=${UPSTREAM1}
server=${UPSTREAM2}
address=/hub.api.surehub.io/${HA_IP}
EOF

pct create "${CTID}" "${TEMPLATE}" \
  --hostname "${CT_HOSTNAME}" \
  --memory "${MEMORY_MB}" \
  --cores "${CORES}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${CT_DNS_IP}/${CT_CIDR},gw=${ROUTER_GW}" \
  --storage "${STORAGE}" \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --unprivileged 1 \
  --onboot 1

pct start "${CTID}"
sleep 3

pct exec "${CTID}" -- sh -ec 'apk add --no-cache dnsmasq; install -d -m 0755 /etc/dnsmasq.d'
pct push "${CTID}" "${TMP_CONF}" /etc/dnsmasq.d/pethublocal.conf
pct exec "${CTID}" -- sh -ec 'rc-update add dnsmasq default; service dnsmasq restart'

echo
echo "Done. CT ${CTID}: hub.api.surehub.io -> ${HA_IP} (resolver ${CT_DNS_IP})"
echo "Next: ASUS DHCP -> DNS Server 1 = ${CT_DNS_IP}"
echo "Test: nslookup hub.api.surehub.io   (expect ${HA_IP})"
