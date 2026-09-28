//
// no-webgpu-smoke.mjs — CI smoke test for the built web game.
//
// Proves, in a real Chrome, that the exact artifact about to be deployed:
//   1. boots and renders with WebGPU removed from the browser entirely
//      (navigator.gpu is a trap that throws if anything touches it, so the
//      page's adapter probe fails and it must fall back to Canvas 2D),
//   2. does so WITHOUT cross-origin isolation — a plain static host sends no
//      COOP/COEP headers, so a build that needed SharedArrayBuffer would die
//      there,
//   3. renders actual pixels (a "ready" flag alone proves nothing).
//
// CI runs this in build-web.yml after the build and before web/dist is
// committed, so a build that breaks the fallback never gets published.
//
// Run:  CHROME_PATH=/usr/bin/google-chrome-stable node web/tests/no-webgpu-smoke.mjs
//       (needs `npm install --no-save puppeteer-core` in web/ first)
// Env:  DIST_DIR   — built site directory (default: ../dist)
//       CHROME_PATH— chrome binary (default: /usr/bin/google-chrome-stable)
//       SMOKE_OUT  — directory for screenshots (default: current dir)
//
// Exits 0 only if the game reaches its first frame with real pixels.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { mkdir } from 'node:fs/promises';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DIST = process.env.DIST_DIR ? resolve(process.env.DIST_DIR) : resolve(__dirname, '../dist');
const CHROME = process.env.CHROME_PATH ?? '/usr/bin/google-chrome-stable';
const OUT = process.env.SMOKE_OUT ?? process.cwd();
const PORT = 8901;
const READY_TIMEOUT_MS = 180_000; // 69 MB download + compile on CI
const PIXEL_TIMEOUT_MS = 30_000;

const MIME_OK = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.map': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
  '.png': 'image/png',
};

function staticServer(root, port) {
  return new Promise((resolveSrv) => {
    const srv = createServer(async (req, res) => {
      const pathname = new URL(req.url, 'http://localhost').pathname;
      const file = join(root, pathname === '/' ? 'index.html' : pathname);
      let data;
      try {
        data = await readFile(file);
      } catch {
        res.writeHead(404).end('not found');
        return;
      }
      const ext = extname(file);
      const mime = MIME_OK[ext] ?? 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': mime }).end(data);
    });
    srv.listen(port, '127.0.0.1', () => resolveSrv(srv));
  });
}

// Installs (in the page, before any page script runs):
//  - a navigator.gpu trap: any access throws, so a page that "works" here
//    demonstrably fell back to Canvas 2D instead of depending on WebGPU (the
//    page probes for an adapter first, and must survive the probe throwing);
//  - a hook that flags when the game calls its own foretoldReady.
const PAGE_PROLOGUE = () => {
  try {
    Object.defineProperty(navigator, 'gpu', {
      configurable: true,
      get() { throw new Error('WEBGPU_API_TOUCHED: simulated broken WebGPU — the page must fall back to Canvas 2D'); },
    });
  } catch {}
  window.__smokeReady = false;
  const t = setInterval(() => {
    const f = window.foretoldReady;
    if (typeof f === 'function') {
      clearInterval(t);
      window.foretoldReady = (...a) => { window.__smokeReady = true; return f(...a); };
    }
  }, 5);
};

// True once the canvas has real content: a 200×200 sample around the board
// center must contain a healthy amount of non-background pixels.
const PIXELS_PRESENT = () => {
  const c = document.getElementById('canvas');
  if (!c) return false;
  const ctx = c.getContext('2d');
  const d = ctx.getImageData(c.width / 2 - 100, c.height / 2 - 100, 200, 200).data;
  let lit = 0;
  for (let i = 0; i < d.length; i += 4) {
    // Page background is #16161c; blank canvas is transparent black. Count
    // anything clearly not either as drawn content.
    if (d[i + 3] > 0 && (d[i] > 40 || d[i + 1] > 40 || d[i + 2] > 40)) lit++;
  }
  return lit > 50;
};

