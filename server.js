// kb-remote-ui server.
//
// Zero-dep Node HTTP server that exposes a JSON dashboard for the kb-remote /
// kb-dev workflow. Reads the same state file (~/.config/kb-remote/state.json),
// shells out to git / mutagen / ssh / launchctl, and serves a static SPA from
// ./public.
//
// Design notes
// ────────────
// • Source of truth lives on Mac:
//     ~/.config/kb-remote/state.json   — attached folders, ports, labels
//     `mutagen sync list`              — per-label sync health
//     `launchctl print gui/<uid>/...`  — autossh launchd agent state
//     `git -C <path> …`                — branch / commit for each Mac folder
//     `ssh kupi-remote tmux list-...`  — dev tmux sessions on remote WSL
// • All shell calls go through `spawn(cmd, [args...])` with an explicit argv
//   (no shell string), so paths from state.json can't escape into a command.
// • Action endpoints (POST /api/actions/*) accept a path, then validate it
//   against the current state file before invoking the corresponding kb-* CLI.
// • A background poller refreshes the cache every POLL_INTERVAL_MS so GET
//   /api/* returns immediately and we don't fan-out N ssh sessions per click.
//
// Config (env)
// ────────────
//   PORT            HTTP port (default 4747)
//   HOST            bind address (default 127.0.0.1; use 0.0.0.0 to expose)
//   KB_REMOTE_HOST  ssh host alias (default: kupi-remote, matches kb-remote)
//   KB_STATE_FILE   override state file path (default $XDG_CONFIG_HOME/...)
//   KB_MUTAGEN_BIN  mutagen binary
//   POLL_INTERVAL   poll period in ms (default 5000)

