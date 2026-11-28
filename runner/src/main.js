// Runner dell'agente AMS: si associa a RST con un codice, attende le azioni (long polling),
// le esegue nel browser tramite Playwright MCP e restituisce esito, pagina e screenshot.
import { mkdirSync, readFileSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { homedir, hostname } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { pathToFileURL } from 'node:url';
import tls from 'node:tls';
import { createRst, RstError } from './rst.js';
import { createBrowser } from './browser.js';
import { execute, hostOf, pageUrl, textOf } from './actions.js';

const log = (s) => console.log(`[${new Date().toLocaleTimeString()}] ${s}`);
// fetch dice solo "fetch failed": la causa (certificato, DNS, rete) e' in e.cause.
const why = (e) => (e.cause?.message ? `${e.message}: ${e.cause.message}` : e.message);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Un giro: una richiesta di azioni, esecuzione in ordine, invio degli esiti.
export async function runOnce({ rst, token, browser, state }) {
  const actions = await rst.poll(token);
  for (const action of actions) {
    log(`Azione ${action.tool}`);
    let result;
    try {
      result = await execute(action, browser, state);
    } catch (e) {
      result = { result: `Il runner non ha potuto eseguire l'azione: ${e.message}`, isError: true, summary: 'Errore del runner' };
    }
    browser.clearOutput?.();
    await sendWithRetry(rst, token, action.stepId, result);
  }
  return actions.length;
}

// Apre il portale indicato a riga di comando. Se si arriva al login Microsoft, l'utente passato
// si aggiunge come login_hint: Entra ID lo mostra gia' compilato. Il runner non scrive nella pagina.
export async function openStart(browser, url, loginHint) {
  await browser.callTool('browser_navigate', { url });
  if (!loginHint) return;
  const current = pageUrl(textOf(await browser.callTool('browser_snapshot', {})));
  if (hostOf(current) !== 'login.microsoftonline.com' || /[?&]login_hint=/.test(current)) return;
  const withHint = new URL(current);
  withHint.searchParams.set('login_hint', loginHint);
  await browser.callTool('browser_navigate', { url: withHint.href });
}

// Un esito perso lascerebbe l'operazione ferma fino al timeout: si ritenta finche' la rete torna.
async function sendWithRetry(rst, token, stepId, result, retryMs = 5000) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await rst.sendResult(token, stepId, result);
    } catch (e) {
      if (e instanceof RstError && e.status < 500) throw e;
      if (attempt >= 12) throw e;
      log(`Invio dell'esito non riuscito (${why(e)}): riprovo`);
      await sleep(retryMs);
    }
  }
}

async function main() {
  const baseUrl = process.env.RST_URL;
  if (!baseUrl) {
    console.error('Manca RST_URL, per esempio: RST_URL="https://<host>:<porta>/sap/bc/reg/cinghy_ams_rn?sap-client=100" npm start');
    process.exit(2);
  }
  const home = process.env.AMS_RUNNER_HOME || join(homedir(), '.cinghy-ams-runner');
  const tokenFile = join(home, 'token');
  mkdirSync(home, { recursive: true, mode: 0o700 });

  // RST con certificato autofirmato: ci si fida solo di quel certificato, salvato dal consulente.
  const certFile = join(home, 'rst-cert.pem');
  if (existsSync(certFile)) {
    if (typeof tls.setDefaultCACertificates !== 'function') {
      console.error(`Questa versione di Node non carica ${certFile}: aggiornare Node o avviare con NODE_EXTRA_CA_CERTS=${certFile}`);
      process.exit(2);
    }
    tls.setDefaultCACertificates([...tls.getCACertificates('default'), readFileSync(certFile, 'utf8')]);
  }

  const rst = createRst(baseUrl);
  if (!existsSync(tokenFile)) {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const code = (await rl.question('Codice di associazione generato in Cinghy: ')).trim().toUpperCase();
    rl.close();
    const token = await rst.pair(code, hostname());
    writeFileSync(tokenFile, token, { mode: 0o600 });
    log('Runner associato');
  }
  const token = readFileSync(tokenFile, 'utf8').trim();

  const browser = createBrowser({ profileDir: join(home, 'profile'), outputDir: join(home, 'output') });
  browser.clearOutput();
  const stop = async () => { await browser.close(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);

  // Il browser si apre subito: il consulente puo' fare l'accesso ai portali prima della prima operazione.
  // npm start -- <url> [utente]: apre subito il portale per fare l'accesso.
  const [startUrl, loginHint] = process.argv.slice(2);
  if (startUrl) await openStart(browser, startUrl, loginHint);
  else await browser.callTool('browser_snapshot', {});
  log('Browser aperto. In attesa di azioni da RST (Ctrl+C per uscire)');

  const state = { lastSnapshot: '' };
  let backoff = 5000;
  for (;;) {
    try {
      await runOnce({ rst, token, browser, state });
      backoff = 5000;
    } catch (e) {
      if (e instanceof RstError && e.status === 401) {
        rmSync(tokenFile, { force: true });
        log(`${e.message}. Token cancellato: genera un nuovo codice in Cinghy e riavvia il runner`);
        await browser.close();
        process.exit(1);
      }
      log(`RST non raggiungibile (${why(e)}): riprovo tra ${backoff / 1000} s`);
      await sleep(backoff);
      backoff = Math.min(backoff * 2, 60000);
    }
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(why(e)); process.exit(1); });
}
