# Cinghy – plugin Fiori Launchpad

Plugin dello shell per S/4HANA on-premise (UI5 1.136): aggiunge il pulsante di Cinghy nella barra in alto del Launchpad e apre un pannello chat sopra l'app corrente. Finché il backend non è collegato, le risposte sono simulate.

- `webapp/Component.js`: plugin, pulsante (servizio Extension) e contesto dell'app corrente (servizio AppLifeCycle)
- `webapp/ChatPanel.js`: pannello chat fisso a destra
- `webapp/ChatService.js`: servizio di risposta, oggi simulato (il backend sostituirà solo questo modulo)
- `webapp/ConversationStore.js`: conversazione in `sessionStorage`
- `webapp/markdown.js`: risposte markdown → HTML, filtrato da `sap.m.FormattedText`
- `webapp/css/cinghy.css`: stile del pannello, solo variabili del tema SAP
- `webapp/img/03_analisi_dati_occhiali_ar.webp`: icona del pulsante Cinghy

## Sviluppo locale

Serve Node.js 20 o superiore.

```sh
npm install
npm start
```

`npm start` avvia `ui5 serve` con SAPUI5 1.136 e apre un Launchpad sandbox (`webapp/test/flpSandbox.html`) con il plugin e un'app di esempio, "Ordini demo". Nella chat, un messaggio che contiene `#errore` simula una risposta fallita.

Test unitari: con il server avviato, aprire `http://localhost:8080/test/unit/unitTests.qunit.html`.

Build per il deploy: `npm run build` crea `dist/`, con Web Components e `marked` già inclusi. La cartella `webapp/test/` è esclusa dalla build.

## Deploy on-premise

1. Deploy del contenuto di `dist/` come BSP `/REG/CINGHY`.
2. Catalogo tecnico in /UI2/FLPD_CUST o Launchpad Content Manager.
3. Target mapping: semantic object `Shell`, azione `plugin`, ID componente `regesta.cinghy`.
4. Catalogo nel ruolo PFCG degli utenti.
5. Invalidare le cache (/UI2/INVALIDATE_GLOBAL_CACHES, /UI5/APP_INDEX_CALCULATE).
