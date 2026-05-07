"""Run a single shell command on OpenWrt over SSH (paramiko).

Environment: OPENWRT_HOST, OPENWRT_USER, OPENWRT_KEY.
Documented in router-openwrt-x3000t.md (repo root).
"""
import os
import sys
import paramiko


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
    if len(sys.argv) < 2:
        print("usage: python scripts/openwrt/openwrt_exec.py <command>")
        return 2

    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    user = os.environ.get("OPENWRT_USER", "root")
    key_path = os.environ.get("OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass")
    cmd = " ".join(sys.argv[1:])

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = load_private_key(key_path)
    client.connect(host, username=user, pkey=key, timeout=10)

    try:
        _stdin, stdout, stderr = client.exec_command(cmd, timeout=180)
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        if out:
            sys.stdout.buffer.write(out.encode("utf-8", errors="ignore"))
        if err:
            sys.stderr.buffer.write(err.encode("utf-8", errors="ignore"))
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
