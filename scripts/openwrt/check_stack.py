"""Validate current OpenWrt routing stack health over SSH.

Environment variables are the same as in openwrt_exec.py:
- OPENWRT_HOST (default: 192.168.1.1)
- OPENWRT_USER (default: root)
- OPENWRT_KEY  (default: C:\\Users\\PUndef-PC\\.ssh\\openwrt_ax300t_nopass)
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass

import paramiko

# Probes that may fail when VPS blocks AI from router-origin curl; do not fail the stack.
OPTIONAL_CHECK_NAMES = frozenset({"ai-targets-via-primary", "awg1-egress-backup"})


@dataclass
class CheckResult:
    group: str
    name: str
    ok: bool
    detail: str


class Style:
    def __init__(self) -> None:
        no_color = os.environ.get("NO_COLOR", "").strip() != ""
        self.enabled = sys.stdout.isatty() and not no_color
        self.reset = "\033[0m" if self.enabled else ""
        self.bold = "\033[1m" if self.enabled else ""
        self.dim = "\033[2m" if self.enabled else ""
        self.green = "\033[32m" if self.enabled else ""
        self.red = "\033[31m" if self.enabled else ""
        self.cyan = "\033[36m" if self.enabled else ""
        self.yellow = "\033[33m" if self.enabled else ""

    def color(self, text: str, color: str, bold: bool = False) -> str:
        if not self.enabled:
            return text
        prefix = ""
        if bold:
            prefix += self.bold
        prefix += color
        return f"{prefix}{text}{self.reset}"


class ProgressBar:
    def __init__(self, total: int, style: Style) -> None:
        self.total = max(total, 1)
        self.style = style
        self.width = 24
        self.active = sys.stdout.isatty()
        self.last_len = 0

    def update(self, current: int, label: str) -> None:
        if not self.active:
            return
        ratio = min(max(current / self.total, 0.0), 1.0)
        done = int(self.width * ratio)
        bar = "#" * done + "-" * (self.width - done)
        msg = f"[{bar}] {current:>2}/{self.total} {label}"
        self.last_len = len(msg)
        sys.stdout.write("\r" + self.style.color(msg, self.style.cyan))
        sys.stdout.flush()

    def finish(self) -> None:
        if not self.active:
            return
        sys.stdout.write("\n")
        sys.stdout.flush()


def run_command(client: paramiko.SSHClient, command: str, timeout: int = 30) -> tuple[int, str]:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    _ = stdin
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    code = stdout.channel.recv_exit_status()
    combined = (out + ("\n" + err if err else "")).strip()
    return code, combined


def run_check(
    client: paramiko.SSHClient,
    group: str,
    name: str,
    command: str,
    ok_hint: str,
) -> CheckResult:
    code, output = run_command(client, command)
    if code == 0:
        return CheckResult(group=group, name=name, ok=True, detail=ok_hint)

    short = " ".join(output.split())
    if len(short) > 180:
        short = short[:177] + "..."
    return CheckResult(group=group, name=name, ok=False, detail=short or "command failed")


def load_private_key(key_path: str) -> paramiko.PKey:
    last_error: Exception | None = None
    key_classes = (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey)
    for key_cls in key_classes:
        try:
            return key_cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last_error = exc

    raise last_error or paramiko.SSHException("Unsupported private key type")


def main() -> int:
    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    user = os.environ.get("OPENWRT_USER", "root")
    key_path = os.environ.get("OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        key = load_private_key(key_path)
        client.connect(host, username=user, pkey=key, timeout=10)
    except Exception as exc:  # noqa: BLE001
        print(f"Connection error: {exc}")
        return 2

    awg2_egress_probe = (
        "out=$(curl -4 -sS --connect-timeout 8 --max-time 15 --interface awg2 "
        "https://api.ipify.org); echo \"$out\"; "
        # expected egress IP for Neth VPS
        "[ \"$out\" = \"45.154.35.222\" ]"
    )
    workvpn_gitlab_probe = (
        "ip=$(nslookup gitlab.kpb.lt 192.168.1.1 | awk '/^Address: / {ip=$2} END {print ip}'); "
        "[ -n \"$ip\" ] || exit 1; "
        "ok=0; "
        "for i in 1 2 3; do "
        "out=$(curl -4 -L -k -sS --connect-timeout 8 --max-time 20 --interface vpn-workvpn "
        "--resolve \"gitlab.kpb.lt:443:$ip\" "
        "-o /dev/null -w 'code=%{http_code} remote=%{remote_ip} total=%{time_total}' "
        "https://gitlab.kpb.lt 2>&1); "
        "rc=$?; "
        "case \"$out\" in *code=000*) rc=1 ;; esac; "
        "if [ \"$rc\" = 0 ]; then echo \"gitlab.kpb.lt OK: $out\"; ok=1; break; fi; "
        "echo \"gitlab.kpb.lt attempt $i failed: $out\"; "
        "sleep 2; "
        "done; "
        "[ \"$ok\" = 1 ]"
    )
    ai_targets_probe = (
        "PRIMARY=$(uci -q get podkop.main.interface); "
        "case \"$PRIMARY\" in awg1|awg2) ;; *) PRIMARY=awg2 ;; esac; "
        "passed=0; "
        "for url in https://chatgpt.com https://claude.ai https://api.openai.com; do "
        "ok=0; "
        "for i in 1 2 3; do "
        "out=$(curl -4 -L -sS --connect-timeout 10 --max-time 25 --interface \"$PRIMARY\" "
        "-o /dev/null -w 'code=%{http_code} remote=%{remote_ip} total=%{time_total}' \"$url\" 2>&1); "
        "rc=$?; "
        "case \"$out\" in *code=000*) rc=1 ;; esac; "
        "if [ \"$rc\" = 0 ]; then echo \"$url OK: $out\"; ok=1; passed=$((passed+1)); break; fi; "
        "echo \"$url attempt $i failed: $out\"; "
        "sleep 2; "
        "done; "
        "done; "
        "echo \"AI probes passed: $passed/3 via $PRIMARY\"; "
        "[ \"$passed\" -ge 1 ]"
    )
    awg1_backup_egress_probe = (
        "out=$(curl -4 -sS --connect-timeout 5 --max-time 10 --interface awg1 "
        "-o /dev/null -w 'code=%{http_code}' https://1.1.1.1/cdn-cgi/trace 2>&1) || "
        "out=\"timeout or down\"; "
        "echo \"awg1 backup (optional): $out\"; "
        "true"
    )
    nextcloud_https_direct_probe = (
        "out=$(curl -4 -k -sS --connect-timeout 8 --max-time 15 "
        "-o /dev/null -w 'code=%{http_code} remote=%{remote_ip}' "
        "https://192.168.50.34/ 2>&1); "
        "echo \"$out\"; "
        "case \"$out\" in *code=2*|*code=3*) exit 0 ;; esac; "
        "exit 1"
    )
    nextcloud_https_via_domain_probe = (
        "ip=$(nslookup cloud-pundef.mooo.com 127.0.0.1 | awk '/^Address: /{print $2}' | head -1); "
        "echo \"cloud-pundef.mooo.com -> $ip\"; "
        "[ \"$ip\" = \"192.168.50.34\" ] || exit 1; "
        "out=$(curl -4 -k -sS --connect-timeout 8 --max-time 15 "
        "-o /dev/null -w 'code=%{http_code} remote=%{remote_ip}' "
        "https://cloud-pundef.mooo.com/ 2>&1); "
        "echo \"$out\"; "
        "case \"$out\" in *code=2*|*code=3*) exit 0 ;; esac; "
        "exit 1"
    )
    owncord_https_via_domain_probe = (
        "ip=$(nslookup owncord-pundef.mooo.com 127.0.0.1 | awk '/^Address: /{print $2}' | head -1); "
        "echo \"owncord-pundef.mooo.com -> $ip\"; "
        "[ \"$ip\" = \"192.168.50.34\" ] || exit 1; "
        "body=$(curl -4 -sS --connect-timeout 8 --max-time 15 "
        "https://owncord-pundef.mooo.com/api/health 2>&1) || "
        "body=$(curl -4 -k -sS --connect-timeout 8 --max-time 15 "
        "https://owncord-pundef.mooo.com/api/health 2>&1); "
        "echo \"$body\" | head -c 120; echo; "
        "echo \"$body\" | grep -q '\"ok\":true'"
    )
    owncord_https_edge_probe = (
        "body=$(curl -4 -sS --connect-timeout 8 --max-time 15 "
        "--resolve 'owncord-pundef.mooo.com:443:192.168.50.34' "
        "https://owncord-pundef.mooo.com/api/health 2>&1) || "
        "body=$(curl -4 -k -sS --connect-timeout 8 --max-time 15 "
        "--resolve 'owncord-pundef.mooo.com:443:192.168.50.34' "
        "https://owncord-pundef.mooo.com/api/health 2>&1); "
        "echo \"$body\" | head -c 120; echo; "
        "echo \"$body\" | grep -q '\"ok\":true'"
    )
    # HAOS VM 100 остановлен (onboot 0) — проба отключена, раскомментировать при включении:
    # haos_tcp_probe = (
    #     "code=$(curl -k -sS -o /dev/null -m 5 -w '%{http_code}' "
    #     "http://192.168.50.51:8123/); echo \"haos-8123 code=$code\"; "
    #     "[ \"$code\" != \"000\" ]"
    # )
    proxmox_tcp_probe = (
        "code=$(curl -k -sS -o /dev/null -m 5 -w '%{http_code}' "
        "https://192.168.50.9:8006/); echo \"pve-8006 code=$code\"; "
        "[ \"$code\" != \"000\" ]"
    )
    vm_isolation_probe = (
        # srv may forward only into primary tunnel (ai-frontend ghcr); not backup or workvpn
        "PRIMARY=$(uci -q get podkop.main.interface); "
        "case \"$PRIMARY\" in awg1|awg2) ;; *) PRIMARY=awg2 ;; esac; "
        "BACKUP=awg1; [ \"$PRIMARY\" = awg1 ] && BACKUP=awg2; "
        "leaks=$(nft list chain inet fw4 forward_srv 2>/dev/null "
        "| grep -E \"accept_to_($BACKUP|workvpn)\"); "
        "if [ -n \"$leaks\" ]; then echo \"LEAK: $leaks\"; exit 1; fi; "
        "echo \"srv-isolated-except-optional-$PRIMARY\""
    )

    checks = [
        (
            "services",
            "default-route-wan",
            "ip route | grep -q '^default via .* dev wan'",
            "default route via wan",
        ),
        (
            "services",
            "sing-box-running",
            "/etc/init.d/sing-box status | grep -q '^running$'",
            "sing-box is running",
        ),
        (
            "services",
            "podkop-enabled",
            "/usr/bin/podkop get_status | grep -q '\"enabled\":1'",
            "podkop enabled",
        ),
        (
            "services",
            "podkop-subnets",
            "nft list set inet PodkopTable podkop_subnets | grep -q 'elements = {'",
            "podkop_subnets set is populated",
        ),
        (
            "services",
            "zapret-running",
            "/etc/init.d/zapret status | grep -q '^running$'",
            "zapret is running",
        ),
        (
            "routing",
            "pbr-awg2-primary-rule",
            "ip rule | grep -q 'fwmark 0x40000/0xff0000 lookup pbr_awg2'",
            "pbr primary (awg2) fwmark rule exists",
        ),
        (
            "routing",
            "pbr-policy-nft",
            "PRIMARY=$(uci -q get podkop.main.interface); "
            "case \"$PRIMARY\" in awg1|awg2) ;; *) PRIMARY=awg2 ;; esac; "
            "nft list chain inet fw4 pbr_prerouting | grep -q \"AI Tools via $PRIMARY\"",
            "pbr AI policy chain matches podkop.main.interface",
        ),
        (
            "routing",
            "default-route-test",
            "ip route get 9.9.9.9 | grep -q ' dev wan '",
            "unmarked test route goes via wan",
        ),
        (
            "routing",
            "pbr-mark-route-test",
            "PRIMARY=$(uci -q get podkop.main.interface); "
            "case \"$PRIMARY\" in awg2) ip route get 9.9.9.9 mark 0x40000 | grep -q ' dev awg2 ' ;; "
            "awg1) ip route get 9.9.9.9 mark 0x20000 | grep -q ' dev awg1 ' ;; "
            "*) exit 1 ;; esac",
            "pbr mark route uses primary tunnel device",
        ),
        (
            "routing",
            "awg2-running",
            "ifstatus awg2 | grep -q '\"up\": true'",
            "awg2 (Neth) interface is up",
        ),
        (
            "routing",
            "pbr-awg2-rule",
            "ip rule | grep -q 'fwmark 0x40000/0xff0000 lookup pbr_awg2'",
            "pbr awg2 fwmark rule exists",
        ),
        (
            "routing",
            "pbr-awg2-table",
            "ip route show table pbr_awg2 | grep -q 'default via .* dev awg2'",
            "pbr_awg2 default route goes via awg2",
        ),
        (
            "routing",
            "awg2-firewall-zone",
            "uci show firewall | grep -q \"name='awg2'\" && uci show firewall | grep -q 'awg2-lan'",
            "awg2 firewall zone and lan->awg2 forwarding exist",
        ),
        (
            "routing",
            "workvpn-running",
            "ifstatus workvpn | grep -q '\"up\": true'",
            "workvpn interface is up",
        ),
        (
            "routing",
            "pbr-workvpn-rule",
            "ip rule | grep -q 'lookup pbr_workvpn'",
            "pbr workvpn rule exists",
        ),
        (
            "routing",
            "pbr-workvpn-table",
            "ip route show table pbr_workvpn | grep -q 'default via .* dev vpn-workvpn'",
            "pbr_workvpn default route goes via vpn-workvpn",
        ),
        (
            "routing",
            "corp-workvpn-mark-route",
            "ifstatus workvpn | grep -q '\"up\": true' && "
            "ip route get 10.0.17.5 mark 0x30000 2>/dev/null | grep -q 'dev vpn-workvpn'",
            "marked corp traffic (fwmark 0x30000) routes via vpn-workvpn",
        ),
        (
            "routing",
            "workvpn-policy-nft",
            "nft list chain inet fw4 pbr_prerouting | grep -q 'paul-mac kpb via workvpn' "
            "&& nft list chain inet fw4 pbr_prerouting | grep -q 'pundef-pc kpb via workvpn'",
            "workvpn policies for paul-mac and pundef-pc are active",
        ),
        (
            "zapret-bypass",
            "zapret-bypass-phoneserver-postnat",
            "nft list chain inet zapret postnat | grep -q 'zapret-ct-bypass-227'",
            "phoneserver bypass postnat rule exists (.227)",
        ),
        (
            "zapret-bypass",
            "zapret-bypass-phoneserver-prenat",
            "nft list chain inet zapret prenat | grep -q 'zapret-ct-bypass-227-pre'",
            "phoneserver bypass prenat rule exists (.227)",
        ),
        (
            "zapret-bypass",
            "zapret-bypass-pundef-pc-postnat",
            "nft list chain inet zapret postnat | grep -q 'zapret-ct-bypass-133'",
            "pundef-pc bypass postnat rule exists (.133)",
        ),
        (
            "zapret-bypass",
            "zapret-bypass-pundef-pc-prenat",
            "nft list chain inet zapret prenat | grep -q 'zapret-ct-bypass-133-pre'",
            "pundef-pc bypass prenat rule exists (.133)",
        ),
        (
            "zapret-bypass",
            "zapret-bypass-srv-postnat",
            "nft list chain inet zapret postnat | grep -q 'zapret-ct-bypass-srv'",
            "srv subnet bypass postnat rule exists (192.168.50.0/24)",
        ),
        (
            "zapret-bypass",
            "zapret-bypass-srv-prenat",
            "nft list chain inet zapret prenat | grep -q 'zapret-ct-bypass-srv-pre'",
            "srv subnet bypass prenat rule exists (192.168.50.0/24)",
        ),
        (
            "active-probes",
            "dns-resolve-via-router",
            "nslookup cloud-pundef.mooo.com 192.168.1.1 | grep -q 'Address:'",
            "router DNS resolves test domain",
        ),
        (
            "active-probes",
            "wan-https-probe",
            "code=$(curl -sS --connect-timeout 8 -o /dev/null -w '%{http_code}' https://example.com); [ \"$code\" != \"000\" ]",
            "HTTPS via default WAN path is reachable",
        ),
        (
            "active-probes",
            "awg2-egress-probe",
            awg2_egress_probe,
            "HTTPS egress via awg2 lands on Neth IP 45.154.35.222",
        ),
        (
            "optional-probes",
            "awg1-egress-backup",
            awg1_backup_egress_probe,
            "awg1 backup tunnel status (informational)",
        ),
        (
            "optional-probes",
            "ai-targets-via-primary",
            ai_targets_probe,
            "AI via primary from router (optional; LAN clients use pbr marks)",
        ),
        (
            "active-probes",
            "workvpn-dns-gitlab",
            "nslookup gitlab.kpb.lt 192.168.1.1 | grep -q 'Address:'",
            "router DNS resolves gitlab.kpb.lt",
        ),
        (
            "active-probes",
            "workvpn-gitlab-via-tunnel",
            workvpn_gitlab_probe,
            "gitlab.kpb.lt is reachable via workvpn",
        ),
        (
            "vm-services",
            "srv-zone-up",
            "ifstatus srv | grep -q '\"up\": true' && ip -br a show dev lan2 | grep -q ' UP '",
            "srv interface (lan2) is up",
        ),
        (
            "vm-services",
            "srv-vms-reachable",
            "ping -c 1 -W 2 192.168.50.34 >/dev/null 2>&1 "
            "&& ping -c 1 -W 2 192.168.50.35 >/dev/null 2>&1",
            "srv VMs nextcloud (.34) and static-sites (.35) respond to ping (HAOS off)",
        ),
        (
            "vm-services",
            "owncord-backend-lan",
            "body=$(curl -4 -sS --connect-timeout 5 --max-time 10 "
            "http://192.168.50.36:3001/api/health 2>&1); "
            "echo \"$body\" | head -c 80; echo; "
            "echo \"$body\" | grep -q '\"ok\":true'",
            "OwnCord backend http://192.168.50.36:3001/api/health returns ok",
        ),
        (
            "vm-services",
            "vm-isolation-from-tunnels",
            vm_isolation_probe,
            "no srv -> awg1/workvpn forwarding (awg2-only OK for ai-frontend ghcr)",
        ),
        (
            "vm-services",
            "split-horizon-cloud-pundef",
            "nslookup cloud-pundef.mooo.com 127.0.0.1 "
            "| awk '/^Address: /{print $2}' | grep -qx 192.168.50.34",
            "router DNS resolves cloud-pundef.mooo.com -> 192.168.50.34",
        ),
        (
            "vm-services",
            "split-horizon-owncord-pundef",
            "grep -q 'owncord-pundef.mooo.com/192.168.50.34' /etc/dnsmasq.conf "
            "&& nslookup owncord-pundef.mooo.com 127.0.0.1 "
            "| awk '/^Address: /{print $2}' | grep -qx 192.168.50.34",
            "dnsmasq + router DNS: owncord-pundef.mooo.com -> 192.168.50.34",
        ),
        (
            "vm-services",
            "nextcloud-port-forward-rules",
            "nft list chain inet fw4 dstnat_wan 2>/dev/null "
            "| grep -q 'Nextcloud-HTTP' "
            "&& nft list chain inet fw4 dstnat_wan "
            "| grep -q 'Nextcloud-HTTPS'",
            "wan -> 192.168.50.34 DNAT rules exist for 80 and 443",
        ),
        (
            "vm-services",
            "proxmox-host-pveui-tcp",
            proxmox_tcp_probe,
            "Proxmox web UI tcp/8006 reachable on 192.168.50.9",
        ),
        (
            "vm-services",
            "nextcloud-https-direct",
            nextcloud_https_direct_probe,
            "https://192.168.50.34/ answers (lan -> srv forwarding works)",
        ),
        (
            "vm-services",
            "nextcloud-https-by-domain",
            nextcloud_https_via_domain_probe,
            "https://cloud-pundef.mooo.com/ resolves to local IP and answers",
        ),
        (
            "vm-services",
            "owncord-https-by-domain",
            owncord_https_via_domain_probe,
            "https://owncord-pundef.mooo.com/api/health resolves locally and returns ok",
        ),
        (
            "vm-services",
            "owncord-https-edge-vhost",
            owncord_https_edge_probe,
            "Apache edge answers owncord vhost on 192.168.50.34 (/api/health ok)",
        ),
        # HAOS VM 100 остановлен — раскомментировать вместе с haos_tcp_probe:
        # (
        #     "vm-services",
        #     "haos-webui-tcp",
        #     haos_tcp_probe,
        #     "Home Assistant web UI tcp/8123 reachable on 192.168.50.51",
        # ),
        (
            "phoneserver",
            "phoneserver-dhcp-lease",
            "grep -qE 'dc:04:5a:58:5a:93.*192\\.168\\.50\\.127' /tmp/dhcp.leases",
            "phoneserver DHCP lease 192.168.50.127 is active",
        ),
        (
            "phoneserver",
            "phoneserver-ping",
            "ping -c 1 -W 3 192.168.50.127 >/dev/null 2>&1",
            "phoneserver responds to ping on 192.168.50.127",
        ),
        (
            "phoneserver",
            "phoneserver-kuma-http",
            "code=$(curl -sS -o /dev/null -m 5 -w '%{http_code}' http://192.168.50.35:3001/); "
            "echo \"kuma-3001 code=$code\"; "
            "[ \"$code\" != \"000\" ]",
            "Uptime Kuma http://192.168.50.35:3001/ answers",
        ),
    ]

    # Legacy checks kept for backward compatibility naming in reports.
    legacy_aliases = [
        (
            "legacy",
            "stack-basic-ready",
            "true",
            "legacy alias: use grouped checks above",
        ),
    ]
    checks.extend(legacy_aliases)

    style = Style()
    results: list[CheckResult] = []
    progress = ProgressBar(total=len(checks), style=style)
    for idx, (group, name, command, ok_hint) in enumerate(checks, start=1):
        progress.update(idx, name)
        result = run_check(client, group, name, command, ok_hint)
        results.append(result)
    progress.finish()

    client.close()

    failed = 0
    passed = 0
    current_group = ""
    name_width = max(len(r.name) for r in results) if results else 10
    for result in results:
        if result.group != current_group:
            current_group = result.group
            title = style.color(current_group.upper(), style.cyan, bold=True)
            print(f"\n{title}")
        optional = result.name in OPTIONAL_CHECK_NAMES
        if result.ok:
            status_colored = style.color("OK  ", style.green, bold=True)
        elif optional:
            status_colored = style.color("WARN", style.yellow, bold=True)
        else:
            status_colored = style.color("FAIL", style.red, bold=True)
        dots = "." * max(1, name_width - len(result.name) + 2)
        print(f"[{status_colored}] {result.name} {style.dim}{dots}{style.reset} {result.detail}")
        if result.ok:
            passed += 1
        elif optional:
            passed += 1
        else:
            failed += 1

    optional_warn = sum(1 for r in results if r.name in OPTIONAL_CHECK_NAMES and not r.ok)
    if failed:
        summary = f"Summary: {passed} passed, {failed} failed."
        print(f"\n{style.color(summary, style.red, bold=True)}")
        print(style.color("Tip: rerun after 30-60s if services were just restarted.", style.yellow))
        return 1

    summary = f"Summary: {passed} passed, 0 failed."
    if optional_warn:
        summary += f" ({optional_warn} optional WARN)"
    print(f"\n{style.color(summary, style.green, bold=True)}")
    print(style.color("Health check passed: routing stack looks healthy.", style.green))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
