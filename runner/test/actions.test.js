import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execute, hostOf } from '../src/actions.js';

const page = (url, body = '- button "Cerca" [ref=e4]') =>
  ({ content: [{ type: 'text', text: `### Page\n- Page URL: ${url}\n- Page Title: Ticket\n### Snapshot\n\`\`\`yaml\n${body}\n\`\`\`` }] });

// Browser finto: registra le chiamate, la pagina corrente e' quella impostata dal test.
function fakeBrowser(url = 'https://hdserver.pittini.it/ticket') {
  const calls = [];
  return {
    calls,
    url,
    async callTool(name, args) {
      calls.push({ name, args });
      if (name === 'browser_navigate') this.url = args.url;
      if (name === 'browser_take_screenshot') return { content: [{ type: 'text', text: 'ok' }, { type: 'image', mimeType: 'image/png', data: 'iVBORw0' }] };
      return page(this.url);
    },
  };
}
const action = (tool, args = {}) => ({
  stepId: 'A1', tool, args,
  allowedDomains: ['hdserver.pittini.it', 'login.microsoftonline.com'],
  loginDomains: ['login.microsoftonline.com'],
});

test('hostOf legge solo http e https', () => {
  assert.equal(hostOf('https://HDSERVER.pittini.it:443/x'), 'hdserver.pittini.it');
  assert.equal(hostOf('javascript:alert(1)'), '');
  assert.equal(hostOf('https://evil.example/hdserver.pittini.it'), 'evil.example');
});

test('navigazione fuori dai domini rifiutata senza toccare il browser', async () => {
  const b = fakeBrowser();
  const out = await execute(action('browser_navigate', { url: 'https://evil.example/' }), b, {});
  assert.equal(out.isError, true);
  assert.match(out.result, /fuori dai domini/);
  assert.equal(b.calls.length, 0);
});

test('pagina di login: nessuna descrizione e operazione in attesa di login', async () => {
  const b = fakeBrowser('https://login.microsoftonline.com/common/oauth2');
  const state = { lastSnapshot: 'x' };
  // Il portale rimanda al login Microsoft: la pagina corrente e' sul dominio di login.
  const out = await execute(action('browser_snapshot'), b, state);
  assert.equal(out.loginRequired, true);
  assert.equal(out.result, '');
  assert.equal(out.screenshot, undefined);
  assert.equal(state.lastSnapshot, '');
});

test('click: ref diventa target e plan_step non arriva a Playwright MCP', async () => {
  const b = fakeBrowser();
  const state = { lastSnapshot: '- button "Cerca" [ref=e4]' };
  const out = await execute(action('browser_click', { element: 'Cerca', ref: 'e4', plan_step: 2 }), b, state);
  assert.equal(out.isError, false);
  assert.deepEqual(b.calls[0], { name: 'browser_click', args: { element: 'Cerca', target: 'e4' } });
  assert.equal(b.calls[1].name, 'browser_snapshot');
  assert.match(out.result, /\[ref=e4\]/);
});

test('ref non presente nell\'ultima pagina rifiutato', async () => {
  const b = fakeBrowser();
  const out = await execute(action('browser_click', { element: 'x', ref: 'button' }), b, { lastSnapshot: '- button "Cerca" [ref=e4]' });
  assert.equal(out.isError, true);
  assert.equal(b.calls.length, 0);
});

test('pagina finita fuori dominio dopo un click: torna indietro e non la descrive', async () => {
  const b = fakeBrowser();
  b.callTool = async function (name, args) {
    b.calls.push({ name, args });
    return page(name === 'browser_snapshot' ? 'https://evil.example/' : this.url);
  };
  const out = await execute(action('browser_click', { element: 'link', ref: 'e4' }), b, { lastSnapshot: '[ref=e4]' });
  assert.equal(out.isError, true);
  assert.doesNotMatch(out.result, /Snapshot/);
  assert.equal(b.calls.at(-1).name, 'browser_navigate_back');
});

test('screenshot inviato in base64', async () => {
  const out = await execute(action('browser_take_screenshot'), fakeBrowser(), {});
  assert.equal(out.screenshot, 'iVBORw0');
});

test('strumento sconosciuto rifiutato', async () => {
  const b = fakeBrowser();
  const out = await execute(action('browser_evaluate', { function: '() => 1' }), b, {});
  assert.equal(out.isError, true);
  assert.equal(b.calls.length, 0);
});
