# Tasks

## 1. Fondamenta su RST

- [x] 1.1 Creare il pacchetto `/REG/CINGHY_AMS` e le tabelle `/REG/` per runner, operazioni (con conversazione salvata) e passi (coda azioni, registro e screenshot) (design 8); verificare con attivazione senza errori
- [x] 1.2 Creare l'oggetto di autorizzazione (portale, attività usare) e i ruoli PFCG "consulente AMS" e "amministratore agente" (consulente più accesso a TuneCraft Run); verificare con SU53 che un utente senza ruolo riceva il rifiuto
- [x] 1.3 Creare la tabella `/REG/AMS_KEY` e il report di inserimento della chiave con controllo di autorizzazione, e per ogni fornitore usato (OpenAI, Gemini) la destinazione SM59 con certificato in STRUST e la chiave; verificare con una chiamata di prova per fornitore che restituisce una risposta
- [x] 1.4 Creare schema e configurazione TuneCraft `CINGHY_AMS` con impostazioni dell'agente, modelli disponibili e profilo Pittini (URL, domini del portale e di login, runner locale, nessuna password) e la classe che li legge in `app_cfg_par`; verificare con ABAP Unit sulla lettura del JSON di configurazione e, dopo l'import in Build e Run, che lo storico delle revisioni registri autore e data

## 2. Client del modello in ABAP

- [x] 2.1 Implementare l'interfaccia `/REG/IF_AMS_LLM`, il formato neutro di conversazione e risposta (design 2) e la factory che sceglie l'adattatore dal modello del portale o dal predefinito; verificare con ABAP Unit la scelta del modello, compreso il portale con modello proprio
- [x] 2.2 Implementare il salvataggio e la ripresa della conversazione in formato neutro e la riduzione delle descrizioni di pagina più vecchie (design 2); verificare con ABAP Unit che sotto la soglia la conversazione non cambi, che sopra la soglia resti solo l'ultima descrizione completa e che una conversazione salvata e riletta sia identica
- [x] 2.3 Implementare l'adattatore OpenAI (strumenti, errori HTTP, limiti di frequenza, token consumati); verificare con ABAP Unit su risposte registrate, inclusa una chiamata a uno strumento e la restituzione del suo risultato
- [x] 2.4 Implementare l'adattatore Google Gemini con le stesse capacità; verificare con ABAP Unit su risposte registrate, inclusa una chiamata a uno strumento e la restituzione del suo risultato
- [ ] 2.5 Implementare l'adattatore Anthropic con le stesse capacità; verificare con ABAP Unit su risposte registrate, inclusa una chiamata a uno strumento e la restituzione del suo risultato

## 3. Ciclo dell'agente

- [x] 3.1 Implementare l'operazione con i suoi stati, l'unità in background bgPF che esegue un passo e termina, l'avvio del passo successivo su evento (istruzione, esito del runner, conferma, accesso fatto), il limite di passi e il controllo del timeout alla lettura dello stato (design 1); verificare con ABAP Unit le transizioni di stato, il limite di passi e il timeout
- [x] 3.2 Implementare il prompt di sistema con regole e istruzioni del profilo e la delimitazione del contenuto del portale come dato non attendibile (design 9); verificare con ABAP Unit il testo prodotto per il profilo Pittini
- [x] 3.3 Implementare il filtro delle azioni per fase di lettura ed esecuzione, con pulsanti "sicuri" da profilo e passo del piano obbligatorio (design 3); verificare con ABAP Unit che un clic su un pulsante non sicuro in lettura sia rifiutato
- [x] 3.4 Implementare `propose_plan` (attesa di conferma, fine del processo) e la ripresa dopo conferma, annullamento o modifica del piano; verificare con ABAP Unit i tre casi della spec
- [x] 3.5 Implementare verifica finale, esito per modifica e `report`; verificare con ABAP Unit il caso di esecuzione parziale
- [x] 3.6 Implementare interruzione, sospensione per login, runner non collegato e registro di ogni azione con consulente, elemento, esito e costo; verificare con ABAP Unit che il registro contenga il consulente per ogni modifica

## 4. Servizi HTTP su RST

- [ ] 4.1 Servizio per Cinghy: avviare un'operazione, leggerne lo stato, confermare/annullare/modificare il piano, interrompere, "ho fatto l'accesso", generare il codice di associazione del runner; con controllo autorizzazioni; verificare con chiamate di prova (REST client) per ogni endpoint, incluso un utente non autorizzato
- [ ] 4.2 Servizio per i runner: scambio codice/token (solo hash salvato), long polling delle azioni (30 s), invio esiti e upload screenshot; consegna solo al runner del consulente proprietario; verificare con chiamate di prova che un token di un altro consulente non riceva azioni e che un token revocato sia rifiutato

## 5. Runner

- [x] 5.1 Creare `runner/` in questo repo (Node.js, `@playwright/mcp`, client MCP) con avvio di Playwright MCP in modalità visibile e profilo browser persistente dedicato; verificare che `npm start` apra il browser e che un login resti valido dopo il riavvio
- [x] 5.2 Implementare associazione con codice, long polling, esecuzione delle azioni via MCP, invio esiti e screenshot, riconnessione automatica; verificare con un test contro un RST simulato in locale
- [x] 5.3 Implementare il limite ai domini del profilo e il rilevamento delle pagine di login con risposta "login richiesto" senza descrizione della pagina; verificare con test su un dominio non consentito e su `login.microsoftonline.com`
- [ ] 5.4 Documentare installazione, associazione e avvio in `runner/README.md`; verificare seguendo il README su un PC pulito

## 6. Cinghy

- [x] 6.1 Collegare `ChatService.js` al servizio di RST (avvio operazione, id in `sessionStorage`, polling ogni 2 s, ripresa alla riapertura) mantenendo la simulazione per la sandbox; verificare con QUnit su un backend simulato
- [x] 6.2 Mostrare nel pannello avanzamento, pulsante di interruzione, piano con "Conferma" e "Annulla", richiesta di login con "Ho fatto l'accesso", esito con screenshot, accessibili da tastiera e lettore di schermo; verificare con test e2e nella sandbox
- [x] 6.3 Aggiungere in Cinghy la generazione del codice di associazione del runner; verificare nella sandbox con backend simulato
- [ ] 6.4 Aggiornare il README con l'uso dell'agente AMS e il deploy su RST; verificare che i passi descritti corrispondano a quelli eseguiti

## 7. Pilota Pittini

- [ ] 7.1 Deploy di Cinghy sul Launchpad di RST, ruoli ai consulenti pilota, runner installati e associati; verificare che il pulsante compaia e che lo stato runner risulti collegato
- [ ] 7.2 Confermare con Pittini l'uso dell'agente sul loro portale e i ticket di prova; verificare con accordo scritto
- [x] 7.3 Completare le istruzioni di navigazione e le corrispondenze del profilo Pittini dopo l'analisi del portale; verificare con un'operazione di sola lettura su un ticket reale
- [ ] 7.4 Eseguire sul portale Pittini le operazioni del pilota (lettura, commento, cambio stato/priorità/assegnazione) su ticket di prova con conferma del piano; verificare esiti, screenshot e registro
- [ ] 7.5 Provare un ticket di prova con istruzioni malevole nel testo; verificare che l'agente non esegua azioni non confermate

## Workflow follow-up

- Archiviare la change dopo il pilota e la revisione del registro.
- Valutare il runner centrale (login automatico e vault delle credenziali) in una change separata.
