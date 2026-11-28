# Proposal

## Why

Il reparto AMS di Regesta lavora ogni giorno sui portali di ticketing dei clienti: portali diversi per ogni cliente, quasi sempre senza API, raggiungibili solo dall'interfaccia web. Leggere, classificare, aggiornare e rispondere ai ticket è lavoro ripetitivo fatto a mano, cliente per cliente. Cinghy può diventare un agente che il consulente AMS pilota in linguaggio naturale e che esegue queste operazioni sul portale del cliente, sotto il suo controllo. Il primo cliente pilota è Pittini (portale custom "AMS Pittini").

## What Changes

- Cinghy, nel Launchpad del sistema Regesta RST, accetta istruzioni del consulente AMS sui ticket di un portale cliente (per esempio "leggi il ticket 12345, classificalo e prepara una risposta").
- Nasce il backend ABAP di Cinghy su RST: il ciclo dell'agente chiama un modello linguistico e usa strumenti per guidare un browser. Il client del modello è indipendente dal fornitore (OpenAI, Google Gemini, in seguito Anthropic): quale modello usare è una scelta di configurazione, anche diversa per portale. Le risposte simulate restano per gli usi non ancora coperti.
- Le operazioni sul portale sono eseguite da un **runner** esterno ad ABAP (Playwright MCP con Chromium), che si collega in uscita a RST e ne riceve le azioni. Lo stesso runner può girare sul PC del consulente (browser visibile, pilota) o su un server Regesta (in seguito).
- L'agente lavora in due fasi: legge e naviga liberamente, poi propone un piano di modifiche che il consulente conferma in Cinghy prima che venga eseguito. Dopo l'esecuzione l'agente verifica il risultato e ne conserva uno screenshot.
- Ogni portale cliente ha un **profilo** su RST: URL, runner da usare, modello da usare, modalità di login, istruzioni di navigazione, corrispondenze dei valori (priorità, gruppi, stati). Un nuovo cliente richiede un profilo, non sviluppo.
- Ogni richiesta e ogni azione sono registrate su RST con il consulente che le ha chieste: con account condivisi sul portale cliente, è l'unica traccia di chi ha fatto cosa.
- Le credenziali dei portali non passano mai dal modello; il testo dei ticket è trattato come dato non attendibile.

Fuori scope: portali clienti con API (integrazione dedicata, valutata in seguito), runner centrale in produzione e vault delle credenziali, lavoro non presidiato o pianificato, portali con MFA, assistente generico per gli utenti S/4 dei clienti.

## Capabilities

### New Capabilities

- `ams-portal-agent`: l'agente che il consulente AMS pilota da Cinghy: istruzioni, fase di lettura, piano delle modifiche, conferma, esecuzione e verifica, regole di sicurezza e registro delle azioni.
- `portal-runner`: il runner che esegue le azioni del browser per conto dell'agente: collegamento in uscita a RST e sua autenticazione, esecuzione tramite Playwright MCP, gestione del login al portale, modalità locale e centrale.
- `portal-profiles`: i profili dei portali clienti su RST e il loro uso da parte dell'agente.

### Modified Capabilities

Nessuna. Il pannello chat (`cinghy-chat-panel`) è ancora nella change `add-cinghy-chat-panel` non archiviata: le parti del pannello necessarie all'agente (piano da confermare, avanzamento) sono descritte in `ams-portal-agent`.

## Impact

- Sistema RST (ABAP): nuovi oggetti nel namespace `/REG/` per il ciclo dell'agente, il client dei modelli con un adattatore per fornitore (destinazioni SM59, chiavi API), la coda delle azioni per i runner, i profili dei portali, il registro; un servizio HTTP per Cinghy e uno per i runner; esecuzione in background.
- Frontend Cinghy: `ChatService.js` passa dal mock al backend; il pannello mostra avanzamento, piano delle modifiche e conferma; deploy anche su RST.
- Nuovo componente fuori da SAP: il runner (Node.js, Playwright MCP, Chromium), da installare sui PC dei consulenti AMS.
- Rete: HTTPS in uscita dai runner verso RST; da RST verso le API dei fornitori dei modelli configurati.
- Cliente Pittini: accesso a `https://hdserver.pittini.it/` (Microsoft Entra ID tramite Azure App Proxy, account condiviso, senza MFA); da concordare con Pittini l'uso di un agente sul loro portale.
- Costi: consumo dell'API del fornitore del modello per ogni operazione dell'agente.
