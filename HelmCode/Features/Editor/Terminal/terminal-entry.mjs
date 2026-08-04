/**
 * HelmCode WebSSH client (xterm.js) for WKWebView.
 *
 * Protocol (runner-core docs/api/terminal.md):
 *   WS /v1/terminal?cols=&rows=&token=
 *   binary  ↔ PTY data
 *   text JSON control: resize | ping | ready | error | exit | pong
 *
 * Note: @xterm/addon-attach is NOT used — the wire format mixes binary PTY
 * frames with JSON control text. We attach manually (same semantics as AttachAddon
 * for data, plus control handling + resize).
 *
 * Resize on iPad:
 *   FitAddon measures the #terminal DOM box → term.cols/rows.
 *   visualViewport + window resize (keyboard / rotation / Stage Manager) re-fit
 *   and send { type: "resize", cols, rows } so Docker TTY matches the grid.
 */

import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";
// xterm.css is injected by rebuild-terminal.sh shim (esbuild text loader).

/**
 * Match iOS `UIColor.systemBackground` used by the center editor column
 * (`Color(.systemBackground)` on code / welcome surfaces).
 */
const THEMES = {
  dark: {
    background: "#000000",
    foreground: "#e5e5ea",
    cursor: "#e5e5ea",
    cursorAccent: "#000000",
    selectionBackground: "#3a3a3c",
    selectionForeground: "#ffffff",
    black: "#000000",
    red: "#ff453a",
    green: "#30d158",
    yellow: "#ffd60a",
    blue: "#0a84ff",
    magenta: "#bf5af2",
    cyan: "#64d2ff",
    white: "#e5e5ea",
    brightBlack: "#8e8e93",
    brightRed: "#ff6961",
    brightGreen: "#30db5b",
    brightYellow: "#ffd426",
    brightBlue: "#409cff",
    brightMagenta: "#da8fff",
    brightCyan: "#70d7ff",
    brightWhite: "#ffffff",
  },
  light: {
    background: "#ffffff",
    foreground: "#1c1c1e",
    cursor: "#1c1c1e",
    cursorAccent: "#ffffff",
    selectionBackground: "#b3d7ff",
    selectionForeground: "#000000",
    black: "#1c1c1e",
    red: "#d70015",
    green: "#248a3d",
    yellow: "#b25000",
    blue: "#0040dd",
    magenta: "#8944ab",
    cyan: "#0071a4",
    white: "#8e8e93",
    brightBlack: "#636366",
    brightRed: "#ff453a",
    brightGreen: "#28cd41",
    brightYellow: "#ff9f0a",
    brightBlue: "#0a84ff",
    brightMagenta: "#bf5af2",
    brightCyan: "#55bef0",
    brightWhite: "#000000",
  },
};

function resolveInitialScheme() {
  try {
    if (window.matchMedia?.("(prefers-color-scheme: dark)").matches) {
      return "dark";
    }
  } catch {
    /* ignore */
  }
  return "light";
}

let colorScheme = resolveInitialScheme();

function applyDocumentScheme(scheme) {
  const root = document.documentElement;
  root.dataset.helmScheme = scheme;
  root.style.colorScheme = scheme;
  const theme = THEMES[scheme] || THEMES.dark;
  root.style.setProperty("--bg", theme.background);
  root.style.setProperty("--fg", theme.foreground);
  if (document.body) {
    document.body.style.background = theme.background;
    document.body.style.color = theme.foreground;
  }
}

function xtermThemeFor(scheme) {
  return THEMES[scheme] || THEMES.dark;
}

applyDocumentScheme(colorScheme);

const term = new Terminal({
  cursorBlink: true,
  cursorStyle: "block",
  fontSize: 13,
  fontFamily:
    'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace',
  // Integer line metrics reduce sub-pixel overflow that clips the last row
  // inside WKWebView (FitAddon otherwise over-commits by ~1 cell).
  lineHeight: 1.0,
  scrollback: 5000,
  allowProposedApi: true,
  convertEol: false,
  theme: xtermThemeFor(colorScheme),
});

const fitAddon = new FitAddon();
term.loadAddon(fitAddon);
term.loadAddon(new WebLinksAddon());
term.open(document.getElementById("terminal"));

let socket = null;
let disposed = false;
let autoReconnect = true;
let resizeTimer = null;
let pingTimer = null;
let baseURL = "";
let apiToken = "";

const encoder = new TextEncoder();

function postToHost(payload) {
  try {
    window.webkit?.messageHandlers?.helmTerminal?.postMessage(payload);
  } catch {
    /* host not ready */
  }
}

