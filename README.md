# Cinghy – plugin Fiori Launchpad

Plugin dello shell per S/4HANA on-premise (UI5 1.136): aggiunge il pulsante di Cinghy nella barra in alto del Launchpad e apre un pannello chat sopra l'app corrente. Finché il backend non è collegato, le risposte sono simulate.

- `webapp/Component.js`: plugin, pulsante (servizio Extension) e contesto dell'app corrente (servizio AppLifeCycle)
- `webapp/ChatPanel.js`: pannello chat fisso a destra
- `webapp/ChatService.js`: servizio di risposta, oggi simulato (il backend sostituirà solo questo modulo)
- `webapp/ConversationStore.js`: conversazione in `sessionStorage`
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

`npm start` avvia `ui5 serve` con SAPUI5 1.136 e apre un Launchpad sandbox (`webapp/test/flpSandbox.html`) con il plugin e un'app di esempio, "Ordini demo". Nella chat, un messaggio che contiene `#errore` simula una risposta fallita. Con `?shellBar=true` nell'URL (`test/flpSandbox.html?shellBar=true#Shell-home`) la sandbox usa la shell bar a Web Components, come sul sistema S/4.

Test unitari: con il server avviato, aprire `http://localhost:8080/test/unit/unitTests.qunit.html`.

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
