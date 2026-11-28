// Client del servizio runner su RST (/sap/bc/reg/cinghy_ams_rn). Solo HTTPS in uscita.
// Il token viaggia in X-AMS-Token: Authorization lo usa l'ICF per il proprio logon.

export class RstError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function createRst(baseUrl, { fetchImpl = fetch, pollTimeoutMs = 45000 } = {}) {
  const url = (path) => {
    const u = new URL(baseUrl);
    u.pathname = u.pathname.replace(/\/$/, '') + path;
    return u;
  };

  async function call(method, path, { token, body, timeoutMs = 30000 } = {}) {
    const headers = { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' };
    if (token) headers['X-AMS-Token'] = token;
    const res = await fetchImpl(url(path), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await res.text();
    let data;
    try { data = text ? JSON.parse(text) : {}; } catch { data = { error: text.slice(0, 300) }; }
    if (!res.ok) throw new RstError(res.status, data.error || `HTTP ${res.status}`);
    return data;
  }

  return {
    pair: async (code, name) => (await call('POST', '/pair', { body: { code, name } })).token,
    // Long polling: RST tiene aperta la richiesta fino a 30 s.
    poll: (token) => call('GET', '/actions', { token, timeoutMs: pollTimeoutMs }),
    sendResult: (token, stepId, result) =>
      call('POST', `/actions/${encodeURIComponent(stepId)}/result`, { token, body: result, timeoutMs: 60000 }),
  };
}
