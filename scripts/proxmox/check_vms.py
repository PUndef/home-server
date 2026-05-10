"""Collect a fresh snapshot of Proxmox host + VM state.

Connects to the Proxmox host over SSH (same env vars as proxmox_exec.py)
and prints a human-readable report. Inside the VMs it uses
`qm guest exec <vmid> -- ...` and parses the JSON envelope returned by
the QEMU guest agent, so output looks like a normal terminal.

Use it before updating hardware-and-env.md or to do a quick post-change
sanity check.
"""

from __future__ import annotations

import json
import os
import re
import sys

import paramiko

DEFAULT_KEY_PATH = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)


def load_private_key(key_path: str) -> paramiko.PKey:
    last_error: Exception | None = None
    for cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        try:
            return cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last_error = exc
    raise last_error or paramiko.SSHException("Unsupported private key type")


def run(client: paramiko.SSHClient, command: str, timeout: int = 30) -> tuple[int, str, str]:
    _stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    rc = stdout.channel.recv_exit_status()
    return rc, out, err


def guest_exec(client: paramiko.SSHClient, vmid: int, inner: str, timeout: int = 30) -> str:
    """Run a shell snippet inside a VM through qm guest exec, return stdout.

    `inner` is wrapped in `bash -c`. We single-quote it on the host shell so
    that the inner snippet keeps its own quoting; if the snippet contains a
    literal single quote, it is escaped as '\\''.
    """
    safe = inner.replace("'", "'\\''")
    cmd = f"qm guest exec {vmid} -- bash -c '{safe}'"
    rc, out, err = run(client, cmd, timeout=timeout)
    if rc != 0 and not out:
        return f"<guest exec error (rc={rc}): {err.strip() or 'no stderr'}>"
    try:
        envelope = json.loads(out)
    except json.JSONDecodeError:
        return out.strip() or "<no output>"
    parts: list[str] = []
    if envelope.get("out-data"):
        parts.append(envelope["out-data"].rstrip("\n"))
    if envelope.get("err-data"):
        parts.append("[stderr]\n" + envelope["err-data"].rstrip("\n"))
    if envelope.get("exitcode") not in (None, 0):
        parts.append(f"[exit={envelope.get('exitcode')}]")
    return "\n".join(parts).strip()


def section(title: str) -> None:
    print()
    print("=" * 70)
    print(title)
    print("=" * 70)


def kv(label: str, value: str | None) -> None:
    if value is None:
        return
    cleaned = value.strip()
    if not cleaned:
        return
    print(f"  {label:<22} {cleaned}")


def grep_first(pattern: str, text: str) -> str | None:
    for line in text.splitlines():
        m = re.search(pattern, line)
        if m:
            return line.strip()
    return None


def collect_host(client: paramiko.SSHClient) -> None:
    section("HOST: pundef (Proxmox)")
    _, out, _ = run(client, "pveversion --verbose | head -3")
    kv("pveversion", out.splitlines()[0] if out.strip() else None)
    _, out, _ = run(client, "uname -r")
    kv("kernel", out.strip())
    _, out, _ = run(client, "lscpu")
    cpu_model: str | None = None
    cpu_logical: str | None = None
    for line in out.splitlines():
        if line.startswith("Model name:"):
            cpu_model = line.split(":", 1)[1].strip()
        elif line.startswith("CPU(s):"):
            cpu_logical = line.split(":", 1)[1].strip()
    kv("cpu model", cpu_model)
    kv("cpu logical", cpu_logical)
    _, out, _ = run(client, "free -h | awk 'NR==2{print $2,$3,$4,$7}'")
    parts = out.split()
    if len(parts) == 4:
        kv("ram total", parts[0])
        kv("ram used / free", f"{parts[1]} / {parts[2]} (avail {parts[3]})")
    _, out, _ = run(client, "df -h / | tail -1 | awk '{print $1,$2,$3,$5}'")
    parts = out.split()
    if len(parts) == 4:
        kv("rootfs", f"{parts[0]} {parts[2]}/{parts[1]} ({parts[3]} used)")
    _, out, _ = run(client, "lsblk -dno NAME,SIZE,MODEL | grep -v loop | head -3")
    if out.strip():
        kv("disks", out.strip().replace("\n", "\n" + " " * 24))
    _, out, _ = run(client, "uptime -p")
    kv("uptime", out.strip())
    _, out, _ = run(client, "ip -4 -br a | grep -v '^lo'")
    if out.strip():
        kv("network (host)", out.strip().replace("\n", "\n" + " " * 24))
    _, out, _ = run(client, "cat /etc/resolv.conf | grep -E '^(search|nameserver)'")
    if out.strip():
        kv("dns", out.strip().replace("\n", "\n" + " " * 24))
    _, out, _ = run(
        client,
        "curl -s -m 5 ifconfig.me; echo",
    )
    kv("egress public ip", out.strip())


def collect_vm_summary(client: paramiko.SSHClient, vmid: int) -> dict[str, str]:
    """Parse `qm config <vmid>` into a flat dict (one line per key)."""
    _, out, _ = run(client, f"qm config {vmid}")
    cfg: dict[str, str] = {}
    for line in out.splitlines():
        if ":" in line and not line.startswith(" "):
            key, _, value = line.partition(":")
            cfg[key.strip()] = value.strip()
    return cfg


