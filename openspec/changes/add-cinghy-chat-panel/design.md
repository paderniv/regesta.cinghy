# Design

## Context

Vedi proposal.md per la motivazione e specs/cinghy-chat-panel/spec.md per il comportamento atteso.

Stato di partenza, dopo la change `rename-namespace-regesta-cinghy`: plugin FLP `regesta.cinghy` (componente `sap.ui.core.Component`, tipo `plugin`), un solo `Component.js` che crea il pulsante con il servizio `Extension` e un handler di click segnaposto. Nessuna build, nessun test, nessun ambiente locale. Il sistema target ha SAPUI5 1.136 e il plugin gira sull'UI5 caricato dal Launchpad: non può sceglierne un altro.

## Goals / Non-Goals

**Goals:**
- Un pannello chat con aspetto nativo Fiori, che usa solo API pubbliche di UI5 e del Launchpad.
- Un confine netto tra interfaccia e servizio di risposta, così che il backend ABAP sostituisca la simulazione senza toccare la UI.
- Poter sviluppare e collaudare la grafica in locale, senza deploy.

**Non-Goals:**
- Pannello ridimensionabile, conversazioni multiple, cronologia permanente, streaming delle risposte.
- Pulsante "Nuova conversazione" (si può aggiungere dopo senza cambiare il resto).

## Decisions

### 1. Contenitore proprio, fisso a destra, montato con `placeAt`
Il plugin crea un suo elemento `div` dentro `document.body`, con `position: fixed`, e ci monta i controlli UI5 con `placeAt`. Il `div` vive per tutta la sessione del Launchpad, fuori dal contenitore delle app, quindi navigando tra app stato e conversazione restano.

Alternative scartate: `sap.m.Dialog` (sempre modale, blocca l'app); `sap.m.Popover` non modale (si chiude al primo click sull'app); inserirsi nel DOM interno della shell (API non pubblica, si rompe agli upgrade del Launchpad).

La posizione verticale parte sotto la shell bar: l'altezza della shell bar si legge all'apertura dall'elemento header della shell in sola lettura, con un valore di riserva da CSS se non si trova. È l'unico punto che legge il DOM della shell e resta isolato in una funzione.

### 2. Controlli: `sap.m` per la conversazione, Web Components AI per l'input
- Lista messaggi: `sap.m.List` con `sap.m.CustomListItem`, una classe CSS per mittente (`cinghyMsg--user`, `cinghyMsg--bot`). Su 1.136 nessuna libreria offre una conversazione pronta.
- Risposte: `sap.m.FormattedText`, che accetta solo un sottoinsieme di tag e attributi sicuri.
- Input: `PromptInput` di `@ui5/webcomponents-ai`, integrato con `ui5-tooling-modules` come da documentazione SAPUI5 1.136 ("Using Web Components").
- Header, avatar, indicatore di attesa: `sap.m.Toolbar`, `sap.m.Avatar`, `sap.m.BusyIndicator`.

Alternativa scartata: tutto in Web Components. La lista Web Components non dà vantaggi per le bolle, e mescolare meno tecnologie riduce i problemi di tema e focus. Il pacchetto AI è sperimentale: lo usiamo solo per l'input, che si può sostituire con `sap.m.TextArea` + `Button` senza toccare il resto.

### 3. Markdown: libreria `marked` + filtro di `FormattedText`
`marked` converte il markdown in HTML; `FormattedText` scarta tutto ciò che non è nella sua lista di tag e attributi ammessi (niente `script`, niente `on*`). Il filtro è nel controllo standard, non in codice nostro. `marked` viene impacchettata dalla stessa estensione `ui5-tooling-modules` che serve per i Web Components. I messaggi dell'utente vanno in un `sap.m.Text`, mai interpretati come HTML.

Alternativa scartata: un parser markdown scritto a mano. È più codice da mantenere e più facile da sbagliare.

### 4. Servizio di risposta con un solo metodo
Un modulo `ChatService` espone `send(messages, context) -> Promise<string>`. Nell'MVP la sua implementazione è simulata: ritardo breve, testo che dichiara di essere simulato e contiene esempi di markdown, ed errore forzabile per collaudare il "Riprova". Il backend ABAP futuro sostituirà solo questo modulo. `messages` è la cronologia completa, perché l'API di Claude non ricorda la conversazione.

### 5. Contesto dell'app dal servizio `AppLifeCycle`
Il servizio `AppLifeCycle` del Launchpad dà l'app corrente e un evento a ogni caricamento di app. Il contesto contiene oggetto semantico, azione e titolo, oppure l'indicazione Home. È un dato visibile nel chip e incluso in ogni messaggio.

### 6. Persistenza in `sessionStorage`
La conversazione si salva in `sessionStorage` sotto una chiave del namespace `regesta.cinghy`, dopo ogni messaggio. Lettura e scrittura sono in `try/catch`: se il browser le blocca, il pannello funziona senza conservazione. Lo stato aperto/chiuso resta in memoria e non sopravvive al ricaricamento.

### 7. Tema tramite variabili CSS di SAP
Il CSS del pannello usa solo le variabili del tema (`--sapBrandColor`, `--sapGroup_ContentBackgroundColor`, `--sapList_Background`, `--sapTextColor`, `--sapContent_Shadow1` e simili). Nessun colore scritto a mano: il cambio di tema, incluso alto contrasto, funziona senza codice. Il CSS si carica dal `manifest.json` (`sap.ui5/resources/css`).

### 8. Sviluppo locale con Launchpad sandbox
`package.json` + `ui5.yaml` con `framework: SAPUI5 1.136.x`, `ui5-tooling-modules` per task e middleware, e una pagina di test che avvia un Launchpad sandbox con il plugin registrato e almeno un'app di esempio per collaudare la navigazione. Il meccanismo esatto di avvio della sandbox su 1.136 si sceglie nel task di setup, verificando che carichi il plugin.

### 9. Pulsante visibile anche sulla Home
Dopo `showForAllApps()` si chiama anche `showOnHome()` sull'elemento creato dal servizio `Extension` (correzione emersa dall'audit).

## Risks / Trade-offs

- [Pacchetto `@ui5/webcomponents-ai` sperimentale, API che possono cambiare] → versione fissata in `package.json`; `PromptInput` confinato in un solo punto, sostituibile con `sap.m`.
- [Lettura dell'altezza della shell bar dal DOM della shell] → sola lettura, isolata in una funzione, con valore di riserva da CSS; nessuna modifica al DOM della shell.
- [Il pannello copre circa 400px dell'app] → scelta accettata: stile Joule; si chiude con un click o con Esc.
- [Build più grande per i Web Components impacchettati] → caricati solo quando il plugin parte; da misurare nella verifica in sistema.
- [Tag ammessi da `FormattedText` troppo pochi per alcune risposte (per esempio tabelle markdown)] → accettato per l'MVP; le tabelle diventano testo.

## Migration Plan

Si applica dopo la change `rename-namespace-regesta-cinghy`. Deploy del BSP `/REG/CINGHY` come oggi; nessun oggetto SAP nuovo. Rollback: ridistribuire la versione precedente del BSP.
