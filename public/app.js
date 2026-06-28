// kb-remote-ui — dashboard frontend.
//
// • Polls /api/snapshot every 5s, re-renders status bar + folder cards.
// • Action buttons (restart tunnel, dev start/stop, refresh sync) hit
//   POST /api/actions/* and surface a toast + inline stdout/stderr.
// • Theme switcher mirrors request-mock: writes [data-theme] on <html>,
//   persists choice in localStorage.
//
// API base is same-origin by default. To deploy the static UI elsewhere
// (e.g. home-server static-sites) and point it at a Mac on Tailscale,
// set ?api=http://100.x.x.x:4747 once — it's persisted in localStorage.

// ─── config ────────────────────────────────────────────────────────────────

const LS_API = "kb-remote-ui:api";
const LS_THEME = "kb-remote-ui:theme";

const apiBase = (() => {
  const url = new URL(window.location.href);
  const fromUrl = url.searchParams.get("api");
  if (fromUrl !== null) {
    if (fromUrl === "") localStorage.removeItem(LS_API);
    else localStorage.setItem(LS_API, fromUrl);
    url.searchParams.delete("api");
    window.history.replaceState({}, "", url.toString());
  }
  return localStorage.getItem(LS_API) || "";
})();

const POLL_MS = 5000;
const VALID_THEMES = new Set(["system", "dark", "light", "midnight", "spotify", "nord"]);

// ─── theme ─────────────────────────────────────────────────────────────────

function applyTheme(id) {
  const t = VALID_THEMES.has(id) ? id : "system";
  document.documentElement.setAttribute("data-theme", t);
  localStorage.setItem(LS_THEME, t);
  refreshThemePopover();
}

function refreshThemePopover() {
  const current = document.documentElement.getAttribute("data-theme") || "system";
  for (const btn of document.querySelectorAll(".theme-option")) {
    btn.classList.toggle("active", btn.dataset.theme === current);
  }
}

applyTheme(localStorage.getItem(LS_THEME) || "system");

// ─── data fetching ─────────────────────────────────────────────────────────

async function fetchSnapshot({ force = false } = {}) {
  const url = `${apiBase}/api/snapshot${force ? "?force=1" : ""}`;
  const r = await fetch(url, { cache: "no-store" });
  if (!r.ok) throw new Error(`snapshot ${r.status}`);
  return r.json();
}

async function postAction(path, body = null) {
  const r = await fetch(`${apiBase}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : null,
  });
  const json = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, ...json };
}

// ─── utils ─────────────────────────────────────────────────────────────────

const $ = (sel, root = document) => root.querySelector(sel);

function relativeTime(iso) {
  const dt = (Date.now() - new Date(iso).getTime()) / 1000;
  if (dt < 60) return `${Math.max(0, Math.round(dt))}s ago`;
  if (dt < 3600) return `${Math.round(dt / 60)}m ago`;
  if (dt < 86400) return `${Math.round(dt / 3600)}h ago`;
  return `${Math.round(dt / 86400)}d ago`;
}

function setDot(cell, kind) {
  const dot = cell.querySelector(".status-dot");
  dot.className = `status-dot dot-${kind}`;
}

function setVal(cell, text, opts = {}) {
  const val = cell.querySelector(".status-val");
  val.textContent = text;
  val.classList.toggle("muted", !!opts.muted);
}

function escapeHtml(str) {
  if (str == null) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function toast(message, kind = "ok", { timeout = 4500 } = {}) {
  const host = $("#toastHost");
  const el = document.createElement("div");
  el.className = `toast is-${kind}`;
  el.textContent = message;
  host.appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 0.2s, transform 0.2s";
    el.style.opacity = "0";
    el.style.transform = "translateY(6px)";
    setTimeout(() => el.remove(), 250);
  }, timeout);
}

// ─── rendering ─────────────────────────────────────────────────────────────

function renderStatusBar(snap) {
  window.__lastSnap = snap;
  const grid = $("#statusGrid");

  // SSH
  const sshCell = grid.querySelector('[data-key="ssh"]');
  if (snap.ssh && snap.ssh.ok) {
    setDot(sshCell, "ok");
    setVal(sshCell, `${snap.config.sshHost} — reachable`);
  } else {
    setDot(sshCell, "bad");
    setVal(sshCell, snap.ssh?.error || `${snap.config.sshHost} unreachable`);
  }

  // Tunnel — short labels so they don't get ellipsis-clipped next to the Restart button.
  const tunCell = grid.querySelector('[data-key="tunnel"]');
  if (snap.tunnel && snap.tunnel.loaded) {
    const st = snap.tunnel.state;
    if (st === "running") {
      setDot(tunCell, "ok");
      setVal(tunCell, `running · pid ${snap.tunnel.pid ?? "?"}`);
    } else if (/not running|exited|stopped/i.test(st)) {
      setDot(tunCell, "warn");
      setVal(tunCell, "stopped");
    } else {
      setDot(tunCell, "warn");
      setVal(tunCell, st || "unknown");
    }
  } else {
    setDot(tunCell, "warn");
    setVal(tunCell, "not loaded");
  }

  // Mutagen daemon
  const mutCell = grid.querySelector('[data-key="mutagen"]');
  if (snap.mutagenDaemon && snap.mutagenDaemon.ok) {
    setDot(mutCell, "ok");
    setVal(mutCell, snap.mutagenDaemon.raw || "running");
  } else {
    setDot(mutCell, "bad");
    setVal(mutCell, snap.mutagenDaemon?.error || "daemon down");
  }

  // Folders count
  const folCell = grid.querySelector('[data-key="folders"]');
  const total = snap.folders.length;
  const devUp = snap.folders.filter((f) => f.devRunning).length;
  const syncBad = snap.folders.filter(
    (f) => !f.mutagen || (f.mutagen.status && !/Watching|Synchronized/i.test(f.mutagen.status)) || f.mutagen?.conflicts,
  ).length;
  setDot(
    folCell,
    total === 0 ? "unknown" : syncBad > 0 ? "warn" : "ok",
  );
  setVal(folCell, `${total} attached · ${devUp} dev running${syncBad ? ` · ${syncBad} sync warn` : ""}`);

  $("#lastRefresh").textContent = relativeTime(snap.generatedAt);
  $("#footerInfo").textContent = `state: ${snap.config.stateFile} · poll ${snap.elapsedMs}ms · refreshed ${relativeTime(snap.generatedAt)}`;
}

/**
 * Per-folder functional health. Drives the big colored pill at the top of
 * each card, the card border color, and whether "Open localhost:NNNN" is
 * clickable.
 *
 * Order matters: we surface the worst actionable problem first. The previous
 * version only border-colored the card; users could see "Dev: running" + a
 * tiny "not listening" pill side by side and click an "Open" link that
 * silently fails (autossh tunnel was down). Now that case becomes a top-row
 * red TUNNEL DOWN with the Open button disabled and a Restart shortcut.
 */
function computeHealth(folder, snap) {
  if (!snap.ssh?.ok)
    return { kind: "offline", label: "Host offline", sub: "SSH unreachable", color: "bad" };

  if (!folder.mutagen)
    return {
      kind: "sync-missing",
      label: "Sync missing",
      sub: "no Mutagen session for this label",
      color: "bad",
    };
  if (folder.mutagen.conflicts)
    return {
      kind: "sync-conflict",
      label: "Sync conflict",
      sub: "Mutagen reports conflicts",
      color: "bad",
      action: "refresh",
    };
  if (folder.mutagen.alphaConn !== "Yes" || folder.mutagen.betaConn !== "Yes")
    return {
      kind: "sync-disconnected",
      label: "Sync disconnected",
      sub: `α ${folder.mutagen.alphaConn} · β ${folder.mutagen.betaConn}`,
      color: "bad",
      action: "refresh",
    };

  const tunnelUp = snap.tunnel?.state === "running";

  if (folder.devRunning && !tunnelUp) {
    return {
      kind: "tunnel-down",
      label: "Tunnel down",
      sub: `dev is up on WSL but the autossh tunnel is stopped — localhost:${folder.port} unreachable`,
      color: "bad",
      action: "restart-tunnel",
    };
  }
  if (folder.devRunning && tunnelUp && !folder.listening) {
    return {
      kind: "tunnel-down",
      label: "Port not forwarded",
      sub: `dev is up but autossh isn't forwarding ${folder.port} — restart the tunnel`,
      color: "bad",
      action: "restart-tunnel",
    };
  }
  // "Session zombie": tmux session is alive (so devRunning=true and the Mac
  // tunnel is happy), but no process on WSL listens on the dev port. This
  // happens when `next dev`/`yarn express` exited inside the pane and left
  // a bare bash prompt behind — `tmux list-sessions` still reports it. The
  // user must Stop dev (which kills the session) before Start can recreate
  // it cleanly, so we surface that as the primary CTA.
  if (folder.devRunning && tunnelUp && folder.listening && folder.devPortListening === false)
    return {
      kind: "dev-dead",
      label: "Dev exited",
      sub: `tmux session ${folder.devSession} is alive but nothing on WSL is listening on :${folder.port} — the dev process exited; Stop dev then Start again`,
      color: "bad",
      action: "stop-dev",
    };
  if (folder.devRunning && folder.listening)
    return {
      kind: "live",
      label: "Live",
      sub: `localhost:${folder.port} is reachable`,
      color: "ok",
    };
  if (folder.installActive)
    return {
      kind: "installing",
      label: "Installing deps",
      sub: `tmux session ${folder.installSession} is active — yarn/pnpm install on WSL`,
      color: "info",
    };
  if (folder.deps?.state === "missing")
    return {
      kind: "deps-missing",
      label: "Deps missing",
      sub: `no node_modules on ${folder.mirror_path} — Start dev will fail`,
      color: "bad",
      action: "install-deps",
    };
  // Mutagen still syncing (Scanning/Staging/Reconciling/...).
  if (!/Watching|Synchronized/i.test(folder.mutagen.status))
    return {
      kind: "sync-busy",
      label: folder.mutagen.status,
      sub: "Mutagen catching up",
      color: "info",
    };
  return {
    kind: "idle",
    label: "Idle",
    sub: "sync OK, dev not started",
    color: "muted",
  };
}

