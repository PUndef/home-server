import {
  Button,
  Callout,
  Card,
  CardBody,
  CardHeader,
  Code,
  Grid,
  H1,
  H3,
  Pill,
  Row,
  Select,
  Stack,
  Stat,
  Table,
  Text,
  useCanvasState,
  useHostTheme,
} from "cursor/canvas";

type InterfaceId = "133" | "208" | "50.133";
type ModeId = "normal" | "login";
type UseCaseId =
  | "cold_login"
  | "tower_npc"
  | "activity_udp"
  | "discord_text"
  | "discord_voice"
  | "steam_cdn";

type LayerStatus = "ok" | "warn" | "fail" | "na";

type UseCase = {
  id: UseCaseId;
  label: string;
  mode: ModeId;
  layer: string;
  manifestKey: string;
  symptom: string;
  path: string[];
  interfaces: InterfaceId[];
};

const INTERFACES: { id: InterfaceId; label: string; note: string }[] = [
  { id: "133", label: ".133 eth lan", note: "TCP zapret bypass; podkop fake-IP" },
  { id: "208", label: ".208 Wi‑Fi", note: "No blanket zapret bypass; Discord voice" },
  { id: "50.133", label: ".50.133 srv", note: "Catch-all srv default via awg2" },
];

const USE_CASES: UseCase[] = [
  {
    id: "cold_login",
    label: "Cold login / account select",
    mode: "login",
    layer: "pbr Steam → awg2",
    manifestKey: "destiny_modes.login",
    symptom: "centipede / не до аккаунта",
    path: ["Client", "DNS", "pbr", "awg2"],
    interfaces: ["133", "208", "50.133"],
  },
  {
    id: "cold_login",
    label: "Cold login (wrong mode)",
    mode: "normal",
    layer: "pbr Steam → WAN",
    manifestKey: "pbr_baseline.steam",
    symptom: "не до аккаунта в normal",
    path: ["Client", "DNS", "pbr", "WAN"],
    interfaces: ["133", "208", "50.133"],
  },
  {
    id: "tower_npc",
    label: "Tower / NPC interact",
    mode: "normal",
    layer: "zapret + TCP 7500",
    manifestKey: "destiny_activity",
    symptom: "cabbage / NPC dead",
    path: ["Client", "zapret", "WAN"],
    interfaces: ["208", "133"],
  },
  {
    id: "activity_udp",
    label: "Activity UDP / lost sector",
    mode: "normal",
    layer: "zapret DESTINY_NETS + SDR",
    manifestKey: "destiny_activity + destiny_steam_sdr",
    symptom: "cabbage / currant",
    path: ["Client", "zapret", "WAN"],
    interfaces: ["208", "133"],
  },
  {
    id: "discord_text",
    label: "Discord text / gateway",
    mode: "normal",
    layer: "pbr → awg2",
    manifestKey: "pbr_overrides.discord",
    symptom: "gateway fail",
    path: ["Client", "DNS", "pbr", "awg2"],
    interfaces: ["133", "208", "50.133"],
  },
  {
    id: "discord_voice",
    label: "Discord voice UDP",
    mode: "normal",
    layer: "zapret ON (no bypass 104.29.154/24)",
    manifestKey: "forbidden 104.29.154/24",
    symptom: "voice broken if bypassed",
    path: ["Client", "zapret", "WAN"],
    interfaces: ["208", "133"],
  },
  {
    id: "steam_cdn",
    label: "Steam CDN downloads",
    mode: "normal",
    layer: "pbr → WAN",
    manifestKey: "pbr_baseline.steam",
    symptom: "slow via tunnel",
    path: ["Client", "pbr", "WAN"],
    interfaces: ["133", "208", "50.133"],
  },
];

const LAST_CHECK = {
  timestamp: "2026-06-30 post-ACT",
  mode: "normal" as ModeId,
  steamPolicy: "pundef-pc steam via wan",
  loginFlag: "absent",
  towerNpc: "OK (user verify)",
  warnings: [
    "normal mode + cold Destiny login risk",
    "workvpn DNS /kpb.lt/10.0.160.1 missing (known drift)",
  ],
};

