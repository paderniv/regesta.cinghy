// Esecuzione di un'azione ricevuta da RST. RST ha gia' filtrato l'azione; qui si ripetono i
// controlli che dipendono dal browser reale: dominio, pagina di login, riferimento nella pagina.

// Argomenti inoltrati per strumento; il resto (plan_step, ...) si scarta perche' Playwright MCP
// rifiuta argomenti sconosciuti. "ref" di RST diventa "target" di Playwright MCP.
const TOOLS = {
  browser_navigate: ['url'],
  browser_navigate_back: [],
  browser_snapshot: [],
  browser_take_screenshot: [],
  browser_wait_for: ['text', 'time'],
  browser_click: ['element', 'ref'],
  browser_type: ['element', 'ref', 'text', 'submit'],
  browser_select_option: ['element', 'ref', 'values'],
  browser_press_key: ['key'],
};
const MAX_WAIT_SECONDS = 30;

export function hostOf(url) {
  const m = /^https?:\/\/([^/:?#]+)/i.exec(url ?? '');
  return m ? m[1].toLowerCase() : '';
}

export const pageUrl = (snapshot) => /^- Page URL: (\S+)/m.exec(snapshot)?.[1] ?? '';
export const textOf =(res) => (res?.content ?? []).filter((p) => p.type === 'text').map((p) => p.text).join('\n');
const imageOf = (res) => (res?.content ?? []).find((p) => p.type === 'image')?.data;

// state.lastSnapshot: ultima pagina restituita a RST, per controllare i riferimenti.
export async function execute(action, browser, state) {
  const { tool, args = {}, allowedDomains = [], loginDomains = [] } = action;
  const fail = (message) => ({ result: message, isError: true, summary: message });

  if (!(tool in TOOLS)) return fail(`Strumento ${tool} non supportato dal runner`);
  if (tool === 'browser_navigate' && !allowedDomains.includes(hostOf(args.url))) {
    return fail(`Indirizzo ${args.url} fuori dai domini del portale: non aperto`);
  }
  if ('ref' in args && !(state.lastSnapshot ?? '').includes(`[ref=${args.ref}]`)) {
    return fail(`Elemento ${args.ref} non presente nell'ultima pagina letta: rileggi la pagina con browser_snapshot`);
  }

  const mcpArgs = {};
  for (const key of TOOLS[tool]) {
    if (args[key] !== undefined) mcpArgs[key === 'ref' ? 'target' : key] = args[key];
  }
  if (mcpArgs.time > MAX_WAIT_SECONDS) mcpArgs.time = MAX_WAIT_SECONDS;

  const res = await browser.callTool(tool, mcpArgs);
  // Ogni esito porta la pagina corrente intera: il filtro su RST legge ruolo e nome degli elementi da qui.
  const snapRes = tool === 'browser_snapshot' ? res : await browser.callTool('browser_snapshot', {});
  const snapshot = textOf(snapRes);
  const host = hostOf(pageUrl(snapshot));

  if (host && loginDomains.includes(host)) {
    state.lastSnapshot = '';
    // La pagina di login non esce dal PC: niente descrizione, niente screenshot.
    return { result: '', isError: true, loginRequired: true, summary: 'Login richiesto' };
  }
  if (host && !allowedDomains.includes(host)) {
    await browser.callTool('browser_navigate_back', {});
    state.lastSnapshot = '';
    return fail(`L'azione ha portato fuori dai domini del portale (${host}): pagina non letta, tornato indietro`);
  }

  state.lastSnapshot = snapshot;
  const title = /^- Page Title: (.*)$/m.exec(snapshot)?.[1] ?? '';
  const out = res.isError
    ? { result: `${textOf(res)}\n\n${snapshot}`, isError: true, summary: `Errore: ${textOf(res).split('\n').find((l) => l && !l.startsWith('#')) ?? ''}`.slice(0, 250) }
    : { result: snapshot, isError: false, summary: `Pagina: ${title}`.slice(0, 250) };
  const image = imageOf(res);
  if (tool === 'browser_take_screenshot' && image) out.screenshot = image;
  return out;
}
