# Proposal

## Why

Cinghy deve diventare l'assistente AI personale degli utenti S/4HANA, sul modello di SAP Joule. Oggi il plugin `regesta.cinghy` mette solo un pulsante nella shell bar che naviga a un'app segnaposto. Serve la parte visibile dell'assistente: una chat che si apre sopra l'app corrente, con una grafica rifinita e coerente con il tema Fiori, da poter mostrare e collaudare prima che esista il backend.

## What Changes

- Il click sul pulsante Cinghy non naviga più: apre e chiude un pannello chat fisso sul lato destro, sopra l'app corrente, che resta usabile.
- Il pulsante Cinghy è visibile sia sulla Home del Launchpad sia dentro le app.
- Il pannello mostra la conversazione a bolle (utente a destra, Cinghy a sinistra), con le risposte di Cinghy formattate in markdown in modo sicuro, un indicatore di attesa e un campo di input basato su `PromptInput` delle UI5 Web Components AI.
- Il pannello mostra il contesto dell'app corrente (livello 2 dell'MVP) e lo allega a ogni messaggio inviato.
- La conversazione sopravvive alla navigazione tra app e al ricaricamento della pagina, e sparisce alla chiusura della scheda del browser.
- Finché il backend ABAP non esiste, le risposte di Cinghy sono simulate.
- Il progetto ottiene un ambiente di sviluppo locale: `package.json`, `ui5.yaml` con `ui5-tooling-modules` e un Launchpad sandbox che carica il plugin.

Fuori scope: backend ABAP e chiamata a Claude, tool che leggono o modificano dati SAP (livello 3), salvataggio permanente della conversazione, deploy automatico sul sistema.

## Capabilities

### New Capabilities

- `cinghy-chat-panel`: il pannello chat dell'assistente Cinghy nel Launchpad, cioè apertura e chiusura, conversazione, contesto dell'app corrente, persistenza nella sessione del browser, tema e accessibilità.

### Modified Capabilities

Nessuna.

## Impact

- Codice: `webapp/Component.js` (il handler del click cambia), nuovi moduli e CSS per il pannello in `webapp/`, `webapp/manifest.json` (dipendenze e risorse CSS), nuovi `package.json`, `ui5.yaml`, pagina sandbox di test.
- Dipendenze npm: `@ui5/webcomponents`, `@ui5/webcomponents-ai`, `ui5-tooling-modules`, una libreria di conversione markdown.
- Prerequisito: la change `rename-namespace-regesta-cinghy` (namespace `regesta.cinghy`, UI5 1.136) deve essere applicata prima.
- Sistema SAP: nessun oggetto nuovo; il BSP `/REG/CINGHY` riceve una build più grande, perché contiene i Web Components impacchettati.
