# Первичная установка phoneserver (legacy v25.06)

> **Статус:** archive — **не** для текущего узла  
> **Актуальный путь:** [migrate-v2512/README.md](../migrate-v2512/README.md) (v25.12 / 6.14.7-sm7125)

Историческая схема: pmaports **v25.06**, kernel sub-package `joyeuse_tianma`, Android boot.img в partition `boot`, OpenRC, пользователь `pmos`.

Edge-only fallback (не нужны на v25.06/v25.12 штатно): `build-bootimg.sh`, `extract-kernel-from-zboot.py`, `flash-bootimg-via-ssh.sh`, `patch-pmbootstrap-bootsize.sh`.

См. также [docs/phoneserver/pmos-setup.md](../../docs/phoneserver/pmos-setup.md) — раздел «Сделано (история)».
