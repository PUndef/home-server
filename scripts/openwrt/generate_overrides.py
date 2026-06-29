"""Generate OpenWrt override snippets from config/openwrt/overrides.json.

Default mode is dry-run: print generated blocks and do not modify existing scripts.
Use --write to patch embedded blocks in repo scripts. This does not upload to the router.

Usage:
  py -3 scripts/openwrt/generate_overrides.py --dry-run
  py -3 scripts/openwrt/generate_overrides.py --check
  py -3 scripts/openwrt/generate_overrides.py --write
  py -3 scripts/openwrt/generate_overrides.py --out-dir .generated/openwrt
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts" / "openwrt"
DEFAULT_MANIFEST = ROOT / "config" / "openwrt" / "overrides.json"

BEGIN_APPLY = "# BEGIN GENERATED: openwrt-overrides apply lists"
END_APPLY = "# END GENERATED: openwrt-overrides apply lists"
BEGIN_APPLY_CONST = "# BEGIN GENERATED: openwrt-overrides apply constants"
END_APPLY_CONST = "# END GENERATED: openwrt-overrides apply constants"
BEGIN_POLICY_REORDER = "# BEGIN GENERATED: openwrt-overrides policy reorder"
END_POLICY_REORDER = "# END GENERATED: openwrt-overrides policy reorder"
BEGIN_ZAPRET = "# BEGIN GENERATED: openwrt-overrides zapret destiny nets"
END_ZAPRET = "# END GENERATED: openwrt-overrides zapret destiny nets"
BEGIN_ZAPRET_DEVICES = "# BEGIN GENERATED: openwrt-overrides zapret devices"
END_ZAPRET_DEVICES = "# END GENERATED: openwrt-overrides zapret devices"
BEGIN_ZAPRET_SDR = "# BEGIN GENERATED: openwrt-overrides zapret steam sdr"
END_ZAPRET_SDR = "# END GENERATED: openwrt-overrides zapret steam sdr"
BEGIN_LOGIN = "# BEGIN GENERATED: openwrt-overrides destiny login constants"
END_LOGIN = "# END GENERATED: openwrt-overrides destiny login constants"
BEGIN_CHECK = "# BEGIN GENERATED: openwrt-overrides check expectations"
END_CHECK = "# END GENERATED: openwrt-overrides check expectations"

POLICY_IDX_VARS = {
    "steam_auth": "steam_auth_idx",
    "steam_cdn": "steam_cdn_idx",
    "nexus": "nexus_idx",
    "ru_local": "ru_local_idx",
    "lib_ddg": "lib_ddg_idx",
    "discord": "discord_idx",
    "destiny_auth": "destiny_idx",
    "srv_default": "srv_default_idx",
    "warframe": "warframe_idx",
}


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def shell_list(name: str, values: list[str]) -> str:
    if not values:
        return f'{name}=""'
    if len(values) == 1:
        return f'{name}="{values[0]}"'
    lines = [f'{name}="{values[0]} \\']
    for value in values[1:-1]:
        lines.append(f"  {value} \\")
    lines.append(f'  {values[-1]}"')
    return "\n".join(lines)


def baseline_var_name(key: str) -> str:
    mapping = {
        "steam_auth": "STEAM_AUTH_DOMAINS",
        "steam_cdn": "STEAM_CDN_DOMAINS",
        "nexus": "NEXUS_DOMAINS",
        "ru_local": "RU_LOCAL_DOMAINS",
        "lib_ddg": "LIB_DDG_DOMAINS",
        "warframe": "WARFRAME_DOMAINS",
    }
    return mapping[key]


def render_apply_constants_block(manifest: dict[str, Any]) -> str:
    static_ips = manifest["pbr_baseline"]["steam_auth"].get("static_ips", [])
    static_value = " ".join(static_ips)
    return "\n".join(
        [
            BEGIN_APPLY_CONST,
            "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
            f'STEAM_AUTH_STATIC_IPS="{static_value}"',
            END_APPLY_CONST,
        ]
    )


def render_policy_reorder_block(manifest: dict[str, Any]) -> str:
    order = list(manifest.get("pbr_policy_order", []))
    # Warframe is global; do not reorder it relative to pundef-pc chain ( broke priority when moved to [1] ).

    lines = [
        BEGIN_POLICY_REORDER,
        "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
        f'# Policy order: {" -> ".join(order)} (warframe global — not reordered here)',
        "# Pull steam_auth ahead of steam_cdn if indices drifted.",
        'if [ "${steam_auth_idx}" -gt "${steam_cdn_idx}" ]; then',
        '  reorder_policy_before "${steam_auth_idx}" "${steam_cdn_idx}"',
        "fi",
    ]

    pairs = list(zip(order, order[1:]))
    if pairs:
        first_late, first_early = pairs[0]
        late_var = POLICY_IDX_VARS[first_late]
        early_var = POLICY_IDX_VARS[first_early]
        lines.append(f'reorder_policy_before "${{{late_var}}}" "${{{early_var}}}"')

    for early_key, late_key in pairs[1:]:
        early_var = POLICY_IDX_VARS[early_key]
        late_var = POLICY_IDX_VARS[late_key]
        lines.extend(
            [
                f'if [ "${{{late_var}}}" -gt "${{{early_var}}}" ]; then',
                f'  reorder_policy_before "${{{late_var}}}" "${{{early_var}}}"',
                "fi",
            ]
        )

    lines.append(END_POLICY_REORDER)
    return "\n".join(lines)


def render_apply_block(manifest: dict[str, Any]) -> str:
    dns = manifest["dns_bypass"]["domains"]
    discord = manifest["pbr_overrides"]["discord"]["domains"]
    destiny = manifest["pbr_overrides"]["destiny_auth"]["domains"]
    baseline = manifest["pbr_baseline"]

    lines = [
        BEGIN_APPLY,
        "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
    ]
    for key in ("steam_auth", "steam_cdn", "nexus", "ru_local", "lib_ddg", "warframe"):
        lines.append(shell_list(baseline_var_name(key), baseline[key]["domains"]))
        lines.append("")

    lines.extend(
        [
            shell_list("DISCORD_DNS", [d for d in dns if d.startswith("discord")]),
            "",
            shell_list("DISCORD_DOMAINS", discord),
            "",
            "# Destiny login / TAPIR bypass (CIS geo-block at auth only):",
            "# https://github.com/Flowseal/zapret-discord-youtube/discussions/6033",
            shell_list("DESTINY_DOMAINS", destiny),
            END_APPLY,
        ]
    )
    return "\n".join(lines)


def ip_suffix(ip: str) -> str:
    return ip.rsplit(".", 1)[-1]


def render_zapret_devices_block(manifest: dict[str, Any]) -> str:
    zb = manifest["zapret_bypass"]
    lines = [
        BEGIN_ZAPRET_DEVICES,
        "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
    ]

    ps = zb.get("phoneserver_wlan", {})
    for src in ps.get("src", []):
        suffix = ip_suffix(src)
        lines.extend(
            [
                f"# phoneserver wlan {src}: {ps.get('reason', '')}",
                f"nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-{suffix} || \\",
                f"    nft insert rule inet zapret postnat ct original ip saddr {src} return comment zapret-ct-bypass-{suffix}",
                f"nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-{suffix}-pre || \\",
                f"    nft insert rule inet zapret prenat ct reply ip daddr {src} return comment zapret-ct-bypass-{suffix}-pre",
                "",
            ]
        )

    eth = zb.get("pundef_pc_eth_tcp", {})
    for src in eth.get("src", []):
        suffix = ip_suffix(src)
        lines.extend(
            [
                f"# pundef-pc eth {src} TCP bypass: {eth.get('reason', '')}",
                f'delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-{suffix}"',
                f'delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-{suffix}-pre"',
                f"nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-{suffix}-tcp || \\",
                f"    nft insert rule inet zapret postnat ct original ip saddr {src} meta l4proto tcp return comment zapret-ct-bypass-{suffix}-tcp",
                f"nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-{suffix}-pre-tcp || \\",
                f"    nft insert rule inet zapret prenat ct reply ip daddr {src} meta l4proto tcp return comment zapret-ct-bypass-{suffix}-pre-tcp",
                "",
            ]
        )

    wlan = zb.get("pundef_pc_wlan_no_blanket_bypass", {})
    for src in wlan.get("src", []):
        suffix = ip_suffix(src)
        lines.extend(
            [
                f"# pundef-pc wlan {src}: no blanket bypass — {wlan.get('reason', '')}",
                f'delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-{suffix}"',
                f'delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-{suffix}-pre"',
                f'delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-{suffix}-tcp"',
                f'delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-{suffix}-pre-tcp"',
                "",
            ]
        )

    xm = zb.get("xiaomi_13t_pro", {})
    for src in xm.get("src", []):
        suffix = ip_suffix(src)
        lines.extend(
            [
                f"# xiaomi-13t-pro {src}: {xm.get('reason', '')}",
                f"nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-{suffix} || \\",
                f"    nft insert rule inet zapret postnat ct original ip saddr {src} return comment zapret-ct-bypass-{suffix}",
                f"nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-{suffix}-pre || \\",
                f"    nft insert rule inet zapret prenat ct reply ip daddr {src} return comment zapret-ct-bypass-{suffix}-pre",
                "",
            ]
        )

    srv = zb.get("srv_subnet", {})
    for src in srv.get("src", []):
        lines.extend(
            [
                f"# srv subnet {src}: {srv.get('reason', '')}",
                "nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-srv || \\",
                f"    nft insert rule inet zapret postnat ct original ip saddr {src} return comment zapret-ct-bypass-srv",
                "nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-srv-pre || \\",
                f"    nft insert rule inet zapret prenat ct reply ip daddr {src} return comment zapret-ct-bypass-srv-pre",
                "",
            ]
        )

    lines.append(END_ZAPRET_DEVICES)
    return "\n".join(lines)


def render_zapret_block(manifest: dict[str, Any]) -> str:
    destiny = manifest["zapret_bypass"]["destiny_activity"]
    nets = ", ".join(destiny["dst"])
    forbidden = ", ".join(destiny["forbidden"])

    return "\n".join(
        [
            BEGIN_ZAPRET,
            "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
            "# Destiny activity servers must bypass nfqws; Discord voice must remain outside this bypass.",
            f"# Forbidden in Destiny bypass: {forbidden}",
            f'DESTINY_NETS="{{ {nets} }}"',
            END_ZAPRET,
        ]
    )


def render_zapret_sdr_block(manifest: dict[str, Any]) -> str:
    sdr = manifest["zapret_bypass"]["destiny_steam_sdr"]
    clients = " ".join(sdr["src"])
    forbidden = sdr["forbidden"][0] if sdr.get("forbidden") else "104.29.154.0/24"
    dport = sdr.get("udp_dport", "27000-27200")

    return "\n".join(
        [
            BEGIN_ZAPRET_SDR,
            "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
            f'STEAM_SDR_CLIENTS="{clients}"',
            f'STEAM_SDR_UDP_DPORT="{dport}"',
            f'STEAM_SDR_FORBIDDEN="{forbidden}"',
            END_ZAPRET_SDR,
        ]
    )


def render_login_constants_block(manifest: dict[str, Any]) -> str:
    modes = manifest["destiny_modes"]
    login = modes["login"]
    clients = manifest["clients"]["pundef_pc"]
    static_ips = " ".join(login.get("static_ips", []))

    return "\n".join(
        [
            BEGIN_LOGIN,
            "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
            f'FLAG="{modes["flag"]}"',
            f'LOGIN_STEAM_NAME_TEMPLATE="{login["steam_policy"]["name_template"]}"',
            f'LOGIN_FULL_NAME_TEMPLATE="{login["full_tunnel"]["name_template"]}"',
            f'LOGIN_STATIC_IPS="{static_ips}"',
            f'PC_ETH="{clients["lan"][0]}"',
            f'PC_WIFI="{clients["lan"][1]}"',
            END_LOGIN,
        ]
    )


def render_python_tuple(name: str, values: list[str]) -> str:
    if not values:
        return f"{name} = ()"
    if len(values) == 1:
        return f'{name} = ("{values[0]}",)'
    lines = [f"{name} = ("]
    for value in values:
        lines.append(f'    "{value}",')
    lines.append(")")
    return "\n".join(lines)


def render_check_block(manifest: dict[str, Any]) -> str:
    check = manifest["check_expectations"]
    zapret_nets = manifest["zapret_bypass"]["destiny_activity"]["dst"]

    lines = [
        BEGIN_CHECK,
        "# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.",
        render_python_tuple("CHECK_REQUIRED_POLICIES_NORMAL", check["required_policies_normal"]),
        render_python_tuple("CHECK_DNS_RESOLVE_HOSTS", check["dns_resolve_hosts"]),
        render_python_tuple("CHECK_DESTINY_NO_A", check["destiny_no_a_records"]),
        f'CHECK_STEAM_ROUTE_TEST_IP = "{check["steam_route_test_ip"]}"',
        render_python_tuple("CHECK_ZAPRET_DESTINY_NETS", zapret_nets),
        f'CHECK_STEAM_AUTH_ROUTE_TEST_IP = "{check.get("steam_auth_route_test_ip", "199.165.136.100")}"',
        END_CHECK,
    ]
    return "\n".join(lines)


def extract_block(text: str, begin: str, end: str) -> str | None:
    start = text.find(begin)
    finish = text.find(end)
    if start == -1 or finish == -1 or finish < start:
        return None
    finish += len(end)
    return text[start:finish]


def replace_block(text: str, begin: str, end: str, new_block: str) -> str:
    current = extract_block(text, begin, end)
    if current is None:
        raise ValueError(f"missing generated block: {begin}")
    return text.replace(current, new_block, 1)


def write_outputs(out_dir: Path, blocks: dict[str, str]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, content in blocks.items():
        (out_dir / name).write_text(content + "\n", encoding="utf-8")


def check_block(path: Path, begin: str, end: str, expected: str, failures: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    current = extract_block(text, begin, end)
    label = path.name
    if current is None:
        failures.append(f"{label}: generated block is missing ({begin})")
    elif current.strip() != expected.strip():
        failures.append(f"{label}: generated block differs from manifest ({begin})")


def check_blocks(targets: list[tuple[str, Path, str, str]]) -> int:
    failures: list[str] = []
    for expected, path, begin, end in targets:
        check_block(path, begin, end, expected, failures)

    if failures:
        print("FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("Generated blocks match config/openwrt/overrides.json.")
    return 0


def write_blocks(targets: list[tuple[str, Path, str, str]]) -> None:
    for expected, path, begin, end in targets:
        text = path.read_text(encoding="utf-8")
        path.write_text(replace_block(text, begin, end, expected) + "\n", encoding="utf-8")
        print(f"Updated {path.relative_to(ROOT)}")


def build_blocks(manifest: dict[str, Any]) -> dict[str, str]:
    return {
        "apply_const": render_apply_constants_block(manifest),
        "apply": render_apply_block(manifest),
        "policy_reorder": render_policy_reorder_block(manifest),
        "zapret_devices": render_zapret_devices_block(manifest),
        "zapret": render_zapret_block(manifest),
        "zapret_sdr": render_zapret_sdr_block(manifest),
        "login": render_login_constants_block(manifest),
        "check": render_check_block(manifest),
    }


def block_targets(blocks: dict[str, str]) -> list[tuple[str, Path, str, str]]:
    apply_sh = SCRIPTS / "apply-pundef-pc-routes.sh"
    zapret_sh = SCRIPTS / "custom.bypass_devices.sh"
    return [
        (blocks["apply_const"], apply_sh, BEGIN_APPLY_CONST, END_APPLY_CONST),
        (blocks["apply"], apply_sh, BEGIN_APPLY, END_APPLY),
        (blocks["policy_reorder"], apply_sh, BEGIN_POLICY_REORDER, END_POLICY_REORDER),
        (blocks["zapret_devices"], zapret_sh, BEGIN_ZAPRET_DEVICES, END_ZAPRET_DEVICES),
        (blocks["zapret"], zapret_sh, BEGIN_ZAPRET, END_ZAPRET),
        (blocks["zapret_sdr"], zapret_sh, BEGIN_ZAPRET_SDR, END_ZAPRET_SDR),
        (blocks["login"], SCRIPTS / "destiny-login-mode.sh", BEGIN_LOGIN, END_LOGIN),
        (blocks["check"], SCRIPTS / "check_gaming_pc_routes.py", BEGIN_CHECK, END_CHECK),
        (blocks["check"], SCRIPTS / "routing_status.py", BEGIN_CHECK, END_CHECK),
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--dry-run", action="store_true", help="Print generated blocks to stdout")
    parser.add_argument("--check", action="store_true", help="Verify generated blocks embedded in scripts")
    parser.add_argument("--write", action="store_true", help="Write generated blocks into repo scripts")
    parser.add_argument("--out-dir", type=Path, help="Write generated blocks into a review directory")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    blocks = build_blocks(manifest)
    targets = block_targets(blocks)

    if args.check:
        return check_blocks(targets)

    if args.write:
        write_blocks(targets)
        return 0

    if args.out_dir:
        write_outputs(
            args.out_dir,
            {
                "apply-pundef-pc-routes.generated.sh": blocks["apply"],
                "custom.bypass_devices.generated.sh": blocks["zapret"] + "\n\n" + blocks["zapret_sdr"],
                "destiny-login-mode.generated.sh": blocks["login"],
                "check_gaming_pc_routes.generated.py": blocks["check"],
            },
        )
        print(f"Wrote generated overrides to {args.out_dir}")
        return 0

    print("### apply-pundef-pc-routes.generated.sh")
    print(blocks["apply"])
    print()
    print("### custom.bypass_devices.generated.sh (destiny nets)")
    print(blocks["zapret"])
    print()
    print("### custom.bypass_devices.generated.sh (steam sdr)")
    print(blocks["zapret_sdr"])
    print()
    print("### destiny-login-mode.generated.sh")
    print(blocks["login"])
    print()
    print("### check_gaming_pc_routes.generated.py")
    print(blocks["check"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