function cardForFolder(folder, snap) {
  const basename = folder.path.split("/").pop();
  const wt = folder.is_worktree ? `<span class="wt" title="git worktree">wt</span>` : "";
  const stack = `<span class="stack">${escapeHtml(folder.stack)}</span>`;
  const health = computeHealth(folder, snap);
  folder._health = health; // remembered for action wiring

  const branchTip = folder.git?.ok
    ? `${folder.git.branch}${folder.git.dirty ? ` · ${folder.git.dirty} dirty` : ""}`
    : folder.git?.error || "no git info";

  const commitTip = folder.git?.commit
    ? `${folder.git.commit.hash} · ${folder.git.commit.ago}\n${folder.git.commit.subject}`
    : "no commit info";

  const mutTip = folder.mutagen
    ? `${folder.mutagen.status}\nα connected: ${folder.mutagen.alphaConn}\nβ connected: ${folder.mutagen.betaConn}${folder.mutagen.conflicts ? "\n⚠ conflicts present" : ""}`
    : "no Mutagen session";
  const mutDot = (() => {
    if (!folder.mutagen) return "bad";
    if (folder.mutagen.conflicts) return "bad";
    if (folder.mutagen.alphaConn !== "Yes" || folder.mutagen.betaConn !== "Yes") return "bad";
    if (/Watching|Synchronized/i.test(folder.mutagen.status)) return "ok";
    return "info";
  })();
  const mutShort = folder.mutagen
    ? (folder.mutagen.status || "?").replace(/^Watching for changes$/i, "Watching")
    : "missing";

  // "running" requires both the session AND the port — keeps the dev pill
  // honest when next dev exits but the tmux pane is still alive on bash.
  const devLive = folder.devRunning && folder.devPortListening !== false;
  const devShort = devLive
    ? "running"
    : folder.devRunning
      ? "exited"
      : folder.installActive
        ? "installing"
        : "stopped";
  const devDot = devLive
    ? "ok"
    : folder.devRunning
      ? "bad"
      : folder.installActive
        ? "info"
        : "unknown";
  const devTip = folder.devRunning
    ? `tmux session: ${folder.devSession}${devLive ? "" : " (pane is alive, but nothing listens on :" + folder.port + ")"}`
    : folder.installActive
      ? `tmux session: ${folder.installSession}`
      : "no tmux session on remote";

  // One next-dev process can answer multiple hostnames (e.g. new-kupibilet
  // serves kupibilet.local + kupicom.local from the same :3010 by switching
  // whitelabel on Host:). For each host we render its own Open button.
  const hosts = Array.isArray(folder.hosts) && folder.hosts.length > 0
    ? folder.hosts
    : ["localhost"];
  // "Open" only makes sense when BOTH the remote dev is up AND autossh is
  // actually forwarding the port. `folder.listening` (nc -z) is true even
  // when the remote process is down — autossh keeps the local socket open —
  // so we additionally gate on devRunning to avoid the misleading-looking
  // blue link the user complained about.
  const openEnabled = folder.devRunning && folder.listening;
  const openTip = openEnabled
    ? `open the dev URL(s) for this folder`
    : !folder.devRunning
      ? `dev not running on WSL — start dev first`
      : `port ${folder.port} isn't being forwarded — restart the autossh tunnel`;

  const headerActionForHealth = health.action === "restart-tunnel"
    ? `<button class="btn btn-sm btn-danger js-restart-tunnel-card" title="kb-remote restart-tunnel">
         <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3.5-7.1"/><path d="M21 4v5h-5"/></svg>
         Restart tunnel
       </button>`
    : health.action === "refresh"
      ? `<button class="btn btn-sm btn-danger js-refresh-sync-card" title="kb-remote refresh">
           <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3.5-7.1"/><path d="M21 4v5h-5"/></svg>
           Refresh sync
         </button>`
      : health.action === "install-deps"
        ? `<button class="btn btn-sm btn-danger js-install-deps-card" title="kb-remote install-deps">
             <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
             Install deps
           </button>`
        : health.action === "stop-dev"
          ? `<button class="btn btn-sm btn-danger js-dev-stop-card" title="kb-dev --stop (kill the zombie tmux session)">
               <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="6" width="12" height="12" rx="1"/></svg>
               Stop dev
             </button>`
          : "";

  // deps mini-cell. Mirrors mut/dev rendering so the user can spot "node_modules
  // missing" at a glance without clicking through. State precedence matches
  // server.js: installing > ok > missing > unknown.
  const depsState = folder.deps?.state || "unknown";
  const depsShort = depsState === "ok" ? "installed"
    : depsState === "installing" ? "installing"
    : depsState === "missing" ? "missing"
    : "unknown";
  const depsDot = depsState === "ok" ? "ok"
    : depsState === "installing" ? "info"
    : depsState === "missing" ? "bad"
    : "unknown";
  const depsTip = depsState === "ok"
    ? `node_modules present on ${folder.mirror_path}`
    : depsState === "installing"
      ? `install session ${folder.installSession} is running in tmux on WSL`
      : depsState === "missing"
        ? `no node_modules on ${folder.mirror_path} — Start dev will fail until you run Install deps`
        : `SSH unreachable — deps state unknown`;

  return `
    <article class="card health-${health.kind}" data-path="${escapeHtml(folder.path)}">
      <header class="card-head" title="path: ${escapeHtml(folder.path)}&#10;mirror: ${escapeHtml(folder.mirror_path)}&#10;label: ${escapeHtml(folder.label)}&#10;port:  ${folder.port}">
        <div class="card-title">
          <span class="basename">${escapeHtml(basename)}</span>
          ${stack}
          ${wt}
        </div>
        <button class="copy-btn js-copy" data-value="${escapeHtml(folder.path)}" title="Copy folder path to clipboard">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
        </button>
      </header>

      <div class="health-row health-${health.color}" title="${escapeHtml(health.sub || "")}">
        <span class="status-dot dot-${health.color}"></span>
        <div class="health-text">
          <div class="health-label">${escapeHtml(health.label)}</div>
          <div class="health-sub muted">${escapeHtml(health.sub || "")}</div>
        </div>
        ${headerActionForHealth}
      </div>

      <div class="card-meta">
        <div class="meta-item" title="${escapeHtml(branchTip)}">
          <span class="meta-key">branch</span>
          <span class="meta-val mono ellipsis">${escapeHtml(folder.git?.branch || "—")}</span>
          ${folder.git?.dirty ? `<span class="pill pill-warn pill-xs">${folder.git.dirty}</span>` : ""}
        </div>
        <div class="meta-item" title="${escapeHtml(commitTip)}">
          <span class="meta-key">commit</span>
          ${folder.git?.commit
            ? `<span class="meta-val mono">${escapeHtml(folder.git.commit.hash)}</span><span class="meta-val muted small">${escapeHtml(folder.git.commit.ago)}</span>`
            : `<span class="meta-val muted small">—</span>`}
        </div>
        <div class="meta-item" title="${escapeHtml(mutTip)}">
          <span class="meta-key">sync</span>
          <span class="status-dot dot-${mutDot}"></span>
          <span class="meta-val ellipsis">${escapeHtml(mutShort)}</span>
        </div>
        <div class="meta-item" title="${escapeHtml(depsTip)}">
          <span class="meta-key">deps</span>
          <span class="status-dot dot-${depsDot}"></span>
          <span class="meta-val">${escapeHtml(depsShort)}</span>
        </div>
        <div class="meta-item" title="${escapeHtml(devTip)}">
          <span class="meta-key">dev</span>
          <span class="status-dot dot-${devDot}"></span>
          <span class="meta-val">${escapeHtml(devShort)}</span>
          <span class="meta-val muted small ellipsis">:${folder.port}</span>
        </div>
      </div>

      <footer class="card-foot">
        <div class="card-foot-tools" role="toolbar" aria-label="Housekeeping actions">
          <button class="btn icon-btn-sm js-refresh-sync" title="Re-create Mutagen sync session (kb-remote refresh) — use when sync looks stuck or you changed .gitignore">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3.5-7.1"/><path d="M21 4v5h-5"/></svg>
            <span class="sr-only">Re-create sync</span>
          </button>
          ${installIconButton(folder)}
          <button class="btn icon-btn-sm icon-btn-danger js-detach" title="Remove from dashboard (kb-remote detach) — terminates sync + frees port. Confirms before deleting WSL mirror.">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/><path d="M9 6V4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/></svg>
            <span class="sr-only">Remove</span>
          </button>
        </div>
        <span class="grow"></span>
        <div class="card-foot-actions">
          ${devButtonGroup(folder)}
          ${hosts.map((h) => {
            const url = `http://${h}:${folder.port}`;
            const tip = openEnabled ? `open ${url}` : openTip;
            // For multi-host we show just the hostname (no port) since the port
            // is the same for everything in the card and is already in the meta.
            const label = hosts.length > 1 ? `Open ${h}` : `Open :${folder.port}`;
            return `<a class="btn btn-sm ${openEnabled ? "btn-primary" : "btn-disabled"}"
               href="${escapeHtml(url)}"
               target="_blank" rel="noreferrer noopener"
               title="${escapeHtml(tip)}"
               ${openEnabled ? "" : `aria-disabled="true" onclick="event.preventDefault();"`}>
              ${escapeHtml(label)}
            </a>`;
          }).join("")}
        </div>
      </footer>
      <pre class="action-output" hidden>
        <button class="action-output-close" type="button" title="Hide output" aria-label="Hide output">×</button>
        <span class="action-output-body"></span>
      </pre>
    </article>
  `;
}

/**
 * Build the dev start/stop control. With multiple variants (e.g. new-kupibilet)
 * we render a split-button: primary half starts the currently-selected variant
 * in one click, the dropdown half opens a list to pick a different one. When
 * dev is already running we just render Stop; we don't expose variant switching
 * mid-flight (it would require Stop → Start which the user can do manually).
 *
 * When `folder.devReady` is false (deps missing or install running), we render
 * the Start button as disabled and surface `folder.devBlockedReason` as the
 * tooltip — so the user (and any agent reading the DOM) sees the exact reason
 * a click would silently do nothing.
 */
function devButtonGroup(folder) {
  if (folder.devRunning) {
    return `<button class="btn btn-sm btn-danger js-dev-stop">Stop dev</button>`;
  }
  const variants = folder.variants || [];
  const currentId = folder.variantId || (variants.find((v) => v.default)?.id ?? null);
  const blocked = folder.devReady === false;
  const blockTip = blocked ? folder.devBlockedReason || "Start dev is unavailable" : "";
  const disabledAttr = blocked ? "disabled aria-disabled=\"true\"" : "";
  const titleAttr = blocked ? `title="${escapeHtml(blockTip)}"` : "";
  // No variants registered for this stack → behave like the simple Start button.
  if (variants.length <= 1) {
    const label = currentId ? `Start dev (${currentId})` : "Start dev";
    return `<button class="btn btn-sm btn-primary js-dev-start" data-variant="${escapeHtml(currentId || "")}" ${disabledAttr} ${titleAttr}>${escapeHtml(label)}</button>`;
  }
  const opts = variants
    .map((v) => {
      const active = v.id === currentId;
      return `<button class="variant-option ${active ? "active" : ""}" data-variant="${escapeHtml(v.id)}" title="${escapeHtml(v.desc || "")}">
        <span class="variant-name">${escapeHtml(v.label)}</span>
        <span class="variant-desc muted">${escapeHtml(v.desc || "")}</span>
        ${active ? `<svg class="variant-check" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>` : ""}
      </button>`;
    })
    .join("");
  return `
    <div class="split-btn">
      <button class="btn btn-sm btn-primary split-btn-main js-dev-start" data-variant="${escapeHtml(currentId || "")}" ${disabledAttr} title="${escapeHtml(blocked ? blockTip : "Start dev with last-chosen variant")}">
        Start dev (${escapeHtml(currentId || "?")})
      </button>
      <button class="btn btn-sm btn-primary split-btn-toggle js-variant-toggle" ${disabledAttr} title="${escapeHtml(blocked ? blockTip : "Choose a different variant")}" aria-haspopup="true">
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
      </button>
      <div class="variant-popover" hidden role="menu">
        <div class="variant-head">Pick a variant to start</div>
        ${opts}
      </div>
    </div>
  `;
}

/**
 * Install-deps icon button for the card footer. Always rendered (so the user
 * has a manual escape hatch) but tone changes by deps.state:
 *   - ok          → muted ghost icon, tooltip "deps OK · re-run install"
 *   - missing     → destructive icon, urgent tooltip
 *   - installing  → busy spinner, disabled
 *   - unknown     → muted ghost icon
 * Keeps the footer compact: one square instead of a text button.
 */
function installIconButton(folder) {
  const state = folder.deps?.state || "unknown";
  const downloadSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`;
  if (state === "installing") {
    // Spinner-only — don't compose with the download icon (used to overflow
    // the 26×26 button via .btn-busy::after, see public/app.css `.spin`).
    const spinnerSvg = `<svg class="spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3.5-7.1"/><path d="M21 4v5h-5"/></svg>`;
    return `<button class="btn icon-btn-sm js-install-deps" disabled title="Installing deps in tmux session ${escapeHtml(folder.installSession)} — wait for it to finish.">
      ${spinnerSvg}
      <span class="sr-only">Installing deps</span>
    </button>`;
  }
  if (state === "missing") {
    return `<button class="btn icon-btn-sm icon-btn-danger js-install-deps" title="Install deps (kb-remote install-deps) — node_modules missing on WSL, Start dev will fail until you run this.">
      ${downloadSvg}
      <span class="sr-only">Install deps</span>
    </button>`;
  }
  const tip = state === "ok"
    ? "Re-run install (kb-remote install-deps) — deps already present, use when lockfile changed."
    : "Install deps (kb-remote install-deps) — SSH currently unreachable, will queue once host is back.";
  return `<button class="btn icon-btn-sm js-install-deps" title="${escapeHtml(tip)}">
    ${downloadSvg}
    <span class="sr-only">Install deps</span>
  </button>`;
}

