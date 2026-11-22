# Tasks

Prerequisito: change `rename-namespace-regesta-cinghy` applicata (namespace `regesta.cinghy`, `minUI5Version` 1.136.0).

## 1. Ambiente di sviluppo locale

- [x] 1.1 Creare `package.json` e `ui5.yaml` (framework SAPUI5 1.136.x, `ui5-tooling-modules` come task e middleware) e installare `@ui5/webcomponents`, `@ui5/webcomponents-ai`, `marked` come dipendenze; verificare che `npx ui5 serve` parta senza errori
- [x] 1.2 Creare la pagina Launchpad sandbox che registra il plugin `regesta.cinghy` e un'app di esempio navigabile; verificare aprendola in locale che il pulsante Cinghy compaia sulla Home e nell'app di esempio
- [x] 1.3 Documentare nel `README.md` come avviare l'ambiente locale; verificare che i comandi scritti funzionino da un clone pulito

## 2. Pulsante e pannello

- [x] 2.1 Aggiungere `showOnHome()` al pulsante; verificare nella sandbox che il pulsante sia visibile sulla Home e dentro l'app
- [x] 2.2 Creare il contenitore fisso a destra montato con `placeAt` (sotto la shell bar, larghezza circa 400px, piena larghezza su schermi stretti) e collegare il click del pulsante ad apertura/chiusura al posto della navigazione; verificare nella sandbox apertura, chiusura, URL invariato e che l'app sotto resti cliccabile
- [x] 2.3 Aggiungere header con avatar, titolo "Cinghy" e "x", chiusura con Esc e gestione del focus (all'input in apertura, al pulsante in chiusura); verificare da sola tastiera gli scenari di apertura e chiusura della spec
- [x] 2.4 Verificare che navigando tra Home e app di esempio il pannello resti aperto con lo stesso contenuto

## 3. Conversazione

- [x] 3.1 Creare il modulo `ChatService` con `send(messages, context)` simulato (ritardo, testo dichiarato simulato con markdown di esempio, errore forzabile) e un test QUnit che ne verifica risposta ed errore; verificare che il test passi
- [x] 3.2 Creare la lista messaggi con bolle utente a destra e Cinghy a sinistra, testo utente come testo semplice, risposte via `marked` + `FormattedText`, link in nuova scheda; aggiungere un test QUnit che verifica che `<script>` e `onerror` nella risposta non arrivino al DOM; verificare che il test passi e che la risposta simulata sia formattata nella sandbox
- [x] 3.3 Integrare `PromptInput` AI per l'invio con pulsante e tasto Invio, blocco dei messaggi vuoti, invio disabilitato e indicatore "Cinghy sta scrivendo" durante l'attesa, scroll all'ultimo messaggio; verificare nella sandbox gli scenari di invio e risposta della spec
- [x] 3.4 Mostrare l'errore con azione "Riprova" quando `send` fallisce; verificare forzando l'errore nel servizio simulato

## 4. Contesto e persistenza

- [x] 4.1 Leggere il contesto dal servizio `AppLifeCycle` (oggetto semantico, azione, titolo, oppure Home), mostrarlo nel chip sotto l'input, aggiornarlo a ogni navigazione e passarlo a `send`; verificare nella sandbox che il chip cambi tra Home e app di esempio e che il contesto arrivi al servizio
- [x] 4.2 Salvare e rileggere la conversazione in `sessionStorage` con `try/catch`; aggiungere un test QUnit che verifica il ripristino e il funzionamento con `sessionStorage` che lancia eccezioni; verificare che il test passi e che nella sandbox la conversazione sopravviva a F5

## 5. Tema e accessibilità

- [x] 5.1 Scrivere il CSS del pannello usando solo variabili del tema SAP, caricato dal `manifest.json`; verificare nella sandbox con Horizon chiaro, Horizon scuro e alto contrasto nero che testo e bolle siano leggibili, cambiando tema senza ricaricare
- [ ] 5.2 Aggiungere ruoli e nomi accessibili a pannello e lista e una regione live per le nuove risposte; verificare con un lettore di schermo (VoiceOver) che la risposta venga annunciata

## 6. Verifica in sistema

- [ ] 6.1 Eseguire `npx ui5 build`, verificare che il risultato contenga Web Components e `marked` impacchettati, deployare su `/REG/CINGHY` e invalidare le cache; aprire il Launchpad del sistema 1.136 e ripercorrere gli scenari della spec su Home e su almeno due app standard

## Workflow follow-up

- Archiviare la change dopo la verifica in sistema.
