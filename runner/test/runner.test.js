// Un giro del runner contro un RST simulato in locale (stessi percorsi e header del servizio ABAP).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createRst, RstError } from '../src/rst.js';
import { runOnce, openStart } from '../src/main.js';

async function fakeRst(handler) {
  const requests = [];
  const server = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) body += chunk;
    const r = { method: req.method, url: req.url, token: req.headers['x-ams-token'], body: body && JSON.parse(body) };
    requests.push(r);
    const [status, json] = handler(r);
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(json));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/sap/bc/reg/cinghy_ams_rn?sap-client=100`;
  return { base, requests, close: () => server.close() };
}

test('associazione: il codice diventa un token', async (t) => {
  const srv = await fakeRst((r) => (r.body.code === 'ABCD2345' ? [200, { token: 'T'.repeat(64) }] : [401, { error: 'Codice sbagliato' }]));
  t.after(srv.close);
  const rst = createRst(srv.base);
  assert.equal(await rst.pair('ABCD2345', 'pc'), 'T'.repeat(64));
  assert.equal(srv.requests[0].url, '/sap/bc/reg/cinghy_ams_rn/pair?sap-client=100');
  await assert.rejects(rst.pair('XXXX', 'pc'), (e) => e instanceof RstError && e.status === 401);
});

test('un giro: azione ricevuta, eseguita, esito inviato con il token', async (t) => {
  const srv = await fakeRst((r) => {
    if (r.method === 'GET') {
      return [200, [{ stepId: 'ABC123', opId: 'OP1', tool: 'browser_navigate', args: { url: 'https://hdserver.pittini.it/x' },
        allowedDomains: ['hdserver.pittini.it'], loginDomains: [] }]];
    }
    return [200, { ok: true }];
  });
  t.after(srv.close);
  const browser = {
    callTool: async () => ({ content: [{ type: 'text', text: '### Page\n- Page URL: https://hdserver.pittini.it/x\n- Page Title: T\n### Snapshot\n- link "A" [ref=e1]' }] }),
    clearOutput: () => {},
  };
  const n = await runOnce({ rst: createRst(srv.base), token: 'tok', browser, state: {} });
  assert.equal(n, 1);
  const [poll, result] = srv.requests;
  assert.equal(poll.url, '/sap/bc/reg/cinghy_ams_rn/actions?sap-client=100');
  assert.equal(poll.token, 'tok');
  assert.equal(result.url, '/sap/bc/reg/cinghy_ams_rn/actions/ABC123/result?sap-client=100');
  assert.equal(result.token, 'tok');
  assert.equal(result.body.isError, false);
  assert.match(result.body.result, /\[ref=e1\]/);
});

test('token revocato: errore 401 al chiamante', async (t) => {
  const srv = await fakeRst(() => [401, { error: 'Token del runner sconosciuto o revocato' }]);
  t.after(srv.close);
  await assert.rejects(runOnce({ rst: createRst(srv.base), token: 'old', browser: {}, state: {} }),
    (e) => e instanceof RstError && e.status === 401);
});

test('avvio con utente: login Microsoft riaperto con login_hint, una sola volta', async () => {
  const calls = [];
  let url = '';
  const browser = {
    async callTool(tool, args) {
      calls.push([tool, args]);
      if (tool === 'browser_navigate') url = args.url.startsWith('https://hdserver') ? 'https://login.microsoftonline.com/t/oauth2/authorize?client_id=x' : args.url;
      return { content: [{ type: 'text', text: `### Page\n- Page URL: ${url}\n` }] };
    },
  };
  await openStart(browser, 'https://hdserver.pittini.it/', 'mario@pittini.it');
  assert.equal(calls.at(-1)[1].url, 'https://login.microsoftonline.com/t/oauth2/authorize?client_id=x&login_hint=mario%40pittini.it');
  calls.length = 0;
  await openStart(browser, 'https://hdserver.pittini.it/');
  assert.deepEqual(calls.map((c) => c[0]), ['browser_navigate']);
});