function setStatus(text, kind = "info") {
  postToHost({ type: "status", text, kind });
}

function toWsUrl(httpBase, cols, rows) {
  const u = new URL(httpBase);
  u.protocol = u.protocol === "https:" ? "wss:" : "ws:";
  // Strip trailing slash; path may include reverse-proxy prefix.
  const basePath = u.pathname.replace(/\/+$/, "");
  u.pathname = basePath && basePath !== "/" ? `${basePath}/v1/terminal` : "/v1/terminal";
  u.search = "";
  u.searchParams.set("cols", String(cols));
  u.searchParams.set("rows", String(rows));
  if (apiToken) u.searchParams.set("token", apiToken);
  return u.toString();
}

/**
 * Fit the terminal into #terminal without letting the last row paint past the
 * clip edge. FitAddon can over-count by a fractional cell under WKWebView
 * (subpixel / font metrics / delayed layout), which intermittently clips the
 * bottom line.
 */
function fitAndNotify() {
  const host = document.getElementById("terminal");
  try {
    fitAddon.fit();

    // If the rendered screen still spills past the host box, drop one row.
    // (Common with line-box rounding inside WKWebView.)
    if (host && term.rows > 1) {
      const screen = host.querySelector(".xterm-screen");
      if (screen) {
        const hostBottom = host.getBoundingClientRect().bottom;
        const screenBottom = screen.getBoundingClientRect().bottom;
        if (screenBottom - hostBottom > 0.5) {
          term.resize(term.cols, term.rows - 1);
        }
      }
    }
  } catch {
    /* layout not ready */
  }

  const cols = term.cols;
  const rows = term.rows;
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ type: "resize", cols, rows }));
  }
  postToHost({ type: "resize", cols, rows });
  return { cols, rows };
}

function scheduleFit() {
  clearTimeout(resizeTimer);
  // Double rAF: wait for WKWebView/SwiftUI to commit the new bounds, then fit.
  resizeTimer = setTimeout(() => {
    requestAnimationFrame(() => {
      requestAnimationFrame(() => fitAndNotify());
    });
  }, 50);
}

const CONTROL_TYPES = new Set([
  "ready",
  "error",
  "exit",
  "pong",
  "ping",
  "resize",
  "stdin",
]);

/**
 * @returns {object|null} parsed control message, or null if not control JSON
 */
function parseControlMessage(text) {
  const t = typeof text === "string" ? text.trim() : "";
  if (!t.startsWith("{") || !t.includes('"type"')) return null;
  try {
    const msg = JSON.parse(t);
    if (msg && typeof msg.type === "string" && CONTROL_TYPES.has(msg.type)) {
      return msg;
    }
  } catch {
    /* not JSON */
  }
  return null;
}

function handleControlMessage(msg) {
  switch (msg.type) {
    case "ready":
      setStatus(`ready · ${msg.shell || "shell"}`, "ok");
      break;
    case "error":
      term.writeln(`\r\n\x1b[31m[error] ${msg.message}\x1b[0m\r\n`);
      setStatus(msg.message || "error", "err");
      break;
    case "exit":
      term.writeln("\r\n\x1b[90m[process exited]\x1b[0m\r\n");
      setStatus("exited", "err");
      break;
    case "pong":
    case "ping":
    case "resize":
    case "stdin":
      // Never render control plane on the PTY surface.
      break;
    default:
      break;
  }
}

/** Decode WS payload; if it is a control JSON object, handle and return true. */
function consumeControlPayload(data) {
  let text = null;
  if (typeof data === "string") {
    text = data;
  } else if (data instanceof ArrayBuffer) {
    // Peek only small frames as potential JSON control (ready/pong are tiny).
    if (data.byteLength > 0 && data.byteLength < 4096) {
      text = new TextDecoder().decode(data);
    }
  } else if (ArrayBuffer.isView(data)) {
    if (data.byteLength > 0 && data.byteLength < 4096) {
      text = new TextDecoder().decode(data);
    }
  }
  if (text == null) return false;
  const msg = parseControlMessage(text);
  if (!msg) return false;
  handleControlMessage(msg);
  return true;
}

function stopPing() {
  if (pingTimer) {
    clearInterval(pingTimer);
    pingTimer = null;
  }
}

function startPing() {
  stopPing();
  pingTimer = setInterval(() => {
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ type: "ping", t: Date.now() }));
    }
  }, 20_000);
}

function disconnect(opts = { reconnect: false }) {
  autoReconnect = opts.reconnect === true;
  stopPing();
  if (socket) {
    const s = socket;
    socket = null;
    try {
      s.close();
    } catch {
      /* ignore */
    }
  }
}

