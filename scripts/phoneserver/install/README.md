# Первичная установка phoneserver (joyeuse / v25.06)

Скрипты **одноразовой** установки postmarketOS на Redmi Note 9 Pro. Повседневные операции — в [`../README.md`](../README.md).

Порядок шагов и контекст: [`docs/phoneserver/pmos-setup.md`](../../../docs/phoneserver/pmos-setup.md).

| Шаг | Скрипт |
| --- | --- |
| 1 | `pmbootstrap-init.exp` |
| 7 | `setup-ssh-key.sh` (в корне `phoneserver/`) |
| 8 | `enable-passwordless-doas.sh` |
| 9 | `resize-root.sh` |
| 10 | `lan-setup.sh` (после DHCP на eth0 через USB-Ethernet хаб) |

Edge-only fallback (не нужны на v25.06): `build-bootimg.sh`, `extract-kernel-from-zboot.py`, `flash-bootimg-via-ssh.sh`, `patch-pmbootstrap-bootsize.sh`.