function renderGlobalBanner(snap) {
  const list = $("#foldersList");
  const existing = list.querySelector(".global-banner");
  if (existing) existing.remove();

  const tunnelDown = snap.tunnel?.loaded === false || snap.tunnel?.state !== "running";
  const sshDown = !snap.ssh?.ok;
  // Only flag tunnel as a global problem when we'd actually want forwards
  // (i.e. there's at least one attached folder).
  if (!sshDown && !(tunnelDown && snap.folders.length > 0)) return;

  const isError = sshDown;
  const banner = document.createElement("div");
  banner.className = `global-banner ${isError ? "is-bad" : "is-warn"}`;
  banner.innerHTML = sshDown
    ? `<div class="banner-icon">⨯</div>
       <div class="banner-body">
         <strong>SSH to ${escapeHtml(snap.config.sshHost)} is down.</strong>
         <span class="muted">All cards below show last-known state, no actions will succeed.</span>
       </div>`
    : `<div class="banner-icon">⚠</div>
       <div class="banner-body">
         <strong>Autossh tunnel is stopped.</strong>
         <span class="muted">localhost:* port forwards aren't working. Dev sessions on WSL keep running; you just can't reach them from the Mac.</span>
       </div>
       <button class="btn btn-sm btn-primary js-banner-restart">
         <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-3.5-7.1"/><path d="M21 4v5h-5"/></svg>
         Restart tunnel
       </button>`;
  list.prepend(banner);
}

