# `scripts/phoneserver/diag/` — диагностика, не для повседневной работы

Эти скрипты — артефакты разведки, когда мы выясняли что не так с зарядкой
и USB-C role на joyeuse. Полезны при настройке следующих phoneserver-узлов
с такими же или похожими симптомами.

| Скрипт | Что делает |
|---|---|
| `probe-power-supply.sh` | Дамп `/sys/class/power_supply/*` — статус батареи, USB-источника, writable-флаги, uevent. |
| `probe-charger.sh` | dmesg по charger/typec/pm6150, состояние type-c port, наличие qcom-charger-* модулей. |
| `probe-usb-roles.sh` | Какие sysfs-узлы для type-c есть и какие из них writable (на joyeuse `port_type`/`power_role` оказались read-only). |
| `flip-usbc-to-sink.sh` | Попытка переключить type-c port из source в sink через sysfs. **На joyeuse не работает** (драйвер `qcom,pmic-typec` не отдаёт writable хук) — оставлено как пример для будущих устройств. |

Ничего из этого не нужно запускать при штатной эксплуатации phoneserver.