async function runScenario(label, port) {
  console.log(`\n=== scenario ${label} (port ${port}) ===`);
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: true,
    args: [
      '--no-sandbox',
      // No GPU at all — Canvas 2D must fully rasterize on the CPU.
      '--disable-gpu',
      '--window-size=1920,1080',
    ],
  });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(String(e.message ?? e)));
  page.on('console', (m) => {
    if (m.type() === 'error') pageErrors.push('console.error: ' + m.text());
  });

  await page.evaluateOnNewDocument(PAGE_PROLOGUE);
  const navStart = Date.now();
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'load', timeout: 120_000 });

  const pageState = () => page.evaluate(() => {
    const s = document.getElementById('status');
    const log = document.getElementById('log');
    return {
      ready: window.__smokeReady === true,
      statusText: s ? s.textContent : '(no status element)',
      statusErr: s ? s.className === 'err' : false,
      logTail: log && log.style.display !== 'none' ? log.textContent.split('\n').slice(-15).join('\n') : null,
    };
  });

  try {
    try {
      await page.waitForFunction('window.__smokeReady === true',
        { timeout: READY_TIMEOUT_MS, polling: 250 });
      console.log(`  first frame reported in ${((Date.now() - navStart) / 1000).toFixed(1)}s`);

      const statusEl = await page.evaluate(() => {
        const s = document.getElementById('status');
        return s ? { text: s.textContent, err: s.className === 'err' } : null;
      });
      if (statusEl?.err) throw new Error('page reported failure: ' + statusEl.text);

      await page.waitForFunction(PIXELS_PRESENT, { timeout: PIXEL_TIMEOUT_MS, polling: 500 });
      console.log('  canvas has rendered content ✓');

      const facts = await page.evaluate(() => ({
        crossOriginIsolated,
        sab: typeof SharedArrayBuffer !== 'undefined',
        ready: window.__smokeReady,
      }));
      console.log(`  crossOriginIsolated=${facts.crossOriginIsolated} (must be false — the test server sends no COOP/COEP)`);
      if (facts.crossOriginIsolated) {
        console.warn('  !! test host unexpectedly cross-origin isolated — not representative of a plain static host');
      }

      const shot = join(OUT, `smoke-${label}.png`);
      await page.screenshot({ path: shot });
      console.log(`  screenshot → ${shot}`);
      console.log(`  PASS ${label}`);
    } catch (e) {
      // Surface whatever the page itself is saying — a ready-timeout with the
      // page's own status/log text is far more actionable than a bare timeout.
      let diag = '';
      try {
        const st = await pageState();
        diag = '\n  page state at failure:\n'
          + `    ready=${st.ready} statusErr=${st.statusErr}\n`
          + `    status: ${st.statusText.split('\n')[0]}\n`
          + (st.logTail ? '    log tail:\n' + st.logTail.split('\n').map((l) => '      ' + l).join('\n') : '');
        try {
          await page.screenshot({ path: join(OUT, `smoke-${label}-FAILED.png`) });
        } catch {}
      } catch {}
      throw new Error(`${label}: ${e.message}${diag}`);
    }
  } finally {
    await browser.close();
  }
  if (pageErrors.length) {
    console.warn('  page errors observed (non-fatal, review the log):');
    for (const e of pageErrors.slice(0, 10)) console.warn('    ' + e);
  }
}

let code = 1;
try {
  await mkdir(OUT, { recursive: true });
  if (!process.env.DIST_DIR) console.log(`dist: ${DIST}`);
  const srv = await staticServer(DIST, PORT);
  try {
    await runScenario('no-webgpu', PORT);
    code = 0;
    console.log('\nSMOKE TEST PASSED — the build boots and draws with WebGPU unavailable');
  } finally {
    srv.close();
  }
} catch (e) {
  console.error(`\nSMOKE TEST FAILED: ${e.message}`);
  code = 1;
}
process.exit(code);