/**
 * Pretty labels and ordering for each stack header. `order` controls top-down
 * placement (lower = first), `label` is what we render in the section title.
 * Unknown stacks fall back to the raw id and slot in after the known ones.
 */
const STACK_META = {
  "new-kupibilet": { label: "new-kupibilet.ru", order: 0 },
  kupibilet:        { label: "kupibilet.ru (legacy)", order: 1 },
};

function renderFolders(snap) {
  const list = $("#foldersList");
  if (!snap.folders.length) {
    list.innerHTML = `
      <div class="empty">
        Нет attached папок.<br/>
        Сделай <code>kb-remote attach &lt;path&gt;</code> и обнови страницу.
      </div>
    `;
    return;
  }

  // Reuse existing card nodes' action-output text across re-renders.
  const existing = new Map(
    [...list.querySelectorAll(".card")].map((node) => [node.dataset.path, node]),
  );

  // Group by stack. Within a group, sort: main repo (is_worktree=false) first,
  // then worktrees alphabetically by label so a long-lived worktree list stays
  // stable across polls.
  const groups = new Map();
  for (const f of snap.folders) {
    if (!groups.has(f.stack)) groups.set(f.stack, []);
    groups.get(f.stack).push(f);
  }
  for (const arr of groups.values()) {
    arr.sort((a, b) => {
      if (a.is_worktree !== b.is_worktree) return a.is_worktree ? 1 : -1;
      return String(a.label).localeCompare(String(b.label));
    });
  }
  const sortedStacks = [...groups.keys()].sort((a, b) => {
    const oa = STACK_META[a]?.order ?? 100;
    const ob = STACK_META[b]?.order ?? 100;
    if (oa !== ob) return oa - ob;
    return a.localeCompare(b);
  });

  list.innerHTML = sortedStacks
    .map((stack) => renderStackSection(stack, groups.get(stack), snap))
    .join("");

  for (const card of list.querySelectorAll(".card")) {
    const path = card.dataset.path;
    const prev = existing.get(path);
    if (prev) {
      const prevOut = prev.querySelector(".action-output");
      const newOut = card.querySelector(".action-output");
      if (prevOut && !prevOut.hidden && newOut) {
        // Preserve the close-button child, only carry the textual body across renders.
        const prevBody = prev.querySelector(".action-output-body");
        const newBody = newOut.querySelector(".action-output-body");
        if (newBody) newBody.textContent = prevBody?.textContent ?? prevOut.textContent;
        newOut.hidden = false;
      }
    }
  }

  renderGlobalBanner(snap);
  wireFolderActions();
  wireBannerActions();
}

/**
 * Render a single stack section: header (pretty name + folder counts) and a
 * grid of cards. The grid is the same auto-fit minmax responsive layout as
 * before, just scoped per-section so cards from different stacks never share
 * a row.
 */
function renderStackSection(stack, folders, snap) {
  const meta = STACK_META[stack] || { label: stack };
  const total = folders.length;
  const live = folders.filter((f) => computeHealth(f, snap).kind === "live").length;
  const wts = folders.filter((f) => f.is_worktree).length;
  const summaryBits = [`${total} ${total === 1 ? "folder" : "folders"}`];
  if (wts > 0) summaryBits.push(`${wts} worktree${wts === 1 ? "" : "s"}`);
  if (live > 0) summaryBits.push(`${live} live`);
  return `
    <section class="folder-section" data-stack="${escapeHtml(stack)}">
      <header class="folder-section-head">
        <h2 class="folder-section-title">${escapeHtml(meta.label)}</h2>
        <span class="folder-section-meta muted">${escapeHtml(summaryBits.join(" · "))}</span>
      </header>
      <div class="folder-section-grid">
        ${folders.map((f) => cardForFolder(f, snap)).join("")}
      </div>
    </section>
  `;
}

// ─── action wiring ─────────────────────────────────────────────────────────

function setBusy(btn, on) {
  if (!btn) return;
  btn.classList.toggle("btn-busy", on);
  btn.disabled = on;
}

function showOutput(card, text) {
  const out = card.querySelector(".action-output");
  if (!out) return;
  const body = out.querySelector(".action-output-body");
  if (body) body.textContent = text;
  else out.textContent = text;
  out.hidden = !text;
}

function hideOutput(card) {
  const out = card?.querySelector?.(".action-output");
  if (!out) return;
  out.hidden = true;
  const body = out.querySelector(".action-output-body");
  if (body) body.textContent = "";
}

/**
 * Persist the chosen variant for a folder without starting dev. Updates the
 * split-button label and popover checkmark in place so the user gets instant
 * feedback; server PATCH happens in the background, errors fall back to a toast.
 */