import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { readFile, readdir, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, dirname, extname, resolve, normalize, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

// ─── config ─────────────────────────────────────────────────────────────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = join(__dirname, "public");

const PORT = Number(process.env.PORT) || 4747;
const HOST = process.env.HOST || "127.0.0.1";
const POLL_INTERVAL_MS = Number(process.env.POLL_INTERVAL) || 5000;

const SSH_HOST = process.env.KB_REMOTE_HOST || "kupi-remote";
const STATE_FILE =
  process.env.KB_STATE_FILE ||
  join(
    process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
    "kb-remote",
    "state.json",
  );
const PLIST_LABEL = "com.kupibilet.kb-remote";

const MUTAGEN_BIN = (() => {
  if (process.env.KB_MUTAGEN_BIN) return process.env.KB_MUTAGEN_BIN;
  for (const c of [
    join(homedir(), ".local/bin/mutagen"),
    "/usr/local/bin/mutagen",
    "/opt/homebrew/bin/mutagen",
  ]) {
    if (existsSync(c)) return c;
  }
  return "mutagen";
})();

// kb-remote / kb-dev live in user-local bin by convention.
const KB_REMOTE_BIN = join(homedir(), ".local/bin/kb-remote");
const KB_DEV_BIN = join(homedir(), ".local/bin/kb-dev");

// Per-stack list of dev "variants" — different apps/whitelabels you can boot
// in the same attached folder (on its allocated port). Kept in-server (not in
// state.json) so it's trivially user-editable here and the frontend just
// renders what we ship. Keep `id` aligned with the values kb-dev accepts via
// `--variant`. `default: true` marks the one used when the user hits the
// primary "Start dev" button without a specific choice.
const VARIANTS = {
  "new-kupibilet": [
    { id: "kupibilet",    label: "kupibilet",    desc: "apps/kupibilet (main fronted)", default: true },
    { id: "sales",        label: "sales",        desc: "apps/sales" },
    { id: "seo-landings", label: "seo-landings", desc: "apps/seo-landings" },
    { id: "help",         label: "help",         desc: "apps/help" },
    { id: "blog",         label: "blog",         desc: "apps/blog" },
    { id: "price-map",    label: "price-map",    desc: "apps/price-map" },
    { id: "storybook",    label: "storybook",    desc: "apps/storybook (port shared)" },
  ],
  kupibilet: [
    { id: "kupibilet.ru", label: "kupibilet.ru", desc: "WHITE_LABEL=kupibilet.ru yarn express", default: true },
    { id: "kupicom.com",  label: "kupicom.com",  desc: "WHITE_LABEL=kupicom.com yarn express (verify script name)" },
  ],
};

function defaultVariant(stack) {
  return (VARIANTS[stack] || []).find((v) => v.default)?.id || null;
}

// Per-stack list of hostnames a single dev process answers on. new-kupibilet's
// next dev binds to 127.0.0.1 (via /etc/hosts → kupibilet.local / kupicom.local)
// and switches whitelabel based on the incoming Host header — so one process,
// two browser URLs. legacy kupibilet just uses localhost.
// Make sure the same hosts exist in your /etc/hosts pointing to 127.0.0.1.
const HOSTS = {
  "new-kupibilet": ["kupibilet.local", "kupicom.local"],
  kupibilet: ["localhost"],
};

function hostsFor(stack) {
  return HOSTS[stack] || ["localhost"];
}

// ─── attach naming convention + port allocator ──────────────────────────────
//
// Source of truth for both the basename pattern and the port ranges lives in
// the bash script ~/.local/bin/kb-remote (see `detect()` and `allocate_port`).
// We mirror it here strictly for *preview* in the attach form — the real
// `kb-remote attach` call will still pick the actual port. If these drift,
// the preview becomes wrong but attach itself stays correct.

const REPO_KUPI = "kupibilet.ru";
const REPO_NEW = "new-kupibilet.ru";

const PORT_RANGES = {
  kupibilet:       { main: 8443, wtStart: 8453, wtEnd: 8493 },
  "new-kupibilet": { main: 3000, wtStart: 3010, wtEnd: 3050 },
};

const DOCUMENTS_DIR = join(homedir(), "Documents");

/**
 * Classify a directory basename per kb-remote's `detect()`:
 *   kupibilet.ru                → { stack: "kupibilet",     isWorktree: false }
 *   kupibilet.ru-FOO            → { stack: "kupibilet",     isWorktree: true  }
 *   new-kupibilet.ru            → { stack: "new-kupibilet", isWorktree: false }
 *   new-kupibilet.ru-FOO        → { stack: "new-kupibilet", isWorktree: true  }
 *   anything else               → null
 */
function classifyBasename(base) {
  if (base === REPO_KUPI) return { stack: "kupibilet", isWorktree: false, parentRepo: REPO_KUPI };
  if (base === REPO_NEW) return { stack: "new-kupibilet", isWorktree: false, parentRepo: REPO_NEW };
  if (base.startsWith(REPO_KUPI + "-")) return { stack: "kupibilet", isWorktree: true, parentRepo: REPO_KUPI };
  if (base.startsWith(REPO_NEW + "-")) return { stack: "new-kupibilet", isWorktree: true, parentRepo: REPO_NEW };
  return null;
}

/** Mutagen-friendly label: kb-<basename with dots→dashes>. Must match kb-remote. */
function labelFor(base) {
  return "kb-" + base.replace(/\./g, "-");
}

/**
 * Re-implementation of `allocate_port` from kb-remote, for preview only.
 * Returns the port that would be assigned for a fresh attach, or null if the
 * worktree range is exhausted / stack unknown.
 */
function previewPort(stack, isWorktree, entries) {
  const range = PORT_RANGES[stack];
  if (!range) return null;
  if (!isWorktree) return range.main;
  const taken = new Set(entries.map((e) => e.port));
  for (let p = range.wtStart; p <= range.wtEnd; p++) {
    if (!taken.has(p)) return p;
  }
  return null;
}

// ─── tiny shell helpers ─────────────────────────────────────────────────────

/** Run a command with explicit argv. Resolves to {code, stdout, stderr}. */
function run(cmd, args, { timeoutMs = 10_000, env } = {}) {
  return new Promise((resolveOut) => {
    const child = spawn(cmd, args, {
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const t = setTimeout(() => {
      try {
        child.kill("SIGKILL");
      } catch {
        /* ignore */
      }
    }, timeoutMs);
    child.stdout.on("data", (d) => {
      stdout += d.toString();
    });
    child.stderr.on("data", (d) => {
      stderr += d.toString();
    });
    child.on("error", (err) => {
      clearTimeout(t);
      resolveOut({ code: -1, stdout, stderr: stderr || String(err) });
    });
    child.on("close", (code) => {
      clearTimeout(t);
      resolveOut({ code: code ?? -1, stdout, stderr });
    });
  });
}

const ssh = (remoteCmd, opts = {}) =>
  run(
    "ssh",
    [
      "-o",
      "BatchMode=yes",
      "-o",
      `ConnectTimeout=${opts.connectTimeout || 5}`,
      SSH_HOST,
      remoteCmd,
    ],
    { timeoutMs: opts.timeoutMs || 8000 },
  );

// ─── state file ─────────────────────────────────────────────────────────────

async function readState() {
  try {
    const raw = await readFile(STATE_FILE, "utf8");
    const json = JSON.parse(raw);
    return Array.isArray(json.entries) ? json.entries : [];
  } catch (err) {
    if (err.code === "ENOENT") return [];
    throw err;
  }
}

/**
 * Persist a `last_variant` next to a specific entry in state.json. kb-remote
 * never reads or writes this field, so adding it is a no-op for the rest of
 * the workflow. We rewrite the whole file (it's tiny) to keep behavior atomic
 * and avoid partial writes.
 */
async function writeLastVariant(path, variant) {
  const { readFile: rf } = await import("node:fs/promises");
  const { writeFile } = await import("node:fs/promises");
  let json;
  try {
    json = JSON.parse(await rf(STATE_FILE, "utf8"));
  } catch (err) {
    if (err.code === "ENOENT") return; // can't persist if there's no state file yet
    throw err;
  }
  if (!Array.isArray(json.entries)) return;
  const entry = json.entries.find((e) => e.path === path);
  if (!entry) return;
  entry.last_variant = variant;
  await writeFile(STATE_FILE, JSON.stringify(json, null, 2) + "\n", "utf8");
}

// ─── per-source probes ──────────────────────────────────────────────────────

async function probeSsh() {
  const r = await ssh("echo ok", { connectTimeout: 4, timeoutMs: 6000 });
  return {
    ok: r.code === 0 && r.stdout.trim() === "ok",
    code: r.code,
    error: r.code === 0 ? null : (r.stderr.trim() || r.stdout.trim() || "ssh failed"),
  };
}

async function probeTunnel() {
  // launchctl print returns rich text; capture state/pid out of it. State can
  // be a single word ("running") or several ("not running"), so we grab the
  // rest of the line and trim.
  const target = `gui/${process.getuid()}/${PLIST_LABEL}`;
  const r = await run("launchctl", ["print", target], { timeoutMs: 4000 });
  if (r.code !== 0) {
    return { loaded: false, state: "not loaded", pid: null };
  }
  const state = (r.stdout.match(/^\s*state\s*=\s*([^\n]+)$/m) || [, "unknown"])[1].trim();
  const pidStr = (r.stdout.match(/^\s*pid\s*=\s*(\d+)\s*$/m) || [, null])[1];
  return {
    loaded: true,
    state,
    pid: pidStr ? Number(pidStr) : null,
  };
}

/**
 * Parse `mutagen sync list` text output into { [name]: { status, conflicts, alphaConn, betaConn } }.
 * Real-world output (mutagen 0.18.x):
 *   --------------------------------------------------------------------------
 *   Name: kb-new-kupibilet-ru
 *   Identifier: sync_xxx
 *   Alpha:
 *       URL: /Users/work/Documents/new-kupibilet.ru
 *       Connected: Yes
 *       Synchronizable contents:
 *           ...
 *   Beta:
 *       URL: kupi-remote:/home/.../new-kupibilet.ru
 *       Connected: Yes
 *       ...
 *   Status: Watching for changes
 *
 * Conflicts only appear when present; absent means zero.
 */
async function fetchMutagenList() {
  // Doubles as a daemon liveness probe: if the call succeeds, the daemon is
  // up; if it fails with "could not dial" / "connection refused", daemon is
  // down. We surface either flavour via mutagenDaemon in the snapshot.
  const r = await run(MUTAGEN_BIN, ["sync", "list"], { timeoutMs: 6000 });
  if (r.code !== 0) {
    return { ok: false, sessions: {}, error: (r.stderr || r.stdout).trim() };
  }
  const sessions = {};
  // Sessions are separated by lines starting with `---`. Robustly: chunk by "Name:".
  const chunks = r.stdout.split(/\n(?=Name:)/);
  for (const chunk of chunks) {
    const m = chunk.match(/Name:\s*(\S+)/);
    if (!m) continue;
    const name = m[1];
    const status = (chunk.match(/Status:\s*(.+)/) || [, ""])[1].trim();
    // Conflict line is omitted entirely when zero; presence ⇒ at least one.
    const conflicts = /Conflicts:/i.test(chunk);
    const alphaConn = (chunk.match(/Alpha:[\s\S]*?Connected:\s*(\S+)/) ||
      [, "?"])[1];
    const betaConn = (chunk.match(/Beta:[\s\S]*?Connected:\s*(\S+)/) ||
      [, "?"])[1];
    sessions[name] = { status, conflicts, alphaConn, betaConn };
  }
  return { ok: true, sessions, sessionCount: Object.keys(sessions).length };
}

async function fetchRemoteTmuxSessions(sshOk) {
  if (!sshOk) return { ok: false, names: [], paneCmd: {} };
  // Also pull each session's pane_current_command so we can distinguish a
  // session whose real workload finished from one that's actively doing work.
  // kb-remote install-deps wraps `pnpm install` with `; sleep 600` so the user
  // can `tmux attach` to inspect the log after install — but if we only check
  // session presence the UI shows "Installing" for 10 minutes after exit.
  // pane_current_command for that idle tail = "sleep"; for an active install
  // it's "pnpm" / "node" / "yarn" / "npm". Likewise for dev sessions the
  // post-exit pane drops back to "bash" while a live `next dev` shows "node".
  const r = await ssh(
    `tmux list-sessions -F '#{session_name}|#{pane_current_command}' 2>/dev/null || true`,
    { timeoutMs: 6000 },
  );
  if (r.code !== 0) return { ok: false, names: [], paneCmd: {}, error: r.stderr.trim() };
  const names = [];
  const paneCmd = {};
  for (const line of r.stdout.split("\n")) {
    const s = line.trim();
    if (!s) continue;
    const [name, cmd] = s.split("|", 2);
    if (!name) continue;
    names.push(name);
    paneCmd[name] = cmd || "";
  }
  return { ok: true, names, paneCmd };
}

/**
 * Classify a tmux session's current foreground command into the buckets the
 * UI cares about. Used to tell "active install/dev" apart from "tmux is
 * sitting on the post-exit prompt" (bash) or "post-exit sleep wrapper".
 */
function isActiveWorkCommand(cmd) {
  if (!cmd) return false;
  const c = cmd.toLowerCase();
  if (c === "sleep") return false;
  if (c === "bash" || c === "sh" || c === "zsh" || c === "fish") return false;
  return true;
}

/**
 * Probe `node_modules` presence on every mirror in a single ssh call. We
 * intentionally don't try to detect "stale install" (lockfile drift) — it
 * requires pnpm/yarn-specific metadata files and produces false positives
 * after `git pull` even when the install is fresh. Detecting the *missing*
 * case is what protects the user from a guaranteed `kb-dev` failure; "stale"
 * is a softer warning best surfaced by the dev process itself.
 *
 * Returns { ok, byPath: { [mirrorPath]: "present" | "missing" }, error? }.
 * If ssh is unreachable, every path resolves to "unknown" downstream.
 */
async function fetchRemoteDeps(sshOk, entries) {
  if (!sshOk || entries.length === 0) {
    return { ok: false, byPath: {} };
  }
  // Build one shell command that prints "<mirror>|present" or "<mirror>|missing"
  // for each path. We pipe paths through stdin to avoid argv length limits and
  // to keep shell-escaping trivial (paths can contain spaces in theory).
  const paths = entries.map((e) => e.mirror_path).filter(Boolean);
  if (paths.length === 0) return { ok: true, byPath: {} };
  const heredoc = paths.join("\n");
  // Bash on remote: read paths line-by-line, test node_modules existence.
  // `[ -d "$p/node_modules" ]` handles monorepo root (pnpm/yarn workspaces
  // always create the top-level node_modules even with hoisting variants).
  const remoteCmd =
    `while IFS= read -r p; do ` +
    `  if [ -d "$p/node_modules" ]; then echo "$p|present"; ` +
    `  else echo "$p|missing"; fi; ` +
    `done <<'KBDEPSEOF'\n${heredoc}\nKBDEPSEOF`;
  const r = await ssh(remoteCmd, { timeoutMs: 6000 });
  if (r.code !== 0) {
    return { ok: false, byPath: {}, error: (r.stderr || r.stdout).trim() };
  }
  const byPath = {};
  for (const line of r.stdout.split("\n")) {
    const sep = line.lastIndexOf("|");
    if (sep < 0) continue;
    const p = line.slice(0, sep);
    const v = line.slice(sep + 1).trim();
    if (v === "present" || v === "missing") byPath[p] = v;
  }
  return { ok: true, byPath };
}

async function fetchGitInfo(path) {
  // Parallel queries; degrade gracefully when not a git repo.
  const [branchR, commitR, statusR, worktreeR] = await Promise.all([
    run("git", ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"], {
      timeoutMs: 3000,
    }),
    run(
      "git",
      ["-C", path, "log", "-1", "--format=%h%x09%cr%x09%s"],
      { timeoutMs: 3000 },
    ),
    run("git", ["-C", path, "status", "--porcelain=v1"], { timeoutMs: 4000 }),
    run("git", ["-C", path, "rev-parse", "--git-common-dir"], { timeoutMs: 3000 }),
  ]);

  if (branchR.code !== 0) {
    return { ok: false, error: branchR.stderr.trim().split("\n")[0] || "not a git repo" };
  }

  const branch = branchR.stdout.trim();
  let commit = null;
  if (commitR.code === 0) {
    const [hash, ago, ...rest] = commitR.stdout.trim().split("\t");
    commit = { hash, ago, subject: rest.join("\t") };
  }
  const dirtyLines = statusR.stdout
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
  const isWorktree =
    worktreeR.code === 0 && !worktreeR.stdout.trim().endsWith("/.git");

  return {
    ok: true,
    branch,
    commit,
    dirty: dirtyLines.length,
    isWorktree,
  };
}

/** Quick check that a TCP port on Mac side is listening (i.e. autossh forwarded it). */
async function probeLocalPort(port) {
  const r = await run("nc", ["-z", "-w", "1", "127.0.0.1", String(port)], {
    timeoutMs: 3000,
  });
  return r.code === 0;
}

/**
 * Probe which TCP ports are actually listening on the WSL side. We need this
 * to distinguish "Live" from "session zombie": the kb-dev tmux session lives
 * past `next dev` exiting (a bash shell remains in the pane), so checking
 * just `tmux list-sessions` reports the dev as up even when nothing is
 * listening on the expected port. The Mac-side autossh tunnel also stays in
 * LISTEN regardless of remote process state, so `listening` (Mac probe)
 * can't tell us either.
 *
 * One ssh call gathers all listening TCP ports on WSL via `ss -lntH`. We
 * collect ports into a Set so per-folder we can `byPort.has(folder.port)`.
 *
 * Returns { ok, byPort: Set<number>, error? }.
 */
async function fetchRemoteListeningPorts(sshOk) {
  if (!sshOk) return { ok: false, byPort: new Set() };
  // `ss -lntH` — TCP, listening, numeric, no header. Column 4 is local addr
  // (e.g. `*:3011` / `127.0.0.1:8443` / `[::]:22`). We extract the trailing
  // `:PORT` and dedupe across IPv4/IPv6.
  const r = await ssh(
    `ss -lntH 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}' | sort -u`,
    { timeoutMs: 6000 },
  );
  if (r.code !== 0) {
    return { ok: false, byPort: new Set(), error: (r.stderr || r.stdout).trim() };
  }
  const byPort = new Set();
  for (const line of r.stdout.split("\n")) {
    const n = Number.parseInt(line.trim(), 10);
    if (Number.isInteger(n) && n > 0 && n < 65536) byPort.add(n);
  }
  return { ok: true, byPort };
}

// ─── orchestrated snapshot ──────────────────────────────────────────────────

/** Full poll: gather everything in parallel, returns a snapshot object. */
async function gatherSnapshot() {
  const startedAt = Date.now();
  const entries = await readState();

  // Coarse-grained probes (1 call each) run in parallel with per-folder fanout.
  const [ssh1, tunnel, mutagenList] = await Promise.all([
    probeSsh(),
    probeTunnel(),
    fetchMutagenList(),
  ]);
  // Mutagen daemon liveness is inferred from sync-list success.
  const mutagenDaemon = mutagenList.ok
    ? { ok: true, raw: `daemon running · ${mutagenList.sessionCount} sync session(s)` }
    : { ok: false, error: mutagenList.error || "daemon unreachable" };

  const [tmux, depsProbe, remoteListening] = await Promise.all([
    fetchRemoteTmuxSessions(ssh1.ok),
    fetchRemoteDeps(ssh1.ok, entries),
    fetchRemoteListeningPorts(ssh1.ok),
  ]);

  const folders = await Promise.all(
    entries.map(async (e) => {
      const [git, listening] = await Promise.all([
        fetchGitInfo(e.path),
        probeLocalPort(e.port),
      ]);
      const mut = mutagenList.sessions[e.label] || null;
      const devSession = `${e.label}-dev`;
      const installSession = `${e.label}-install`;
      const devSessionExists = tmux.ok && tmux.names.includes(devSession);
      const installSessionExists = tmux.ok && tmux.names.includes(installSession);
      // Active = the pane's foreground command is real work (pnpm/node/yarn/…)
      // — not a post-exit bash prompt or the `sleep 600` tail kb-remote
      // install-deps appends so the user can `tmux attach` after exit.
      const installActive = installSessionExists
        && isActiveWorkCommand(tmux.paneCmd?.[installSession]);
      const devActive = devSessionExists
        && isActiveWorkCommand(tmux.paneCmd?.[devSession]);
      // Public API back-compat: devRunning/installRunning still expose
      // "session present", which is what the existing kb-dev --stop logic
      // keys off. The UI uses installActive/devActive (and the port probe
      // below) to decide what label to render.
      const devRunning = devSessionExists;
      const installRunning = installSessionExists;
      // True when a TCP listener is bound to the dev port on WSL. The kb-dev
      // tmux session can outlive its `next dev` (the pane drops back to a
      // bash prompt after `[dev exited]`), so devRunning alone doesn't
      // imply the dev server is actually answering — this is what tells the
      // UI to flag a "session zombie".
      const devPortListening = remoteListening.ok && remoteListening.byPort.has(e.port);
      const variants = VARIANTS[e.stack] || [];
      const variantId = e.last_variant || defaultVariant(e.stack);
      const hosts = hostsFor(e.stack);

      // deps.state derivation:
      //   installing  → tmux install session is *actively* running pnpm/yarn
      //                 (we check pane_current_command, not just session
      //                 presence — kb-remote install-deps appends `sleep 600`
      //                 so the user can attach after exit, and we don't want
      //                 to keep the UI spinning for 10 minutes after install
      //                 actually finished)
      //   ok          → node_modules dir exists on mirror
      //   missing     → mirror reachable + no node_modules → kb-dev will fail
      //   unknown     → ssh down or probe failed → don't gate the UI, just hint
      let depsState = "unknown";
      if (installActive) {
        depsState = "installing";
      } else if (depsProbe.ok && e.mirror_path in depsProbe.byPath) {
        depsState = depsProbe.byPath[e.mirror_path] === "present" ? "ok" : "missing";
      }
      // devReady = "can the user safely click Start dev right now?". Surfaces
      // the reason so the UI can render an exact title on the disabled button.
      let devReady = true;
      let devBlockedReason = null;
      if (installActive) {
        devReady = false;
        devBlockedReason = "install in progress — wait for it to finish";
      } else if (depsState === "missing") {
        devReady = false;
        devBlockedReason = "node_modules missing on WSL — run Install deps first";
      }
      const deps = { state: depsState, mirrorPath: e.mirror_path };

      return {
        ...e,
        exists: true,
        git,
        listening,
        mutagen: mut,
        devSession,
        devRunning,
        devActive,
        devPortListening,
        installSession,
        installRunning,
        installActive,
        variants,
        variantId,
        hosts,
        deps,
        devReady,
        devBlockedReason,
      };
    }),
  );

  return {
    generatedAt: new Date().toISOString(),
    elapsedMs: Date.now() - startedAt,
    config: {
      sshHost: SSH_HOST,
      stateFile: STATE_FILE,
      plistLabel: PLIST_LABEL,
      mutagenBin: MUTAGEN_BIN,
    },
    ssh: ssh1,
    tunnel,
    mutagenDaemon,
    mutagenListError: mutagenList.ok ? null : mutagenList.error,
    tmuxError: tmux.ok ? null : tmux.error || null,
    depsProbeError: depsProbe.ok ? null : depsProbe.error || null,
    folders,
  };
}

// ─── poll cache ─────────────────────────────────────────────────────────────

const cache = {
  snapshot: null,
  error: null,
  refreshingPromise: null,
  lastRefreshMs: 0,
};

async function refreshCache() {
  if (cache.refreshingPromise) return cache.refreshingPromise;
  cache.refreshingPromise = gatherSnapshot()
    .then((snap) => {
      cache.snapshot = snap;
      cache.error = null;
      cache.lastRefreshMs = Date.now();
      return snap;
    })
    .catch((err) => {
      cache.error = String(err && err.stack ? err.stack : err);
      cache.lastRefreshMs = Date.now();
      throw err;
    })
    .finally(() => {
      cache.refreshingPromise = null;
    });
  return cache.refreshingPromise;
}

function startPolling() {
  refreshCache().catch(() => {});
  setInterval(() => {
    refreshCache().catch(() => {});
  }, POLL_INTERVAL_MS).unref();
}

// ─── http plumbing ──────────────────────────────────────────────────────────

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
  ".map": "application/json; charset=utf-8",
};

function sendJson(res, status, body) {
  const buf = Buffer.from(JSON.stringify(body, null, 2));
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": buf.length,
    "cache-control": "no-store",
    // Permit fetch from a frontend hosted elsewhere (e.g. home-server static).
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type",
  });
  res.end(buf);
}