const LAYER_CHECKS: Record<string, { status: LayerStatus; detail: string }> = {
  pbr: { status: "ok", detail: "All baseline + Discord/Destiny policies present" },
  zapret: { status: "ok", detail: "DESTINY_NETS + SDR + device bypass on router" },
  dns: { status: "ok", detail: "Discord/Bungie/2GIS bypass → 8.8.8.8" },
  podkop: { status: "na", detail: "Dynamic lists — not in manifest" },
  workvpn: { status: "warn", detail: "Up; DNS drift /kpb.lt/10.0.160.1" },
  hash: { status: "ok", detail: "Repo /opt sha256 match after ACT" },
};

function statusTone(status: LayerStatus): "success" | "warning" | "danger" | "neutral" {
  if (status === "ok") return "success";
  if (status === "warn") return "warning";
  if (status === "fail") return "danger";
  return "neutral";
}

function statusLabel(status: LayerStatus): string {
  if (status === "ok") return "OK";
  if (status === "warn") return "WARN";
  if (status === "fail") return "FAIL";
  return "N/A";
}

export default function OpenWrtRoutingExplorer() {
  const theme = useHostTheme();
  const [iface, setIface] = useCanvasState<InterfaceId>("iface", "208");
  const [mode, setMode] = useCanvasState<ModeId>("mode", "normal");
  const [useCase, setUseCase] = useCanvasState<UseCaseId>("useCase", "tower_npc");

  const activeCases = USE_CASES.filter(
    (item) =>
      item.id === useCase &&
      item.mode === mode &&
      item.interfaces.includes(iface),
  );
  const activeCase = activeCases[0] ?? USE_CASES.find((item) => item.id === useCase);
  const activePath = activeCase?.path ?? ["Client", "DNS", "pbr", "zapret", "Out"];

  const pathNodes = ["Client", "DNS", "pbr", "podkop", "zapret", "WAN", "awg2", "workvpn"];
  const outTargets = ["WAN", "awg2", "workvpn"];

  return (
    <Stack gap={16} style={{ padding: 16, color: theme.foreground }}>
      <Stack gap={4}>
        <H1>OpenWrt pundef-pc routing explorer</H1>
        <Text style={{ color: theme.mutedForeground }}>
          Manifest-first path visualization · last check: {LAST_CHECK.timestamp}
        </Text>
      </Stack>

      <Callout tone="warning">
        Green infrastructure checks do not guarantee Destiny cold login OK. In normal mode Steam auth
        may still exit via WAN — use apply_overrides.py --mode login before cold start.
      </Callout>

      <Grid columns={3} gap={12}>
        <Stat label="Router mode" value={LAST_CHECK.mode} tone="neutral" />
        <Stat label="Steam policy" value={LAST_CHECK.steamPolicy} tone="success" />
        <Stat label="Tower NPC (last run)" value={LAST_CHECK.towerNpc} tone="success" />
      </Grid>

      <Card>
        <CardHeader title="Controls" />
        <CardBody>
          <Grid columns={3} gap={12}>
            <Stack gap={6}>
              <Text weight="semibold">Interface</Text>
              <Select
                value={iface}
                onChange={(value) => setIface(value as InterfaceId)}
                options={INTERFACES.map((item) => ({
                  value: item.id,
                  label: item.label,
                }))}
              />
              <Text style={{ color: theme.mutedForeground, fontSize: 12 }}>
                {INTERFACES.find((item) => item.id === iface)?.note}
              </Text>
            </Stack>
            <Stack gap={6}>
              <Text weight="semibold">Destiny mode</Text>
              <Select
                value={mode}
                onChange={(value) => setMode(value as ModeId)}
                options={[
                  { value: "normal", label: "normal (baseline)" },
                  { value: "login", label: "login (auth tunnel)" },
                ]}
              />
            </Stack>
            <Stack gap={6}>
              <Text weight="semibold">Use case</Text>
              <Select
                value={useCase}
                onChange={(value) => setUseCase(value as UseCaseId)}
                options={[
                  { value: "cold_login", label: "Cold login" },
                  { value: "tower_npc", label: "Tower / NPC" },
                  { value: "activity_udp", label: "Activity UDP" },
                  { value: "discord_text", label: "Discord text" },
                  { value: "discord_voice", label: "Discord voice" },
                  { value: "steam_cdn", label: "Steam CDN" },
                ]}
              />
            </Stack>
          </Grid>
        </CardBody>
      </Card>

      {activeCase ? (
        <Card>
          <CardHeader
            title={`Active path: ${activeCase.label}`}
            trailing={<Pill tone={mode === "login" ? "warning" : "neutral"}>{mode}</Pill>}
          />
          <CardBody>
            <Stack gap={8}>
              <Text>
                Layer: <Code>{activeCase.layer}</Code> · manifest:{" "}
                <Code>{activeCase.manifestKey}</Code>
              </Text>
              <Text style={{ color: theme.mutedForeground }}>
                Symptom if broken: {activeCase.symptom}
              </Text>
              <Row gap={8} wrap>
                {pathNodes.map((node) => {
                  const inPath = activePath.includes(node);
                  const isOut = outTargets.includes(node) && activePath.includes(node);
                  if (!inPath && !["Client", "DNS"].includes(node) && node !== "podkop") {
                    if (node === "podkop" && !activePath.includes("podkop")) return null;
                  }
                  const show =
                    inPath ||
                    (node === "Client" && activePath.includes("Client")) ||
                    (node === "DNS" && activePath.includes("DNS")) ||
                    (node === "podkop" && activePath.includes("podkop"));
                  if (!show && node !== "Client") return null;
                  return (
                    <Pill key={node} tone={inPath || isOut ? "accent" : "neutral"}>
                      {node}
                      {inPath && activePath.indexOf(node) < activePath.length - 1 ? " →" : ""}
                    </Pill>
                  );
                })}
              </Row>
            </Stack>
          </CardBody>
        </Card>
      ) : (
        <Callout tone="neutral">
          Selected use case / mode / interface combination has no mapped path. Try normal + .208 for
          tower/NPC.
        </Callout>
      )}

      <Card>
        <CardHeader title="Layer status (last validator run)" />
        <CardBody padding={0}>
          <Table
            columns={[
              { key: "layer", header: "Layer" },
              { key: "status", header: "Status" },
              { key: "detail", header: "Detail" },
            ]}
            rows={Object.entries(LAYER_CHECKS).map(([layer, check]) => ({
              layer,
              status: statusLabel(check.status),
              detail: check.detail,
              tone: statusTone(check.status),
            }))}
          />
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="All routing forks" />
        <CardBody padding={0}>
          <Table
            columns={[
              { key: "useCase", header: "Use case" },
              { key: "mode", header: "Mode" },
              { key: "layer", header: "Layer" },
              { key: "manifest", header: "Manifest" },
              { key: "symptom", header: "If broken" },
            ]}
            rows={USE_CASES.map((item, index) => ({
              key: String(index),
              useCase: item.label,
              mode: item.mode,
              layer: item.layer,
              manifest: item.manifestKey,
              symptom: item.symptom,
              tone: item.id === useCase && item.mode === mode ? "accent" : undefined,
            }))}
          />
        </CardBody>
      </Card>

      <Card>
        <CardHeader title="Commands" />
        <CardBody>
          <Stack gap={8}>
            <Stack gap={4}>
              <H3>Validate (read-only)</H3>
              <Code>py -3 scripts/openwrt/validate_overrides.py</Code>
              <Code>py -3 scripts/openwrt/check_gaming_pc_routes.py</Code>
            </Stack>
            <Stack gap={4}>
              <H3>Apply</H3>
              <Code>py -3 scripts/openwrt/apply_overrides.py --mode login</Code>
              <Code>py -3 scripts/openwrt/apply_overrides.py --mode normal</Code>
              <Code>py -3 scripts/openwrt/apply_overrides.py --mode status</Code>
            </Stack>
            <Row gap={8}>
              <Button
                onClick={() =>
                  navigator.clipboard?.writeText(
                    "py -3 scripts/openwrt/apply_overrides.py --mode normal",
                  )
                }
              >
                Copy normal apply
              </Button>
              <Button
                onClick={() =>
                  navigator.clipboard?.writeText(
                    "py -3 scripts/openwrt/apply_overrides.py --mode login",
                  )
                }
              >
                Copy login apply
              </Button>
            </Row>
          </Stack>
        </CardBody>
      </Card>

      {LAST_CHECK.warnings.length > 0 ? (
        <Card>
          <CardHeader title="Warnings from last run" />
          <CardBody>
            <Stack gap={6}>
              {LAST_CHECK.warnings.map((warning) => (
                <Text key={warning}>• {warning}</Text>
              ))}
            </Stack>
          </CardBody>
        </Card>
      ) : null}
    </Stack>
  );
}