function connect() {
  if (disposed) return;
  if (!baseURL) {
    setStatus("no runner URL", "err");
    term.writeln("\r\n\x1b[33m[configure a project runner URL to open the terminal]\x1b[0m\r\n");
    return;
  }

  disconnect({ reconnect: true });
  autoReconnect = true;

  const { cols, rows } = fitAndNotify();
  let url;
  try {
    url = toWsUrl(baseURL, cols, rows);
  } catch (e) {
    setStatus("invalid URL", "err");
    term.writeln(`\r\n\x1b[31m[invalid base URL] ${baseURL}\x1b[0m\r\n`);
    return;
  }

  setStatus("connecting…", "info");
  const ws = new WebSocket(url);
  ws.binaryType = "arraybuffer";
  socket = ws;

  ws.addEventListener("open", () => {
    setStatus("connected", "ok");
    fitAndNotify();
    startPing();
    term.focus();
  });

  ws.addEventListener("message", (ev) => {
    // Control JSON must never hit term.write (text or binary-labeled).
    if (consumeControlPayload(ev.data)) return;

    if (typeof ev.data === "string") {
      term.write(ev.data);
      return;
    }

    const bytes =
      ev.data instanceof ArrayBuffer
        ? new Uint8Array(ev.data)
        : new Uint8Array(ev.data);
    term.write(bytes);
  });

  ws.addEventListener("close", (ev) => {
    stopPing();
    socket = null;
    setStatus(`disconnected (${ev.code})`, "err");
    if (!disposed && autoReconnect) {
      term.writeln(
        "\r\n\x1b[90m[session closed — reconnecting in 2s]\x1b[0m\r\n"
      );
      setTimeout(() => {
        if (!disposed && autoReconnect) connect();
      }, 2000);
    }
  });

  ws.addEventListener("error", () => {
    setStatus("error", "err");
  });
}

// Keystrokes → binary PTY stdin
term.onData((data) => {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  socket.send(encoder.encode(data));
});

// iPad orientation / Stage Manager / split.
window.addEventListener("resize", scheduleFit);
window.addEventListener("orientationchange", () => {
  setTimeout(fitAndNotify, 250);
});
// Software keyboard: visualViewport shrinks the layout box → FitAddon recompute cols/rows.
if (window.visualViewport) {
  window.visualViewport.addEventListener("resize", scheduleFit);
  window.visualViewport.addEventListener("scroll", scheduleFit);
}

// ResizeObserver: parent SwiftUI panel height changes (drag handle).
if (typeof ResizeObserver !== "undefined") {
  const ro = new ResizeObserver(() => scheduleFit());
  ro.observe(document.getElementById("terminal"));
}

// Bridge for Swift host
window.HelmTerminal = {
  configure({ baseURL: base, token } = {}) {
    if (typeof base === "string") baseURL = base.trim();
    if (typeof token === "string") apiToken = token.trim();
  },
  /**
   * Match app / editor column appearance (`Color(.systemBackground)`).
   * @param {"light"|"dark"} scheme
   */
  setColorScheme(scheme) {
    const next = scheme === "light" ? "light" : "dark";
    if (next === colorScheme) {
      // Still re-apply so late page load picks up host override.
      applyDocumentScheme(next);
      term.options.theme = xtermThemeFor(next);
      return;
    }
    colorScheme = next;
    applyDocumentScheme(next);
    term.options.theme = xtermThemeFor(next);
    // Refresh viewport so background cells repaint immediately.
    try {
      term.refresh(0, term.rows - 1);
    } catch {
      /* ignore */
    }
  },
  connect(opts) {
    if (opts) window.HelmTerminal.configure(opts);
    disposed = false;
    connect();
  },
  disconnect() {
    disposed = false;
    autoReconnect = false;
    disconnect({ reconnect: false });
    setStatus("disconnected", "info");
  },
  reconnect() {
    disposed = false;
    autoReconnect = true;
    if (socket) {
      try {
        socket.close();
      } catch {
        /* fall through */
      }
    } else {
      connect();
    }
  },
  fit: fitAndNotify,
  focus() {
    term.focus();
  },
  clear() {
    term.clear();
  },
  dispose() {
    disposed = true;
    autoReconnect = false;
    disconnect({ reconnect: false });
    try {
      term.dispose();
    } catch {
      /* ignore */
    }
  },
  ready: true,
};

postToHost({ type: "ready" });
requestAnimationFrame(() => {
  fitAndNotify();
  postToHost({ type: "ready" });
});
