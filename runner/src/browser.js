// Playwright MCP come processo figlio (stdio), con browser visibile e profilo dedicato persistente.
import { createRequire } from 'node:module';
import { rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const require = createRequire(import.meta.url);

export function createBrowser({ profileDir, outputDir, browser = 'chrome', headless = false }) {
  let client;

  async function connect() {
    // cli.js non e' tra gli "exports" del pacchetto: si risolve dalla cartella di package.json.
    const cli = join(dirname(require.resolve('@playwright/mcp/package.json')), 'cli.js');
    const args = [cli, '--browser', browser,
      '--user-data-dir', profileDir, '--output-dir', outputDir];
    if (headless) args.push('--headless');
    const c = new Client({ name: 'cinghy-ams-runner', version: '0.1.0' });
    await c.connect(new StdioClientTransport({ command: process.execPath, args, stderr: 'inherit' }));
    c.onclose = () => { if (client === c) client = undefined; };
    return c;
  }

  return {
    async callTool(name, args) {
      client ??= await connect();
      return client.callTool({ name, arguments: args });
    },
    // Playwright MCP salva pagine e screenshot su file: contengono dati del cliente, non li teniamo.
    clearOutput() { rmSync(outputDir, { recursive: true, force: true }); },
    async close() { await client?.close(); client = undefined; },
  };
}