async function selectVariant(card, path, variant) {
  const mainBtn = card.querySelector(".split-btn-main");
  if (mainBtn) {
    mainBtn.dataset.variant = variant;
    mainBtn.textContent = `Start dev (${variant})`;
  }
  for (const opt of card.querySelectorAll(".variant-option")) {
    const isActive = opt.dataset.variant === variant;
    opt.classList.toggle("active", isActive);
    let check = opt.querySelector(".variant-check");
    if (isActive && !check) {
      check = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      check.setAttribute("class", "variant-check");
      check.setAttribute("width", "14");
      check.setAttribute("height", "14");
      check.setAttribute("viewBox", "0 0 24 24");
      check.setAttribute("fill", "none");
      check.setAttribute("stroke", "currentColor");
      check.setAttribute("stroke-width", "2.4");
      check.setAttribute("stroke-linecap", "round");
      check.setAttribute("stroke-linejoin", "round");
      check.innerHTML = `<polyline points="20 6 9 17 4 12"/>`;
      opt.appendChild(check);
    } else if (!isActive && check) {
      check.remove();
    }
  }
  try {
    const r = await postAction("/api/actions/set-variant", { path, variant });
    if (!r.ok) toast(`save variant failed: ${r.stderr || r.code}`, "bad");
  } catch (err) {
    toast(`save variant failed: ${err.message || err}`, "bad");
  }
}

async function runFolderAction(card, path, endpoint, btn, friendlyName, extraBody = {}) {
  setBusy(btn, true);
  showOutput(card, `$ ${friendlyName} ${path}\n`);
  try {
    const r = await postAction(endpoint, { path, ...extraBody });
    const out = `$ ${friendlyName} ${path}\n[exit ${r.code ?? "-"}]\n${r.stdout || ""}${r.stderr ? `\n---stderr---\n${r.stderr}` : ""}`;
    showOutput(card, out);
    if (r.ok) toast(`${friendlyName} OK`, "ok");
    else toast(`${friendlyName} failed (exit ${r.code ?? "-"})`, "bad");
  } catch (err) {
    showOutput(card, String(err));
    toast(`${friendlyName} failed: ${err.message || err}`, "bad");
  } finally {
    setBusy(btn, false);
    refresh({ force: true });
  }
}

function wireFolderActions() {
  for (const card of document.querySelectorAll(".card")) {
    const path = card.dataset.path;

    const refreshHandler = (e) => runFolderAction(
      card, path, "/api/actions/mutagen-refresh", e.currentTarget, "kb-remote refresh",
    );
    card.querySelector(".js-refresh-sync")?.addEventListener("click", refreshHandler);
    card.querySelector(".js-refresh-sync-card")?.addEventListener("click", refreshHandler);

    card.querySelector(".js-dev-start")?.addEventListener("click", (e) => {
      const btn = e.currentTarget;
      if (btn.disabled || btn.getAttribute("aria-disabled") === "true") {
        // Surface the exact reason as a toast so a stray click still teaches.
        const reason = btn.getAttribute("title") || "Start dev is unavailable";
        toast(reason, "warn", { timeout: 5000 });
        return;
      }
      const variant = btn.dataset.variant || null;
      runFolderAction(
        card, path, "/api/actions/dev-start", btn,
        variant ? `kb-dev --bg --variant ${variant}` : "kb-dev --bg",
        { variant },
      );
    });
    // Variant dropdown: toggle visibility, then handle item clicks. Popover is
    // position:fixed so we compute coordinates from the toggle's bounding rect
    // and flip above/below depending on viewport space.
    const variantToggle = card.querySelector(".js-variant-toggle");
    const variantPopover = card.querySelector(".variant-popover");
    if (variantToggle && variantPopover) {
      variantToggle.addEventListener("click", (e) => {
        e.stopPropagation();
        for (const other of document.querySelectorAll(".variant-popover")) {
          if (other !== variantPopover) other.hidden = true;
        }
        if (variantPopover.hidden) {
          variantPopover.hidden = false;
          positionPopover(variantToggle, variantPopover);
        } else {
          variantPopover.hidden = true;
        }
      });
      for (const opt of variantPopover.querySelectorAll(".variant-option")) {
        opt.addEventListener("click", async (e) => {
          e.stopPropagation();
          const variant = opt.dataset.variant;
          variantPopover.hidden = true;
          await selectVariant(card, path, variant);
        });
      }
    }
    card.querySelector(".js-dev-stop")?.addEventListener("click", (e) => {
      runFolderAction(card, path, "/api/actions/dev-stop", e.currentTarget, "kb-dev --stop");
    });
    // Install deps — both the footer button and the in-banner CTA when
    // health.action === "install-deps" route through the same endpoint.
    const installHandler = (e) => runFolderAction(
      card, path, "/api/actions/install-deps", e.currentTarget, "kb-remote install-deps",
    );
    card.querySelector(".js-install-deps")?.addEventListener("click", installHandler);
    card.querySelector(".js-install-deps-card")?.addEventListener("click", installHandler);
    card.querySelector(".js-restart-tunnel-card")?.addEventListener("click", async (e) => {
      const btn = e.currentTarget;
      setBusy(btn, true);
      try {
        const r = await postAction("/api/actions/tunnel-restart");
        if (r.ok) toast("autossh tunnel restarted", "ok");
        else toast(`tunnel restart failed (exit ${r.code ?? "-"})`, "bad");
      } catch (err) {
        toast(`tunnel restart failed: ${err.message || err}`, "bad");
      } finally {
        setBusy(btn, false);
        refresh({ force: true });
      }
    });
    card.querySelector(".js-copy")?.addEventListener("click", async (e) => {
      const btn = e.currentTarget;
      const val = btn.dataset.value;
      try {
        await navigator.clipboard.writeText(val);
        btn.classList.add("flash-ok");
        setTimeout(() => btn.classList.remove("flash-ok"), 700);
      } catch {
        toast("clipboard write failed", "bad");
      }
    });
    card.querySelector(".js-detach")?.addEventListener("click", (e) => {
      e.preventDefault();
      const snap = window.__lastSnap;
      const folder = snap?.folders?.find((f) => f.path === path);
      openDetachModal(folder || { path, label: path });
    });
    card.querySelector(".action-output-close")?.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      hideOutput(card);
    });
  }
}

// ─── detach modal ───────────────────────────────────────────────────────────

let detachTarget = null; // { path, label, port }

function openDetachModal(folder) {
  const modal = $("#detachModal");
  if (!modal) return;
  detachTarget = { path: folder.path, label: folder.label, port: folder.port };
  $("#detachModalTitle").textContent = `Detach ${folder.label}?`;
  $("#detachModalSub").textContent = folder.path;
  $("#detachPurgeCheck").checked = false;
  const confirmBtn = $("#detachConfirmBtn");
  setBusy(confirmBtn, false);
  confirmBtn.textContent = "Detach";
  modal.hidden = false;
  // Focus the cancel button so Enter doesn't immediately confirm destructive op.
  $("#detachCancelBtn")?.focus();
}

function closeDetachModal() {
  const modal = $("#detachModal");
  if (modal) modal.hidden = true;
  detachTarget = null;
}

async function confirmDetach() {
  if (!detachTarget) return;
  const { path, label } = detachTarget;
  const purgeMirror = $("#detachPurgeCheck")?.checked === true;
  const confirmBtn = $("#detachConfirmBtn");
  setBusy(confirmBtn, true);
  try {
    const r = await postAction("/api/actions/detach", { path, purgeMirror });
    if (r.ok) {
      toast(`detached: ${label}${purgeMirror ? " (mirror purged)" : ""}`, "ok");
      closeDetachModal();
      refresh({ force: true });
    } else {
      toast(`detach failed: ${r.error || r.stderr || `exit ${r.code ?? "-"}`}`, "bad", { timeout: 7000 });
      setBusy(confirmBtn, false);
    }
  } catch (err) {
    toast(`detach failed: ${err.message || err}`, "bad");
    setBusy(confirmBtn, false);
  }
}