function sendText(res, status, body, contentType = "text/plain; charset=utf-8") {
  const buf = Buffer.from(body);
  res.writeHead(status, {
    "content-type": contentType,
    "content-length": buf.length,
    "cache-control": "no-store",
  });
  res.end(buf);
}

async function readJsonBody(req, maxBytes = 64 * 1024) {
  return new Promise((resolveOut, rejectOut) => {
    let total = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      total += chunk.length;
      if (total > maxBytes) {
        rejectOut(new Error("payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (chunks.length === 0) return resolveOut(null);
      try {
        resolveOut(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch (err) {
        rejectOut(err);
      }
    });
    req.on("error", rejectOut);
  });
}

async function serveStatic(req, res, pathname) {
  // Default to index.html for "/".
  let rel = pathname === "/" ? "/index.html" : pathname;
  // Strip query/fragment, normalize, and prevent path traversal.
  rel = rel.split("?")[0].split("#")[0];
  rel = normalize(rel).replace(/^(\.\.[/\\])+/, "");
  const filePath = resolve(PUBLIC_DIR, "." + rel);
  if (!filePath.startsWith(PUBLIC_DIR)) {
    sendText(res, 403, "forbidden");
    return;
  }
  try {
    const st = await stat(filePath);
    if (!st.isFile()) throw new Error("not a file");
    const buf = await readFile(filePath);
    const type = MIME[extname(filePath)] || "application/octet-stream";
    res.writeHead(200, {
      "content-type": type,
      "content-length": buf.length,
      "cache-control": "no-cache",
    });
    res.end(buf);
  } catch {
    sendText(res, 404, "not found");
  }
}

/** Ensure the requested path is among the state entries (no arbitrary exec). */
async function validatePathInState(path) {
  const entries = await readState();
  return entries.find((e) => e.path === path) || null;
}

/**
 * Resolve an incoming path string to an absolute, canonical form and ensure it
 * stays under $HOME. We don't allow attach/detach against arbitrary filesystem
 * locations even if the user hand-edits the request — the whole kb-remote
 * convention assumes ~/Documents/<repo>.
 */
function resolveHomePath(input) {
  if (typeof input !== "string" || !input.trim()) return null;
  const abs = resolve(input);
  const home = homedir();
  if (abs !== home && !abs.startsWith(home + "/")) return null;
  return abs;
}

// ─── action endpoints ───────────────────────────────────────────────────────

// Serialize attach/detach calls so two parallel requests don't trigger
// concurrent `launchctl kickstart -k` on the same autossh agent (which races
// with itself and can leave the tunnel in a half-loaded state).
let mutateQueue = Promise.resolve();
function runMutating(fn) {
  const next = mutateQueue.then(fn, fn);
  mutateQueue = next.catch(() => {});
  return next;
}

async function actionTunnelRestart() {
  const r = await run(KB_REMOTE_BIN, ["restart-tunnel"], { timeoutMs: 15_000 });
  return { ok: r.code === 0, ...r };
}

async function actionDetach(path, purgeMirror) {
  const args = ["detach", path];
  if (purgeMirror) args.push("--purge-mirror");
  const r = await run(KB_REMOTE_BIN, args, { timeoutMs: 30_000 });
  return { ok: r.code === 0, ...r };
}

async function actionAttach(path) {
  // Mutagen create + initial scan on a fresh repo can take a while; bump the
  // timeout well past the 10s default.
  const r = await run(KB_REMOTE_BIN, ["attach", path], { timeoutMs: 60_000 });
  return { ok: r.code === 0, ...r };
}

/**
 * Scan ~/Documents (depth=1) for folders matching the kb-remote naming
 * convention and not currently attached. Used to power the "Suggested" list in
 * the Attach popover so the user doesn't have to type paths by hand.
 */
async function listAttachCandidates() {
  const entries = await readState();
  const attachedPaths = new Set(entries.map((e) => e.path));
  const attachedBasenames = new Set(entries.map((e) => basename(e.path)));

  let dirents;
  try {
    dirents = await readdir(DOCUMENTS_DIR, { withFileTypes: true });
  } catch (err) {
    return { ok: false, error: String(err.message || err), candidates: [] };
  }

  const candidates = [];
  for (const d of dirents) {
    if (d.name.startsWith(".")) continue;
    // Accept directories and symlinks to directories.
    const full = join(DOCUMENTS_DIR, d.name);
    let isDir = d.isDirectory();
    if (!isDir && d.isSymbolicLink()) {
      try {
        const st = await stat(full);
        isDir = st.isDirectory();
      } catch {
        continue;
      }
    }
    if (!isDir) continue;
    if (attachedPaths.has(full)) continue;
    // Also dedup by basename — if a worktree with that name is already attached
    // from a different parent dir, kb-remote will pick the same label and fail.
    if (attachedBasenames.has(d.name)) continue;
    const cls = classifyBasename(d.name);
    if (!cls) continue;
    candidates.push({
      path: full,
      basename: d.name,
      stack: cls.stack,
      isWorktree: cls.isWorktree,
      parentRepo: cls.parentRepo,
      label: labelFor(d.name),
      suggestedPort: previewPort(cls.stack, cls.isWorktree, entries),
    });
  }

  candidates.sort((a, b) => a.basename.localeCompare(b.basename));
  return { ok: true, candidates };
}

/**
 * Validate a user-typed path for the Attach form and report what *would*
 * happen if they hit Attach. Returns ok=false with a human-readable `error`
 * for every failure mode the real attach would also reject, plus a port hint.
 */
async function previewAttach(rawPath) {
  const path = resolveHomePath(rawPath);
  if (!path) {
    return { ok: false, error: "path is required and must live under $HOME" };
  }
  let st;
  try {
    st = await stat(path);
  } catch {
    return { ok: false, path, error: "path does not exist" };
  }
  if (!st.isDirectory()) {
    return { ok: false, path, error: "path is not a directory" };
  }
  const base = basename(path);
  const cls = classifyBasename(base);
  if (!cls) {
    return {
      ok: false,
      path,
      basename: base,
      error:
        `basename does not match kb-remote convention ` +
        `(expected ${REPO_KUPI}, ${REPO_NEW}, or '<repo>-<branch>')`,
    };
  }
  const entries = await readState();
  const already = entries.find((e) => e.path === path);
  if (already) {
    return {
      ok: false,
      path,
      basename: base,
      stack: cls.stack,
      isWorktree: cls.isWorktree,
      error: `already attached as ${already.label} on port :${already.port}`,
      existingPort: already.port,
      existingLabel: already.label,
    };
  }
  const labelCollision = entries.find((e) => basename(e.path) === base);
  if (labelCollision) {
    return {
      ok: false,
      path,
      basename: base,
      stack: cls.stack,
      isWorktree: cls.isWorktree,
      error: `another path is attached with the same basename → label collision: ${labelCollision.label}`,
    };
  }
  const port = previewPort(cls.stack, cls.isWorktree, entries);
  if (port == null) {
    return {
      ok: false,
      path,
      basename: base,
      stack: cls.stack,
      isWorktree: cls.isWorktree,
      error: `no free port in range for stack '${cls.stack}'`,
    };
  }
  return {
    ok: true,
    path,
    basename: base,
    stack: cls.stack,
    isWorktree: cls.isWorktree,
    parentRepo: cls.parentRepo,
    label: labelFor(base),
    suggestedPort: port,
  };
}

async function actionDevStart(path, variant) {
  const args = ["--bg", path];
  if (variant) args.push("--variant", variant);
  const r = await run(KB_DEV_BIN, args, { timeoutMs: 15_000 });
  // Persist the chosen variant so subsequent renders show the right pre-selection.
  // We only do this on success to avoid sticking a broken variant id.
  if (r.code === 0 && variant) {
    try {
      await writeLastVariant(path, variant);
    } catch (err) {
      // Non-fatal: action succeeded, persistence didn't.
      // eslint-disable-next-line no-console
      console.warn(`[kb-remote-ui] writeLastVariant failed: ${err.message || err}`);
    }
  }
  return { ok: r.code === 0, ...r };
}

async function actionDevStop(path) {
  const r = await run(KB_DEV_BIN, ["--stop", path], { timeoutMs: 10_000 });
  return { ok: r.code === 0, ...r };
}

async function actionMutagenRefresh(path) {
  const r = await run(KB_REMOTE_BIN, ["refresh", path], { timeoutMs: 30_000 });
  return { ok: r.code === 0, ...r };
}

/**
 * `kb-remote install-deps <path>` opens a tmux session `<label>-install` on
 * the remote and runs the appropriate package manager inside it. It returns
 * as soon as the session is launched (the install itself keeps running in
 * tmux); the snapshot poller picks up the new session within POLL_INTERVAL_MS.
 */
async function actionInstallDeps(path) {
  const r = await run(KB_REMOTE_BIN, ["install-deps", path], { timeoutMs: 30_000 });
  return { ok: r.code === 0, ...r };
}

// ─── worktree wizard ────────────────────────────────────────────────────────
//
// Mirrors ~/.cursor/skills/kupibilet-worktree/SKILL.md so the dashboard does
// exactly the same git/kb-remote dance the skill does, without users having
// to drop into a terminal. Three deliberate constraints:
//   • Only operates on parents that live in state.json and are NOT worktrees
//     themselves (skill: «cwd должно быть в основном клон-репе»).
//   • Sanitize branch → folder by replacing "/" with "-". The branch ref
//     stays untouched (origin checkout still uses "feature/foo").
//   • Block collisions hard: if either the target folder exists OR the
//     branch is already checked out in another worktree, refuse with a
//     helpful error instead of guessing a suffix.

/**
 * List local + origin branches for a parent repo, plus the current branch.
 * Returns { ok, local: [...], origin: [...], current, error? }.
 * We feed this to the wizard's branch-input datalist so the user gets
 * autocomplete from real refs, not guesswork.
 */
async function listBranches(parentPath) {
  // Best-effort fetch — non-fatal: skill explicitly tolerates `origin` being
  // absent (e.g. for request-mock). Pipe to /dev/null with `|| true` would
  // require shell:true, so we just run it and ignore its exit code.
  await run("git", ["-C", parentPath, "fetch", "--prune", "origin"], { timeoutMs: 15_000 }).catch(() => {});

  const [headR, localR, originR] = await Promise.all([
    run("git", ["-C", parentPath, "rev-parse", "--abbrev-ref", "HEAD"], { timeoutMs: 3000 }),
    run(
      "git",
      ["-C", parentPath, "for-each-ref", "--format=%(refname:short)", "refs/heads/"],
      { timeoutMs: 5000 },
    ),
    run(
      "git",
      ["-C", parentPath, "for-each-ref", "--format=%(refname:short)", "refs/remotes/origin/"],
      { timeoutMs: 5000 },
    ),
  ]);
  if (localR.code !== 0) {
    return { ok: false, local: [], origin: [], current: null, error: (localR.stderr || localR.stdout).trim() };
  }
  const local = localR.stdout.split("\n").map((s) => s.trim()).filter(Boolean);
  const origin = originR.stdout
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean)
    // for-each-ref short-form for "refs/remotes/origin/HEAD" comes back as just
    // "origin" (no slash), and we don't want that polluting the list either.
    .filter((s) => s !== "origin" && s !== "origin/HEAD")
    .map((s) => s.replace(/^origin\//, ""))
    .filter((s) => s && s !== "HEAD");
  const current = headR.code === 0 ? headR.stdout.trim() : null;
  return { ok: true, local, origin, current };
}

/**
 * Classify a branch name against a parent's known local/origin set. Used to
 * decide which `git worktree add` invocation to run, and what badge to show
 * in the wizard's branch input.
 *
 *   "local"        → branch exists locally (worktree add <dir> <branch>)
 *   "origin"       → only on origin     (worktree add <dir> -b <branch> origin/<branch>)
 *   "both"         → both present       (worktree add <dir> <branch>; git remembers tracking)
 *   "new"          → neither            (worktree add <dir> -b <branch> <base>)
 */
function classifyBranch(branch, branches) {
  const inLocal = branches.local.includes(branch);
  const inOrigin = branches.origin.includes(branch);
  if (inLocal && inOrigin) return "both";
  if (inLocal) return "local";
  if (inOrigin) return "origin";
  return "new";
}

const BASE_BRANCH = {
  // kb-remote naming convention: `kupibilet` / `new-kupibilet` come from stack.
  // The skill says both monorepos use `origin/dev` as base because `main` is prod.
  kupibilet: "origin/dev",
  "new-kupibilet": "origin/dev",
};

/** Sanitize a branch name for use as a directory suffix. `/` → `-`, drop weird chars. */
function sanitizeBranchForFolder(branch) {
  return branch.replace(/\//g, "-").replace(/[^A-Za-z0-9._-]/g, "_");
}

/**
 * Execute the full skill workflow. Returns a structured response with one
 * entry per step so the UI can render exactly what succeeded/failed instead
 * of opaque "exit 1".
 */
async function actionWorktreeCreate({ parentPath, branch, copyEnv, autoAttach, autoInstall }) {
  const steps = [];
  const pushStep = (name, r) => {
    steps.push({
      name,
      ok: r.code === 0,
      code: r.code,
      stdout: (r.stdout || "").trim(),
      stderr: (r.stderr || "").trim(),
    });
    return r.code === 0;
  };

  // 1) Validate parent (must be an attached main checkout).
  const entries = await readState();
  const parent = entries.find((e) => e.path === parentPath);
  if (!parent) {
    return { ok: false, error: `parent path is not attached: ${parentPath}`, steps };
  }
  if (parent.is_worktree) {
    return { ok: false, error: `parent ${basename(parentPath)} is itself a worktree; pick the main checkout`, steps };
  }
  const stack = parent.stack;
  const base = BASE_BRANCH[stack];
  if (!base) {
    return { ok: false, error: `no base branch configured for stack '${stack}'`, steps };
  }

  // 2) Resolve branch state.
  const branches = await listBranches(parentPath);
  if (!branches.ok) {
    return { ok: false, error: `cannot list branches: ${branches.error}`, steps };
  }
  const branchState = classifyBranch(branch, branches);

  // 3) Compute target path and validate collision.
  const repoBase = basename(parentPath);
  const folder = `${repoBase}-${sanitizeBranchForFolder(branch)}`;
  const newPath = join(DOCUMENTS_DIR, folder);
  if (existsSync(newPath)) {
    return {
      ok: false,
      error: `target folder already exists: ${newPath}. Pick a different branch or remove the existing worktree.`,
      steps,
      newPath,
    };
  }
  // Also check git's perspective: is this branch already checked out somewhere?
  const wtListR = await run("git", ["-C", parentPath, "worktree", "list", "--porcelain"], { timeoutMs: 5000 });
  if (wtListR.code === 0) {
    // worktree list --porcelain emits blocks: "worktree <path>\nHEAD <sha>\nbranch refs/heads/<name>\n\n"
    const checkedOut = wtListR.stdout
      .split(/\n\n+/)
      .map((block) => {
        const b = block.match(/^branch\s+refs\/heads\/(.+)$/m);
        const p = block.match(/^worktree\s+(.+)$/m);
        return b ? { branch: b[1], path: p?.[1] || null } : null;
      })
      .filter(Boolean);
    const owner = checkedOut.find((c) => c.branch === branch);
    if (owner) {
      return {
        ok: false,
        error: `branch '${branch}' is already checked out in worktree ${owner.path}. Detach that worktree first or pick another branch.`,
        steps,
      };
    }
  }

  // 4) git worktree add — args depend on branch state.
  let addArgs;
  if (branchState === "new") {
    // Brand-new branch from base. base may be a remote ref like origin/dev.
    addArgs = ["-C", parentPath, "worktree", "add", newPath, "-b", branch, base];
  } else if (branchState === "origin") {
    // Origin-only branch → create tracking local branch as we check out.
    addArgs = ["-C", parentPath, "worktree", "add", newPath, "-b", branch, `origin/${branch}`];
  } else {
    // Local-only or both: just check out the existing local ref.
    addArgs = ["-C", parentPath, "worktree", "add", newPath, branch];
  }
  const addR = await run("git", addArgs, { timeoutMs: 30_000 });
  if (!pushStep("git worktree add", addR)) {
    return { ok: false, error: "git worktree add failed", steps, newPath };
  }

  // 5) Copy .env* (excluding .env.example) from parent → new worktree.
  if (copyEnv) {
    // Use bash one-liner to keep it portable with skill's exact find filters.
    const script = `set -e; cd "${parentPath}"; ` +
      `find . -maxdepth 6 -name '.env*' ` +
      `  -not -path './node_modules/*' -not -path './.next/*' -not -path './dist/*' ` +
      `  -not -name '.env.example' -print | ` +
      `while IFS= read -r src; do ` +
      `  dst="${newPath}/$src"; ` +
      `  if [ ! -e "$dst" ]; then mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; echo "copied $src"; fi; ` +
      `done`;
    const envR = await run("bash", ["-c", script], { timeoutMs: 10_000 });
    pushStep("copy .env* files", envR);
    // Non-fatal: cp errors are surfaced but we still keep going. The worktree
    // is already created; the user can re-copy manually.
  }

  // 6) Attach to kb-remote (creates Mutagen sync + reserves port).
  let port = null;
  let label = null;
  if (autoAttach) {
    const attachR = await runMutating(() =>
      run(KB_REMOTE_BIN, ["attach", newPath], { timeoutMs: 60_000 }),
    );
    pushStep("kb-remote attach", attachR);
    if (attachR.code !== 0) {
      return { ok: false, error: "kb-remote attach failed", steps, newPath };
    }
    // Re-read state to pick up the port that kb-remote allocated.
    const refreshed = await readState();
    const fresh = refreshed.find((e) => e.path === newPath);
    if (fresh) { port = fresh.port; label = fresh.label; }
  }

  // 7) Install deps on WSL (tmux fire-and-forget — kb-remote returns fast,
  // snapshot poller picks up the install session within POLL_INTERVAL_MS).
  if (autoInstall && autoAttach) {
    const instR = await run(KB_REMOTE_BIN, ["install-deps", newPath], { timeoutMs: 30_000 });
    pushStep("kb-remote install-deps", instR);
  }

  return {
    ok: true,
    newPath,
    label,
    port,
    branch,
    branchState,
    steps,
  };
}

// ─── routing ────────────────────────────────────────────────────────────────

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);

  // CORS preflight (so a frontend hosted on home-server can hit this API).
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,OPTIONS",
      "access-control-allow-headers": "content-type",
    });
    res.end();
    return;
  }

  try {
    if (req.method === "GET" && url.pathname === "/api/health") {
      sendJson(res, 200, { ok: true, ts: new Date().toISOString() });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/snapshot") {
      // Force a fresh refresh if the cache is stale or ?force=1.
      const force = url.searchParams.get("force") === "1";
      const stale =
        !cache.snapshot ||
        Date.now() - cache.lastRefreshMs > POLL_INTERVAL_MS * 2;
      if (force || stale) {
        try {
          await refreshCache();
        } catch (err) {
          sendJson(res, 500, { error: String(err.message || err) });
          return;
        }
      }
      sendJson(res, 200, cache.snapshot);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/actions/tunnel-restart") {
      const r = await actionTunnelRestart();
      refreshCache().catch(() => {});
      sendJson(res, r.ok ? 200 : 500, r);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/actions/detach") {
      const body = await readJsonBody(req);
      const rawPath = body && typeof body.path === "string" ? body.path : null;
      const path = resolveHomePath(rawPath);
      if (!path) {
        sendJson(res, 400, { error: "body.path is required and must live under $HOME" });
        return;
      }
      const entry = await validatePathInState(path);
      if (!entry) {
        sendJson(res, 404, { error: `path not attached: ${path}` });
        return;
      }
      const purgeMirror = body.purgeMirror === true;
      const result = await runMutating(() => actionDetach(path, purgeMirror));
      refreshCache().catch(() => {});
      sendJson(res, result.ok ? 200 : 500, { ...result, path, label: entry.label, purgeMirror });
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/actions/attach") {
      const body = await readJsonBody(req);
      const rawPath = body && typeof body.path === "string" ? body.path : null;
      const path = resolveHomePath(rawPath);
      if (!path) {
        sendJson(res, 400, { error: "body.path is required and must live under $HOME" });
        return;
      }
      let st;
      try {
        st = await stat(path);
      } catch {
        sendJson(res, 400, { error: `path does not exist: ${path}` });
        return;
      }
      if (!st.isDirectory()) {
        sendJson(res, 400, { error: `path is not a directory: ${path}` });
        return;
      }
      const cls = classifyBasename(basename(path));
      if (!cls) {
        sendJson(res, 400, {
          error:
            `basename '${basename(path)}' does not match kb-remote convention ` +
            `(expected ${REPO_KUPI}, ${REPO_NEW}, or '<repo>-<branch>')`,
        });
        return;
      }
      const existing = await validatePathInState(path);
      if (existing) {
        sendJson(res, 409, { error: `already attached as ${existing.label}`, label: existing.label });
        return;
      }
      const result = await runMutating(() => actionAttach(path));
      refreshCache().catch(() => {});
      sendJson(res, result.ok ? 200 : 500, {
        ...result,
        path,
        label: labelFor(basename(path)),
        stack: cls.stack,
        isWorktree: cls.isWorktree,
      });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/attach-candidates") {
      const result = await listAttachCandidates();
      sendJson(res, 200, result);
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/attach-preview") {
      const rawPath = url.searchParams.get("path") || "";
      const result = await previewAttach(rawPath);
      sendJson(res, result.ok ? 200 : 400, result);
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/branches") {
      const rawPath = url.searchParams.get("parentPath") || "";
      const parentPath = resolveHomePath(rawPath);
      if (!parentPath) {
        sendJson(res, 400, { ok: false, error: "parentPath required (under $HOME)" });
        return;
      }
      const entry = await validatePathInState(parentPath);
      if (!entry) {
        sendJson(res, 404, { ok: false, error: `parent not attached: ${parentPath}` });
        return;
      }
      if (entry.is_worktree) {
        sendJson(res, 400, { ok: false, error: "parent is itself a worktree; pick the main checkout" });
        return;
      }
      const result = await listBranches(parentPath);
      sendJson(res, result.ok ? 200 : 500, result);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/actions/worktree-create") {
      const body = await readJsonBody(req);
      const parentPath = resolveHomePath(body?.parentPath || "");
      const branch = typeof body?.branch === "string" ? body.branch.trim() : "";
      if (!parentPath) {
        sendJson(res, 400, { ok: false, error: "parentPath required (under $HOME)" });
        return;
      }
      if (!branch) {
        sendJson(res, 400, { ok: false, error: "branch required" });
        return;
      }
      // Validate branch shape early — git refuses some characters anyway, but
      // we want a clean UI error instead of a step failure later.
      if (!/^[\w./-][\w./+-]*$/.test(branch) || branch.includes("..") || branch.startsWith("-")) {
        sendJson(res, 400, { ok: false, error: `invalid branch name: ${branch}` });
        return;
      }
      const result = await actionWorktreeCreate({
        parentPath,
        branch,
        copyEnv: body?.copyEnv !== false,
        autoAttach: body?.autoAttach !== false,
        autoInstall: body?.autoInstall !== false,
      });
      refreshCache().catch(() => {});
      sendJson(res, result.ok ? 200 : 500, result);
      return;
    }

    if (
      req.method === "POST" &&
      (url.pathname === "/api/actions/dev-start" ||
        url.pathname === "/api/actions/dev-stop" ||
        url.pathname === "/api/actions/mutagen-refresh" ||
        url.pathname === "/api/actions/install-deps" ||
        url.pathname === "/api/actions/set-variant")
    ) {
      const body = await readJsonBody(req);
      const path = body && typeof body.path === "string" ? body.path : null;
      if (!path) {
        sendJson(res, 400, { error: "body.path is required" });
        return;
      }
      const entry = await validatePathInState(path);
      if (!entry) {
        sendJson(res, 404, { error: `path not attached: ${path}` });
        return;
      }
      let result;
      if (url.pathname === "/api/actions/dev-start") {
        // Pick variant: explicit > entry.last_variant > stack default.
        const variant = body.variant || entry.last_variant || defaultVariant(entry.stack);
        const knownVariants = (VARIANTS[entry.stack] || []).map((v) => v.id);
        if (variant && knownVariants.length > 0 && !knownVariants.includes(variant)) {
          sendJson(res, 400, {
            error: `unknown variant '${variant}' for stack '${entry.stack}'`,
            allowed: knownVariants,
          });
          return;
        }
        result = await actionDevStart(path, variant);
        result.variant = variant;
      } else if (url.pathname === "/api/actions/set-variant") {
        // Choose-only endpoint: persists the selected variant without
        // starting dev. Lets the user pre-pick what the next Start will run.
        const variant = body.variant;
        const knownVariants = (VARIANTS[entry.stack] || []).map((v) => v.id);
        if (!variant || (knownVariants.length > 0 && !knownVariants.includes(variant))) {
          sendJson(res, 400, {
            error: `unknown variant '${variant}' for stack '${entry.stack}'`,
            allowed: knownVariants,
          });
          return;
        }
        try {
          await writeLastVariant(path, variant);
          result = { ok: true, variant, stdout: "", stderr: "", code: 0 };
        } catch (err) {
          result = { ok: false, variant, stdout: "", stderr: String(err.message || err), code: 1 };
        }
      } else if (url.pathname === "/api/actions/dev-stop") {
        result = await actionDevStop(path);
      } else if (url.pathname === "/api/actions/install-deps") {
        result = await actionInstallDeps(path);
      } else {
        result = await actionMutagenRefresh(path);
      }
      refreshCache().catch(() => {});
      sendJson(res, result.ok ? 200 : 500, result);
      return;
    }

    if (url.pathname.startsWith("/api/")) {
      sendJson(res, 404, { error: "unknown api route" });
      return;
    }

    // Anything non-API → static.
    if (req.method === "GET" || req.method === "HEAD") {
      await serveStatic(req, res, url.pathname);
      return;
    }

    sendText(res, 405, "method not allowed");
  } catch (err) {
    sendJson(res, 500, { error: String(err && err.stack ? err.stack : err) });
  }
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(
    `[kb-remote-ui] http://${HOST}:${PORT}  (state=${STATE_FILE}, ssh=${SSH_HOST})`,
  );
  startPolling();
});

// Graceful shutdown so launchd / Ctrl-C don't leave the socket dangling.
for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
