# Cinghy – plugin Fiori Launchpad

Plugin dello shell per S/4HANA on-premise (UI5 1.136): aggiunge il pulsante di Cinghy nella barra in alto del Launchpad e apre un pannello chat sopra l'app corrente. Il pannello parla con l'agente AMS su RST (`/sap/bc/reg/cinghy_ams`): ogni istruzione avvia un'operazione su un portale cliente, che il pannello segue fino all'esito (avanzamento, piano da confermare, richiesta di login, esito con screenshot). Il pulsante con la catena genera il codice di associazione del runner (vedi `runner/README.md`).

- `webapp/Component.js`: plugin, pulsante (servizio Extension) e contesto dell'app corrente (servizio AppLifeCycle)
- `webapp/ChatPanel.js`: pannello chat fisso a destra
- `webapp/ChatService.js`: chiamate al servizio dell'agente AMS su RST e polling dello stato ogni 2 s
- `webapp/ConversationStore.js`: conversazione e id dell'operazione in corso in `sessionStorage` (dopo F5 il pannello riprende a seguirla)
- `webapp/markdown.js`: risposte markdown → HTML, filtrato da `sap.m.FormattedText`
- `webapp/css/cinghy.css`: stile del pannello, solo variabili del tema SAP
- `webapp/img/`: avatar di Cinghy nel pannello (`.png`, 128 px); `.webp` e `.svg` sono sorgenti esclusi dalla build. PNG perché sul sistema S/4 i `.webp` caricati nel repository UI5 non venivano visualizzati
- `webapp/CinghyIcon.js`: icona monocromatica del cinghiale per il pulsante, registrata nei Web Components. La shell bar a Web Components accetta solo icone registrate, non immagini; la barra classica usa `sap-icon://ai`. Si rigenera con `npm run icon` da `img/03_analisi_dati_occhiali_ar.svg` (`scripts/genicon.cjs`)

## Sviluppo locale

Serve Node.js 20 o superiore.

```sh
npm install
npm start
```

`npm start` avvia `ui5 serve` con SAPUI5 1.136 e apre un Launchpad sandbox (`webapp/test/flpSandbox.html`) con il plugin e un'app di esempio, "Ordini demo". Nella sandbox non c'è RST: il pannello usa l'agente AMS simulato di `webapp/test/SimulatedAms.js`. Un'istruzione senza "Pittini" riceve la risposta "portale non riconosciuto"; con "commenta", "chiudi" o "cambia" l'agente propone un piano; `#login` simula la richiesta di accesso, `#offline` il runner spento, `#errore` RST non raggiungibile. Con `?shellBar=true` nell'URL (`test/flpSandbox.html?shellBar=true#Shell-home`) la sandbox usa la shell bar a Web Components, come sul sistema S/4.

Test unitari: con il server avviato, aprire `http://localhost:8080/test/unit/unitTests.qunit.html`.

Prove end-to-end: `npm run test:e2e` avvia il server e Chrome headless (serve Google Chrome installato) ed esegue ogni file `webapp/test/e2e/*.e2e.mjs`, uno alla volta. `ams-panel-sandbox.e2e.mjs` usa il pannello solo da tastiera contro l'agente AMS simulato: lettura, piano, modifica, conferma, annullamento, login, interruzione, screenshot e codice del runner. Con `E2E_SHOTS=<cartella>` salva gli screenshot del pannello.

Build per il deploy: `npm run build` crea `dist/`, con Web Components e `marked` già inclusi. La cartella `webapp/test/` è esclusa dalla build.

## Deploy on-premise

### 1. Caricare la BSP `/REG/CINGHY`

Una volta sola: in [ui5-deploy.yaml](ui5-deploy.yaml) sostituire i `TODO` (URL del sistema, mandante, pacchetto ABAP), poi copiare `.env.example` in `.env` e inserire utente, password e ordine di trasporto. `.env` non va su git.

```sh
npm run deploy:test   # prova: il sistema controlla tutto ma non scrive nulla
npm run deploy        # build + caricamento di dist/ come BSP /REG/CINGHY
```

Serve il servizio OData `/sap/opu/odata/UI5/ABAP_REPOSITORY_SRV` attivo (/IWFND/MAINT_SERVICE) e l'autorizzazione `S_DEVELOP`. Per togliere l'app: `npm run undeploy`.

In alternativa, senza Node: `npm run build`, poi report `/UI5/UI5_REPOSITORY_LOAD` in SE38 caricando la cartella `dist/`.

### 2. Configurare il Launchpad

1. Catalogo tecnico in /UI2/FLPD_CUST (o Launchpad Content Manager), nessuna tile.
2. Target mapping: semantic object `Shell`, azione `plugin`, tipo applicazione SAPUI5 Fiori App, URL `/sap/bc/ui5_ui5/reg/cinghy`, ID `regesta.cinghy`.
3. Catalogo nel ruolo PFCG degli utenti.
4. Invalidare le cache: /UI2/INVALIDATE_GLOBAL_CACHES, /UI5/APP_INDEX_CALCULATE per `/REG/CINGHY`, poi svuotare la cache del browser.

### 3. Agente AMS su RST

Il pannello chiama il servizio dell'agente sullo stesso sistema del Launchpad, quindi Cinghy va deployato su RST.

1. Nodi SICF attivi: `/sap/bc/reg/cinghy_ams` (pannello, handler `/REG/CL_AMS_HTTP_CINGHY`) e `/sap/bc/reg/cinghy_ams_rn` (runner, handler `/REG/CL_AMS_HTTP_RUNNER`).
2. Ruolo PFCG `/REG/AMS` ai consulenti AMS: autorizza l'agente per portale. `/REG/AMS_ADMIN` aggiunge TuneCraft Run, per mantenere i profili dei portali.
3. Configurazione TuneCraft `CINGHY_AMS` in TuneCraft Run: modelli, limiti e profili dei portali.
4. Ogni consulente associa il proprio runner: pulsante con la catena nel pannello, poi `runner/README.md`.