/**
 * Place a popover relative to its toggle button. Prefers above the toggle (so
 * it floats over the card body, which feels natural for a footer button); if
 * there isn't enough room above, flips below. Right-aligns to the toggle so
 * the chevron stays under the dropdown.
 */
function positionPopover(toggle, popover) {
  const togRect = toggle.getBoundingClientRect();
  // Reset to natural size, measure, then place.
  popover.style.top = "0px";
  popover.style.left = "0px";
  const popRect = popover.getBoundingClientRect();
  const margin = 6;
  const vpW = window.innerWidth;
  const vpH = window.innerHeight;

  // Vertical: prefer above; if not enough room, flip below.
  let top = togRect.top - popRect.height - margin;
  if (top < margin) {
    top = togRect.bottom + margin;
    // If neither fits cleanly, clamp to the larger gap and let max-height + scroll handle the rest.
    if (top + popRect.height > vpH - margin) {
      top = Math.max(margin, vpH - popRect.height - margin);
    }
  }

  // Horizontal: right-align to the toggle, but stay within viewport.
  let left = togRect.right - popRect.width;
  if (left < margin) left = margin;
  if (left + popRect.width > vpW - margin) left = vpW - popRect.width - margin;

  popover.style.top = `${top}px`;
  popover.style.left = `${left}px`;
}

function wireBannerActions() {
  $(".global-banner .js-banner-restart")?.addEventListener("click", async (e) => {
    const btn = e.currentTarget;
    setBusy(btn, true);
    try {
      const r = await postAction("/api/actions/tunnel-restart");
      if (r.ok) toast("autossh tunnel restarted", "ok");
      else toast(`tunnel restart failed (exit ${r.code ?? "-"})`, "bad", { timeout: 7000 });
    } catch (err) {
      toast(`tunnel restart failed: ${err.message || err}`, "bad");
    } finally {
      setBusy(btn, false);
      refresh({ force: true });
    }
  });
}

// ─── attach popover ─────────────────────────────────────────────────────────

let attachPreviewSeq = 0;
let attachPreviewState = null; // last successful preview, ready to submit

function openAttachPopover() {
  const pop = $("#attachPopover");
  if (!pop) return;
  pop.hidden = false;
  const attachInput = $("#attachInput");
  if (attachInput) attachInput.value = "";
  attachPreviewState = null;
  updateAttachPreview({ ok: false, idle: true });
  const out = $("#attachOut");
  if (out) { out.hidden = true; out.textContent = ""; out.classList.remove("is-bad"); }
  loadAttachCandidates();
  populateWizardParents();
  // Defer focus past the open animation so the caret lands in the wizard
  // branch field (the primary action) rather than the attach-existing input.
  requestAnimationFrame(() => $("#wizardBranch")?.focus());
}

function closeAttachPopover() {
  const pop = $("#attachPopover");
  if (pop) pop.hidden = true;
}

async function loadAttachCandidates() {
  const host = $("#attachSuggested");
  if (!host) return;
  host.innerHTML = `<div class="attach-suggested-empty">Loading…</div>`;
  try {
    const r = await fetch(`${apiBase}/api/attach-candidates`, { cache: "no-store" });
    const json = await r.json();
    renderAttachCandidates(json);
  } catch (err) {
    host.innerHTML = `<div class="attach-suggested-empty">Failed to load: ${escapeHtml(String(err.message || err))}</div>`;
  }
}

function renderAttachCandidates(json) {
  const host = $("#attachSuggested");
  if (!host) return;
  if (!json?.ok) {
    host.innerHTML = `<div class="attach-suggested-empty">Cannot scan ~/Documents: ${escapeHtml(json?.error || "unknown error")}</div>`;
    return;
  }
  const list = json.candidates || [];
  if (list.length === 0) {
    host.innerHTML = `<div class="attach-suggested-empty">No unattached folders in ~/Documents that match kb-remote naming convention.</div>`;
    return;
  }
  host.innerHTML = list
    .map((c) => {
      const wtPill = c.isWorktree
        ? `<span class="attach-pill is-wt">worktree</span>`
        : `<span class="attach-pill is-main">main</span>`;
      const stackPill = `<span class="attach-pill">${escapeHtml(c.stack)}</span>`;
      const portText = c.suggestedPort
        ? `port: <span class="port mono">:${c.suggestedPort}</span>`
        : `<span class="muted">no free port</span>`;
      return `
        <div class="attach-suggested-row" data-path="${escapeHtml(c.path)}">
          <div class="meta">
            <span class="basename">${escapeHtml(c.basename)}</span>
            <span class="info">${stackPill}${wtPill}<span>${portText}</span></span>
          </div>
          <button class="btn btn-sm btn-primary js-attach-suggested" ${c.suggestedPort ? "" : "disabled"} data-path="${escapeHtml(c.path)}">
            Attach
          </button>
        </div>
      `;
    })
    .join("");
  for (const btn of host.querySelectorAll(".js-attach-suggested")) {
    btn.addEventListener("click", (e) => {
      const p = e.currentTarget.dataset.path;
      submitAttach(p, e.currentTarget);
    });
  }
}

// Reusable HTML escape just for inline preview spans.
function attachInfoSpans(state) {
  const stackPill = `<span class="attach-pill">${escapeHtml(state.stack)}</span>`;
  const wtPill = state.isWorktree
    ? `<span class="attach-pill is-wt">worktree</span>`
    : `<span class="attach-pill is-main">main</span>`;
  return `${stackPill}${wtPill}`;
}

function updateAttachPreview(result) {
  const el = $("#attachPreview");
  const submit = $("#attachSubmitBtn");
  if (!el || !submit) return;
  el.classList.remove("is-ok", "is-bad");
  if (result.idle) {
    el.textContent = "Enter a path to validate.";
    submit.disabled = true;
    attachPreviewState = null;
    return;
  }
  if (result.ok) {
    el.classList.add("is-ok");
    el.innerHTML = `${attachInfoSpans(result)} <span>port: <span class="port mono">:${result.suggestedPort}</span> (next free)</span>`;
    submit.disabled = false;
    attachPreviewState = result;
  } else {
    el.classList.add("is-bad");
    el.textContent = result.error || "invalid path";
    submit.disabled = true;
    attachPreviewState = null;
  }
}

let attachPreviewTimer = null;
function scheduleAttachPreview(rawPath) {
  if (attachPreviewTimer) clearTimeout(attachPreviewTimer);
  if (!rawPath.trim()) {
    updateAttachPreview({ ok: false, idle: true });
    return;
  }
  attachPreviewTimer = setTimeout(() => fetchAttachPreview(rawPath), 220);
}

async function fetchAttachPreview(rawPath) {
  const seq = ++attachPreviewSeq;
  try {
    const r = await fetch(
      `${apiBase}/api/attach-preview?path=${encodeURIComponent(rawPath)}`,
      { cache: "no-store" },
    );
    const json = await r.json();
    // Discard stale responses (user kept typing).
    if (seq !== attachPreviewSeq) return;
    updateAttachPreview(json);
  } catch (err) {
    if (seq !== attachPreviewSeq) return;
    updateAttachPreview({ ok: false, error: String(err.message || err) });
  }
}

