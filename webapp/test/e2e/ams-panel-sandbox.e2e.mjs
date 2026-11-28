// Prova e2e: pannello Cinghy nella sandbox con l'agente AMS simulato, usato solo da tastiera.
// Avvia da sé il server di sviluppo e Chrome (headless). Uso: npm run test:e2e
// Con E2E_SHOTS=<cartella> salva gli screenshot del pannello (piano, esito, login).
import { spawn } from 'node:child_process';
import { chromium } from 'playwright-core';

const PORT = 8091;
const BASE = `http://localhost:${PORT}`;
const SHOTS = process.env.E2E_SHOTS;

const server = spawn('npx', ['ui5', 'serve', '--port', String(PORT)], { stdio: 'ignore', detached: true });
const stopServer = () => { try { process.kill(-server.pid); } catch { /* gia' chiuso */ } };
process.on('exit', stopServer);
for (let i = 0; ; i++) {
  try {
    if ((await fetch(`${BASE}/test/flpSandbox.html`)).ok) break;
  } catch { /* non ancora pronto */ }
  if (i > 60) throw new Error('Il server di sviluppo non risponde');
  await new Promise((r) => setTimeout(r, 1000));
}

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
const errors = [];
// il preload di ushell manca nella sandbox locale: errore noto, non del pannello
page.on('pageerror', (e) => { if (!e.message.includes('preload-bundles')) errors.push(e.message); });
const ok = (cond, msg) => { console.log((cond ? 'OK   ' : 'FAIL ') + msg); if (!cond) process.exitCode = 1; };

await page.goto(`${BASE}/test/flpSandbox.html#Shell-home`);
await page.locator('#regestaCinghyButton').click({ timeout: 60000 });
const panel = page.locator('#regestaCinghyPanel');
await panel.waitFor();
const input = panel.locator('.cinghyInput input');

async function say(text) {
  await input.waitFor();
  await page.waitForFunction(() => !document.querySelector('#regestaCinghyPanel .cinghyInput').disabled, null, { timeout: 15000 });
  await input.click();
  await input.fill(text);
  await page.keyboard.press('Enter');
}
const focusedText = () => page.evaluate(() => document.activeElement?.innerText?.trim() || document.activeElement?.tagName);
async function tabTo(label, max = 40) {
  for (let i = 0; i < max; i++) {
    await page.keyboard.press('Tab');
    if ((await focusedText()) === label) return true;
  }
  return false;
}

// 1. Portale non indicato: risposta di RST, nessuna operazione
await say('leggi il ticket 1');
await panel.getByText('Indica uno dei portali disponibili').waitFor();
ok(true, '422: messaggio di RST mostrato come risposta');

// 2. Lettura: avanzamento e riassunto
await say('Pittini: leggi il ticket 12345');
await panel.getByText('Apro il ticket 12345').waitFor({ timeout: 15000 });
ok(await panel.getByRole('button', { name: 'Interrompi' }).isVisible(), 'avanzamento con Interrompi');
ok(await page.evaluate(() => document.querySelector('#regestaCinghyPanel .cinghyInput').disabled), 'input disabilitato durante l\'operazione');
await panel.getByText('richiesta di verifica sulla ricerca VIM').waitFor({ timeout: 15000 });
ok(true, 'riassunto finale');

// 3. Modifica: piano, modifica testuale, conferma da tastiera, esito con screenshot
await say('Pittini: commenta il ticket 12345');
await panel.getByText('Piano proposto').waitFor({ timeout: 15000 });
ok(await panel.getByText('<Cordiali> saluti').isVisible(), 'testo della risposta mostrato come testo');
if (SHOTS) await panel.screenshot({ path: `${SHOTS}/piano.png` });
await say('usa un tono più formale');
await panel.getByText('Modificato su richiesta: usa un tono più formale').waitFor({ timeout: 15000 });
ok(true, 'modifica del piano scritta nell\'input');
ok(await tabTo('Conferma'), 'Conferma raggiungibile con Tab');
await page.keyboard.press('Enter');
await panel.getByText('Piano eseguito').waitFor({ timeout: 15000 });
const shot = panel.locator('img.cinghyScreenshot');
await shot.waitFor();
ok(await shot.evaluate((img) => img.complete && img.naturalWidth > 0), 'screenshot caricato');
ok((await shot.getAttribute('alt')) === 'Screenshot del portale a fine operazione', 'screenshot con testo alternativo');
if (SHOTS) await panel.screenshot({ path: `${SHOTS}/esito.png` });

// 4. Annulla
await say('Pittini: chiudi il ticket 12345');
await panel.getByText('Piano proposto').waitFor({ timeout: 15000 });
ok(await tabTo('Annulla'), 'Annulla raggiungibile con Tab');
await page.keyboard.press('Enter');
await panel.getByText('nessuna modifica eseguita').waitFor({ timeout: 15000 });
ok(true, 'piano annullato');

// 5. Login
await say('Pittini: leggi il ticket 12345 #login');
await panel.getByRole('button', { name: "Ho fatto l'accesso" }).waitFor({ timeout: 15000 });
if (SHOTS) await panel.screenshot({ path: `${SHOTS}/login.png` });
ok(await tabTo("Ho fatto l'accesso"), "Ho fatto l'accesso raggiungibile con Tab");
await page.keyboard.press('Enter');
await panel.getByText('richiesta di verifica sulla ricerca VIM').nth(1).waitFor({ timeout: 15000 });
ok(true, 'ripresa dopo il login');

// 6. Interruzione
await say('Pittini: leggi il ticket 12345');
await panel.getByRole('button', { name: 'Interrompi' }).waitFor({ timeout: 15000 });
await panel.getByRole('button', { name: 'Interrompi' }).click();
await panel.getByText('Operazione interrotta dal consulente').waitFor({ timeout: 15000 });
ok(true, 'interruzione');

// 7. Codice di associazione
await panel.getByRole('button', { name: 'Associa il runner AMS di questo PC' }).click();
await panel.getByText('ABCD2345').waitFor();
ok(await panel.getByText('cinghy_ams_rn').isVisible(), 'codice con il comando del runner');
const stored = await page.evaluate(() => sessionStorage.getItem('regesta.cinghy.conversation'));
ok(!stored.includes('ABCD2345'), 'codice non salvato in sessionStorage');

// 8. Live region per i lettori di schermo
const live = await page.evaluate(() => [...document.querySelectorAll('[aria-live]')].map((e) => e.textContent).join(' | '));
ok(live.length > 0, 'annunci aria-live presenti');

ok(errors.length === 0, 'nessun errore JavaScript' + (errors.length ? ': ' + errors.join('; ') : ''));
await browser.close();
stopServer();