def collect_vm(client: paramiko.SSHClient, vmid: int, label: str) -> None:
    section(f"VM {vmid}: {label}")
    cfg = collect_vm_summary(client, vmid)
    kv("name", cfg.get("name"))
    kv("status", run(client, f"qm status {vmid}")[1].strip())
    kv("cores / sockets", f"{cfg.get('cores', '?')} cores x {cfg.get('sockets', '1')} socket")
    kv("memory (MB)", cfg.get("memory"))
    if cfg.get("scsi0"):
        kv("disk scsi0", cfg["scsi0"])
    if cfg.get("efidisk0"):
        kv("disk efi", cfg["efidisk0"])
    kv("net0", cfg.get("net0"))
    kv("ostype / bios", f"{cfg.get('ostype', '?')} / {cfg.get('bios', '?')}")
    kv("agent", cfg.get("agent"))
    kv("onboot", cfg.get("onboot"))


def collect_nextcloud_vm(client: paramiko.SSHClient) -> None:
    section("VM 101 inside (Nextcloud, Debian)")
    snippet = (
        "echo '--- os ---'; "
        "grep PRETTY_NAME /etc/os-release || true; "
        "uname -r; uptime -p; "
        "echo '--- mem/disk ---'; "
        "free -h | head -2; "
        "df -h / | tail -1; "
        "echo '--- versions ---'; "
        "php -v 2>/dev/null | head -1; "
        "(mariadbd --version 2>/dev/null || mysqld --version 2>/dev/null) | head -1; "
        "(apache2 -v 2>/dev/null || nginx -v 2>&1) | head -1; "
        "docker --version 2>/dev/null | head -1; "
        "echo '--- nextcloud occ ---'; "
        "occ_path=$(find /var/www -maxdepth 3 -name occ -type f 2>/dev/null | head -1); "
        "echo \"occ at: $occ_path\"; "
        "if [ -n \"$occ_path\" ]; then "
        "  ncuser=$(stat -c %U \"$occ_path\"); "
        "  sudo -u \"$ncuser\" php \"$occ_path\" -V 2>/dev/null | head -1 || true; "
        "  sudo -u \"$ncuser\" php \"$occ_path\" status 2>/dev/null | head -10 || true; "
        "fi; "
        "echo '--- docker containers ---'; "
        "docker ps --format 'table {{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' 2>/dev/null || true; "
        "echo '--- letsencrypt cert ---'; "
        "certbot certificates 2>/dev/null | grep -E 'Certificate Name|Domains|Expiry|Subject Names' || "
        "  (echo '/etc/letsencrypt/live/' && ls -la /etc/letsencrypt/live/ 2>/dev/null); "
        "echo '--- certbot.timer ---'; "
        "systemctl list-timers certbot.timer --no-pager 2>/dev/null | head -3"
    )
    print(guest_exec(client, 101, snippet, timeout=60))


def collect_haos_vm(client: paramiko.SSHClient) -> None:
    section("VM 100 inside (Home Assistant OS)")
    # HAOS guest agent only ships a tiny busybox-like exec surface; many
    # standard binaries (hostname, free, df) are unavailable. We try cautiously.
    snippet = (
        "echo '--- os ---'; "
        "(cat /etc/os-release 2>/dev/null | grep -E PRETTY_NAME || echo '<no os-release>'); "
        "(uname -srm 2>/dev/null || true); "
        "(uptime 2>/dev/null || true); "
        "echo '--- mem ---'; "
        "(free -h 2>/dev/null | head -2 || cat /proc/meminfo 2>/dev/null | head -3); "
        "echo '--- disk ---'; "
        "(df -h /mnt/data 2>/dev/null || df -h / 2>/dev/null | tail -1); "
        "echo '--- ha-supervisor ---'; "
        "(curl -s -m 5 http://localhost:8123/api/ 2>/dev/null | head -1; echo); "
        "(curl -s -m 5 http://supervisor/info 2>/dev/null | head -1; echo); "
        "echo '--- ha core info via ha cli ---'; "
        "(ha core info 2>/dev/null | head -10 || echo '<no ha cli>')"
    )
    print(guest_exec(client, 100, snippet, timeout=60))


def main() -> int:
    host = os.environ.get("PROXMOX_HOST", "192.168.50.9")
    user = os.environ.get("PROXMOX_USER", "root")
    key_path = os.environ.get("PROXMOX_KEY", DEFAULT_KEY_PATH)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(host, username=user, pkey=load_private_key(key_path), timeout=10)
    except Exception as exc:  # noqa: BLE001
        print(f"Connection error: {exc}", file=sys.stderr)
        return 2

    try:
        collect_host(client)
        collect_vm(client, 100, "haos17.0 (Home Assistant OS)")
        collect_vm(client, 101, "nextcloud-vm (Debian)")
        collect_nextcloud_vm(client)
        collect_haos_vm(client)
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