async function submitAttach(path, triggerBtn = null) {
  const out = $("#attachOut");
  const submit = triggerBtn || $("#attachSubmitBtn");
  if (out) { out.hidden = true; out.textContent = ""; out.classList.remove("is-bad"); }
  setBusy(submit, true);
  // Also disable the form-level submit so a second click during a suggested-row
  // attach doesn't double-fire.
  const formSubmit = $("#attachSubmitBtn");
  if (formSubmit && submit !== formSubmit) setBusy(formSubmit, true);
  try {
    const r = await postAction("/api/actions/attach", { path });
    if (r.ok) {
      toast(`attached: ${r.label}${r.stack ? ` (${r.stack})` : ""}`, "ok");
      closeAttachPopover();
      refresh({ force: true });
    } else {
      const msg = r.error || r.stderr || r.stdout || `exit ${r.code ?? "-"}`;
      if (out) {
        out.hidden = false;
        out.classList.add("is-bad");
        out.textContent = msg;
      }
      toast(`attach failed: ${truncate(msg, 80)}`, "bad", { timeout: 7000 });
    }
  } catch (err) {
    if (out) {
      out.hidden = false;
      out.classList.add("is-bad");
      out.textContent = String(err.message || err);
    }
    toast(`attach failed: ${err.message || err}`, "bad");
  } finally {
    setBusy(submit, false);
    if (formSubmit && submit !== formSubmit) setBusy(formSubmit, false);
  }
}

function truncate(s, max) {
  if (typeof s !== "string") return String(s);
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}

// ─── worktree wizard ────────────────────────────────────────────────────────

let wizardBranches = { local: [], origin: [], current: null };
let wizardBranchesLoading = false;

function populateWizardParents() {
  const select = $("#wizardParent");
  if (!select) return;
  const snap = window.__lastSnap;
  const parents = (snap?.folders || []).filter((f) => !f.is_worktree);
  const prev = select.value;
  // Preserve current selection across re-populations (snapshot polls every 5s).
  select.innerHTML = parents
    .map((f) => `<option value="${escapeHtml(f.path)}">${escapeHtml(f.path.split("/").pop())} (${escapeHtml(f.stack)})</option>`)
    .join("");
  if (parents.length === 0) {
    select.innerHTML = `<option value="">— no main checkouts attached —</option>`;
    select.disabled = true;
  } else {
    select.disabled = false;
    if (prev && parents.some((p) => p.path === prev)) {
      select.value = prev;
    } else {
      select.value = parents[0].path;
    }
  }
  // Whenever parent changes (or is first populated), refresh branches.
  loadWizardBranches();
}

async function loadWizardBranches() {
  const select = $("#wizardParent");
  const parent = select?.value;
  const preview = $("#wizardPreview");
  if (!parent) {
    wizardBranches = { local: [], origin: [], current: null };
    refreshWizardDatalist();
    refreshWizardPreview();
    return;
  }
  wizardBranchesLoading = true;
  if (preview) {
    preview.classList.remove("is-ok", "is-bad");
    preview.textContent = `Loading branches (git fetch on ${parent.split("/").pop()})…`;
  }
  try {
    const r = await fetch(
      `${apiBase}/api/branches?parentPath=${encodeURIComponent(parent)}`,
      { cache: "no-store" },
    );
    const json = await r.json();
    if (!json.ok) {
      wizardBranches = { local: [], origin: [], current: null };
      if (preview) { preview.classList.add("is-bad"); preview.textContent = json.error || "could not list branches"; }
    } else {
      wizardBranches = json;
    }
  } catch (err) {
    if (preview) { preview.classList.add("is-bad"); preview.textContent = String(err.message || err); }
  } finally {
    wizardBranchesLoading = false;
    refreshWizardDatalist();
    refreshWizardPreview();
  }
}

function refreshWizardDatalist() {
  const dl = $("#wizardBranchList");
  if (!dl) return;
  // Dedup + sort so the dropdown is sane. Mark origin-only with a hint so the
  // user knows it's not yet local (datalist doesn't allow arbitrary HTML, so
  // we use the `label` attr which most browsers expose as a hint column).
  const local = new Set(wizardBranches.local || []);
  const origin = new Set(wizardBranches.origin || []);
  const all = new Set([...local, ...origin]);
  const items = [...all].sort();
  dl.innerHTML = items
    .map((b) => {
      let hint;
      if (local.has(b) && origin.has(b)) hint = "local + origin";
      else if (local.has(b)) hint = "local only";
      else hint = "origin only";
      return `<option value="${escapeHtml(b)}" label="${escapeHtml(hint)}"></option>`;
    })
    .join("");
}

function refreshWizardPreview() {
  const preview = $("#wizardPreview");
  const submit = $("#wizardSubmitBtn");
  const branchInput = $("#wizardBranch");
  const parent = $("#wizardParent")?.value;
  if (!preview || !submit || !branchInput) return;
  preview.classList.remove("is-ok", "is-bad");
  const branch = branchInput.value.trim();
  if (!parent) {
    preview.textContent = "No main checkout attached — go attach the base repo first.";
    submit.disabled = true;
    return;
  }
  if (wizardBranchesLoading) {
    preview.textContent = "Loading branches…";
    submit.disabled = true;
    return;
  }
  if (!branch) {
    preview.textContent = `Pick or type a branch. ${wizardBranches.current ? `Current HEAD: ${wizardBranches.current}.` : ""}`;
    submit.disabled = true;
    return;
  }
  // Validate branch shape mirror of server check.
  if (!/^[\w./-][\w./+-]*$/.test(branch) || branch.includes("..") || branch.startsWith("-")) {
    preview.classList.add("is-bad");
    preview.textContent = `invalid branch name: ${branch}`;
    submit.disabled = true;
    return;
  }
  const inLocal = wizardBranches.local.includes(branch);
  const inOrigin = wizardBranches.origin.includes(branch);
  const repoBase = parent.split("/").pop();
  const sanitized = branch.replace(/\//g, "-").replace(/[^A-Za-z0-9._-]/g, "_");
  const targetFolder = `${repoBase}-${sanitized}`;
  let badge, action;
  if (inLocal && inOrigin) {
    badge = `<span class="wizard-badge is-both">local + origin</span>`;
    action = `git worktree add → <span class="mono">${escapeHtml(branch)}</span>`;
  } else if (inLocal) {
    badge = `<span class="wizard-badge is-local">local only</span>`;
    action = `git worktree add → <span class="mono">${escapeHtml(branch)}</span>`;
  } else if (inOrigin) {
    badge = `<span class="wizard-badge is-origin">origin only</span>`;
    action = `checkout <span class="mono">origin/${escapeHtml(branch)}</span> with tracking`;
  } else {
    badge = `<span class="wizard-badge is-new">new</span>`;
    action = `branch from <span class="mono">origin/dev</span>`;
  }
  preview.classList.add("is-ok");
  preview.innerHTML = `${badge} ${action} · folder <span class="mono">${escapeHtml(targetFolder)}</span>`;
  submit.disabled = false;
}

function syncWizardInstallEnabled() {
  // Skill: install-deps requires kb-remote attach to have created the mirror first.
  // If the user unchecks Attach, deps install is meaningless → disable + uncheck.
  const attach = $("#wizardAutoAttach")?.checked;
  const install = $("#wizardAutoInstall");
  const label = $("#wizardAutoInstallLabel");
  if (!install || !label) return;
  if (!attach) {
    install.checked = false;
    install.disabled = true;
    label.classList.add("is-disabled");
  } else {
    install.disabled = false;
    label.classList.remove("is-disabled");
  }
}

async function submitWizard() {
  const submit = $("#wizardSubmitBtn");
  const out = $("#wizardOut");
  const parent = $("#wizardParent")?.value;
  const branch = $("#wizardBranch")?.value.trim();
  if (!parent || !branch) return;
  if (out) { out.hidden = true; out.textContent = ""; out.classList.remove("is-bad"); }
  setBusy(submit, true);
  try {
    const r = await postAction("/api/actions/worktree-create", {
      parentPath: parent,
      branch,
      copyEnv: $("#wizardCopyEnv")?.checked,
      autoAttach: $("#wizardAutoAttach")?.checked,
      autoInstall: $("#wizardAutoInstall")?.checked,
    });
    const renderedSteps = (r.steps || [])
      .map((s) => `${s.ok ? "✓" : "✗"} ${s.name}${s.code !== 0 ? ` (exit ${s.code})` : ""}${s.stderr ? `\n   ${s.stderr.split("\n").join("\n   ")}` : ""}`)
      .join("\n");
    if (r.ok) {
      toast(`worktree created: ${r.label || branch}${r.port ? ` on port :${r.port}` : ""}`, "ok");
      // Optionally surface the step log briefly before we close, so the user
      // sees the result of each step. The new card will appear on next refresh.
      if (out && renderedSteps) {
        out.hidden = false;
        out.textContent = `→ ${r.newPath}\n${renderedSteps}`;
      }
      // Give the toast a beat, then close + refresh.
      setTimeout(() => { closeAttachPopover(); refresh({ force: true }); }, 1200);
    } else {
      if (out) {
        out.hidden = false;
        out.classList.add("is-bad");
        out.textContent = `${r.error || "create failed"}\n\n${renderedSteps}`.trim();
      }
      toast(`worktree failed: ${truncate(r.error || "unknown error", 80)}`, "bad", { timeout: 7000 });
    }
  } catch (err) {
    if (out) { out.hidden = false; out.classList.add("is-bad"); out.textContent = String(err.message || err); }
    toast(`worktree failed: ${err.message || err}`, "bad");
  } finally {
    setBusy(submit, false);
  }
}

// ─── global wiring ─────────────────────────────────────────────────────────

let pollTimer = null;

async function refresh({ force = false } = {}) {
  try {
    const snap = await fetchSnapshot({ force });
    renderStatusBar(snap);
    renderFolders(snap);
    maybeAutoOpenDebug();
  } catch (err) {
    toast(`fetch /api/snapshot failed: ${err.message || err}`, "bad", { timeout: 6000 });
    // Show inline error so the user knows the dashboard isn't frozen.
    const loading = $("#loadingState");
    if (loading) {
      loading.textContent = `Cannot reach kb-remote-ui server. Is it running?\nTried: ${apiBase || window.location.origin}`;
    }
  }
}

/**
 * Debug helper: when loaded with `?debug=variant`, open the first card's
 * variant popover on initial render. Used by screenshot tooling; harmless
 * for normal users.
 */
function maybeAutoOpenDebug() {
  if (window.__debugOpened) return;
  const debug = new URLSearchParams(window.location.search).get("debug");
  if (!debug) return;
  // Supports: ?debug=variant (first card) or ?debug=variant:N (Nth card, 0-indexed).
  const match = /^variant(?::(\d+))?$/.exec(debug);
  if (match) {
    const idx = Number(match[1] || 0);
    const toggles = document.querySelectorAll(".js-variant-toggle");
    if (toggles[idx]) {
      toggles[idx].click();
      window.__debugOpened = true;
    }
  }
}

function startPolling() {
  refresh().catch(() => {});
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = setInterval(() => refresh().catch(() => {}), POLL_MS);
}

document.addEventListener("DOMContentLoaded", () => {
  startPolling();

  $("#refreshBtn").addEventListener("click", () => refresh({ force: true }));

  $("#restartTunnelBtn").addEventListener("click", async (e) => {
    const btn = e.currentTarget;
    setBusy(btn, true);
    try {
      const r = await postAction("/api/actions/tunnel-restart");
      if (r.ok) toast("autossh tunnel restarted", "ok");
      else toast(`tunnel restart failed (exit ${r.code ?? "-"}): ${r.stderr || r.error || ""}`, "bad", { timeout: 7000 });
    } catch (err) {
      toast(`tunnel restart failed: ${err.message || err}`, "bad");
    } finally {
      setBusy(btn, false);
      refresh({ force: true });
    }
  });

  // Theme popover.
  const themeBtn = $("#themeBtn");
  const themePop = $("#themePopover");
  themeBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    themePop.hidden = !themePop.hidden;
    refreshThemePopover();
  });

  // Attach popover.
  const attachBtn = $("#attachBtn");
  const attachPop = $("#attachPopover");
  attachBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    if (attachPop.hidden) openAttachPopover();
    else closeAttachPopover();
  });
  $("#attachCancelBtn")?.addEventListener("click", closeAttachPopover);
  $("#attachInput")?.addEventListener("input", (e) => {
    scheduleAttachPreview(e.currentTarget.value);
  });
  $("#attachInput")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && attachPreviewState) {
      e.preventDefault();
      submitAttach(attachPreviewState.path);
    }
  });
  $("#attachSubmitBtn")?.addEventListener("click", () => {
    if (attachPreviewState) submitAttach(attachPreviewState.path);
  });

  // Worktree wizard
  $("#wizardParent")?.addEventListener("change", () => {
    loadWizardBranches();
  });
  $("#wizardBranch")?.addEventListener("input", refreshWizardPreview);
  $("#wizardBranch")?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      const submit = $("#wizardSubmitBtn");
      if (submit && !submit.disabled) submitWizard();
    }
  });
  $("#wizardAutoAttach")?.addEventListener("change", syncWizardInstallEnabled);
  $("#wizardSubmitBtn")?.addEventListener("click", submitWizard);

  // Detach modal.
  const detachModal = $("#detachModal");
  $("#detachCancelBtn")?.addEventListener("click", closeDetachModal);
  $("#detachConfirmBtn")?.addEventListener("click", confirmDetach);
  detachModal?.addEventListener("click", (e) => {
    // Click on the backdrop (the element itself) closes; clicks on .modal don't bubble here.
    if (e.target === detachModal) closeDetachModal();
  });

  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    if (detachModal && !detachModal.hidden) { closeDetachModal(); return; }
    if (attachPop && !attachPop.hidden) { closeAttachPopover(); return; }
    if (themePop && !themePop.hidden) { themePop.hidden = true; return; }
    for (const pop of document.querySelectorAll(".variant-popover:not([hidden])")) {
      pop.hidden = true;
    }
  });

  document.addEventListener("click", (e) => {
    if (!themePop.hidden && !themePop.contains(e.target) && e.target !== themeBtn) {
      themePop.hidden = true;
    }
    // Close attach popover on outside click (but not on its own toggle).
    if (attachPop && !attachPop.hidden) {
      if (!attachPop.contains(e.target) && e.target !== attachBtn && !attachBtn?.contains(e.target)) {
        closeAttachPopover();
      }
    }
    // Close any open variant popovers when clicking outside their card-foot.
    for (const pop of document.querySelectorAll(".variant-popover:not([hidden])")) {
      const split = pop.closest(".split-btn");
      if (!split || !split.contains(e.target)) pop.hidden = true;
    }
  });
  for (const opt of themePop.querySelectorAll(".theme-option")) {
    opt.addEventListener("click", () => {
      applyTheme(opt.dataset.theme);
      themePop.hidden = true;
    });
  }

  // Keep "Xs ago" label fresh between polls.
  setInterval(() => {
    const snap = window.__lastSnap;
    if (snap?.generatedAt) {
      $("#lastRefresh").textContent = relativeTime(snap.generatedAt);
    }
  }, 1000);
});

