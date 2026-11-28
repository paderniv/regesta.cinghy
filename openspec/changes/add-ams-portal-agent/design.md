# Design

## Context

Vedi proposal.md per la motivazione e le spec `ams-portal-agent`, `portal-runner`, `portal-profiles` per il comportamento atteso.

Stato di partenza: il plugin Cinghy (`regesta.cinghy`) è un pannello chat nel Launchpad con risposte simulate (`ChatService.js`); non esiste ancora alcun backend. Il runtime scelto per l'agente è ABAP sul sistema Regesta RST, su cui Regesta ha pieno controllo. I portali clienti sono siti web senza API, spesso dietro login di terzi (per Pittini: Microsoft Entra ID tramite Azure App Proxy, account condiviso, senza MFA). ABAP non può guidare un browser: serve un processo esterno.

## Goals / Non-Goals

**Goals:**
- Un solo componente runner, uguale in locale e in centrale: cambia solo dove è installato e chi lo usa.
- Le regole di sicurezza (fasi, conferma, domini, credenziali) applicate dal codice su RST e nel runner, non solo chieste al modello.
- Il modello è sostituibile per configurazione: il ciclo dell'agente, la conversazione salvata e gli strumenti sono indipendenti dal fornitore; solo un adattatore per fornitore conosce la sua API. I profili sono testo, non codice legato a un modello.

**Non-Goals:**
- Streaming delle risposte del modello nel pannello.
- Più operazioni in parallelo per lo stesso consulente: una alla volta.
- Esecuzione del login automatico nel runner centrale (arriverà con il runner centrale).

## Decisions

### 1. Ciclo dell'agente in ABAP, a passi brevi in background guidati da eventi
L'istruzione del consulente crea un'**operazione** su RST. Il ciclo dell'agente non è un processo che resta in vita fino alla fine: ogni passo è un'**unità in background breve** del Background Processing Framework (bgPF, `CL_BGMC_PROCESS_FACTORY`, basato su bgRFC, rilasciato e realizzato con classi, quindi senza moduli funzione), che parte quando arriva un evento, fa il suo lavoro e termina senza aspettare nulla:

```
istruzione del consulente  --> unità: chiama il modello, mette l'azione in coda          --> fine
esito dal runner            --> unità: registra l'esito, chiama il modello, nuova azione  --> fine
piano proposto              --> stato "piano in attesa"                                    --> fine
conferma del consulente     --> unità: riprende dalla conversazione salvata                --> ...
login richiesto             --> stato "login"  ...  "Ho fatto l'accesso" --> unità: riprende --> ...
```

Tra un passo e l'altro non c'è nessun processo attivo: lo stato dell'operazione (in lettura, piano in attesa, in esecuzione, sospesa per login, finita, interrotta, errore) e la conversazione sono solo nelle tabelle. Gli eventi arrivano dai servizi HTTP (decisione 4 e 7): il servizio per il runner avvia l'unità successiva quando riceve un esito, il servizio per Cinghy quando il consulente conferma, annulla, modifica il piano o segnala l'accesso fatto. Il flag di interruzione si legge all'inizio di ogni unità, quindi l'agente si ferma dopo l'azione in corso.

Vantaggi rispetto a un processo che resta in vita e attende:
- **Nessun processo SAP occupato ad aspettare.** I processi di lavoro in background sono pochi per server e condivisi da tutte le applicazioni di RST. Un processo che attende un login di 10 minuti o una conferma del piano li terrebbe fermi senza lavorare, mettendo in coda gli altri lavori in background del sistema; qui un processo è occupato solo per i secondi della chiamata al modello, qualunque sia il numero di consulenti in attesa.
- **Reazione immediata e nessun carico di attesa.** L'unità parte nel momento in cui arriva l'esito o la conferma; un processo in attesa se ne accorgerebbe solo al controllo successivo e intanto interrogherebbe la tabella ogni secondo per ogni operazione aperta.
- **Nessuno stato perso se un processo si interrompe.** Riavvio del sistema, limite di tempo del framework o intervento di Basis non fanno perdere nulla: tra un passo e l'altro non c'è niente in memoria, e il passo successivo riparte dalle tabelle.
- **Un solo meccanismo.** Attesa dell'esito del runner, del login e della conferma del piano funzionano tutte allo stesso modo: fine dell'unità e ripresa dalla conversazione salvata. Non servono un ciclo con attesa e una ripresa separata.

Costi accettati:
- ogni unità rilegge operazione e conversazione dal database: millisecondi contro i secondi della chiamata al modello;
- i servizi HTTP per Cinghy e per il runner avviano l'unità successiva quando ricevono un evento;
- i timeout (runner non collegato, nessuna risposta del consulente oltre `TIMEOUT_MINUTES`) si controllano quando Cinghy o il runner leggono lo stato, non con un job pianificato: un'operazione abbandonata a pannello chiuso resta in attesa finché qualcuno non la rilegge, senza consumare nulla.

Alternative scartate: un processo in background che esegue tutto il ciclo e attende gli esiti interrogando la tabella (vedi vantaggi sopra); ciclo nella richiesta HTTP di Cinghy (timeout ICM dopo pochi minuti, si perde chiudendo il pannello); ciclo nel runner in Node (sposterebbe la logica e le regole fuori da RST, contro la scelta del runtime ABAP); bgRFC classico con modulo funzione (stesso motore di bgPF ma i moduli funzione non si possono gestire come file con abap-sync).

### 2. Client del modello indipendente dal fornitore
Il ciclo dell'agente usa un'interfaccia propria (`/REG/IF_AMS_LLM`) con un solo metodo: riceve la conversazione e restituisce la risposta. Conversazione e risposta sono in un **formato neutro** nostro: prompt di sistema, strumenti (nome, descrizione, parametri come JSON Schema), messaggi dell'utente, risposte del modello con le chiamate agli strumenti, risultati degli strumenti; nella risposta anche i token consumati e il motivo di fine. È questo formato, non quello di un fornitore, che si salva in `/REG/AMS_OP` e si rimanda a ogni passo: come fa un IDE con l'assistente, la memoria della conversazione è nostra e non dipende dal fornitore.

Un **adattatore per fornitore** traduce il formato neutro nell'API del fornitore e viceversa, con `CL_HTTP_CLIENT` su una destinazione SM59 di tipo G (certificato in STRUST):
- OpenAI (API Chat Completions con `tools`);
- Google Gemini (API `generateContent` con `functionDeclarations`);
- Anthropic (API Messages con `tools`), da attivare quando ci sarà la chiave.

Ogni adattatore gestisce autenticazione, errori HTTP, limiti di frequenza e le opzioni di ragionamento del suo fornitore con valori predefiniti propri, senza configurazione aggiuntiva. Una factory sceglie l'adattatore dal tipo di fornitore del modello configurato.

Configurazione in TuneCraft (decisione 8): un elenco di modelli (codice, tipo di fornitore, nome del modello, destinazione SM59), il modello predefinito e, per ogni portale, un modello facoltativo che sostituisce il predefinito. Così il modello si sceglie anche per cliente, per esempio in base ai suoi vincoli contrattuali sui dati. Il modello usato è registrato nell'operazione all'avvio e resta lo stesso fino alla fine, anche dopo l'attesa del piano: cambiare la configurazione vale per le operazioni successive.

Chiavi API: una tabella `/REG/AMS_KEY` (codice del modello, chiave) senza manutenzione SM30, riempita da un report con controllo di autorizzazione e letta solo dall'adattatore. La chiave è in chiaro nel database: chi ha `S_TABU_NAM` su quella tabella la può leggere.

Strumenti dichiarati al modello, uguali per tutti i fornitori:
- strumenti del browser, uguali a quelli di Playwright MCP (navigare, leggere la pagina, cliccare, scrivere, selezionare, screenshot), inoltrati al runner;
- `propose_plan`: elenco di modifiche e testo delle risposte, che porta l'operazione in attesa di conferma;
- `report`: risposta finale al consulente.

Per contenere i token, le descrizioni di pagina più vecchie sono ridotte a una riga scritta dal codice con titolo e indirizzo ("pagina Ticket 12345 letta"), senza chiamare il modello; resta completa solo l'ultima. La riduzione scatta solo quando la conversazione supera una soglia (circa 30 mila token stimati) e allora riduce tutte le pagine vecchie insieme: tra una riduzione e l'altra la conversazione cresce solo in fondo, così il caching del prefisso dei fornitori continua a valere. La riduzione lavora sul formato neutro, quindi vale per tutti i fornitori; le pagine complete restano nel registro dei passi.

Alternative scartate:
- ABAP AI SDK con SAP AI Core e generative AI hub: indipendente dal fornitore e senza chiavi nel nostro codice, ma richiede SAP AI Core su BTP e la sua conversazione è un oggetto in memoria che non si può salvare e riprendere con le chiamate agli strumenti, mentre il nostro ciclo termina durante l'attesa del piano.
- Un solo fornitore con la sua API usata direttamente nel ciclo dell'agente: più semplice, ma cambiare fornitore vorrebbe dire riscrivere il ciclo e perdere le conversazioni salvate.
- Connettore MCP lato API del fornitore (il modello chiama direttamente un server MCP remoto): richiederebbe di esporre su Internet un browser già autenticato nei portali dei clienti.

### 3. Fasi applicate da RST, non solo dal prompt
RST filtra ogni azione del browser prima di metterla in coda:
- **fase di lettura**: consentiti navigare, leggere, screenshot, cliccare elementi con ruolo link, scheda, voce di menu, riga, e i pulsanti elencati come "sicuri" nel profilo (per esempio "Cerca"); scrivere solo in campi di ricerca; ogni altra azione è rifiutata con un errore restituito al modello ("in fase di lettura: proponi un piano");
- **fase di esecuzione**: ogni azione di modifica deve indicare il passo del piano confermato a cui appartiene; azioni senza passo valido sono rifiutate e l'operazione si ferma chiedendo nuova conferma.

È un filtro, non una garanzia: un pulsante "sicuro" mal configurato può modificare. Per questo il registro salva ogni azione con il ruolo e il nome dell'elemento.

### 4. Runner: ponte Node.js + Playwright MCP
Il runner è un'app Node.js che:
- si collega a RST in HTTPS con **long polling** (richiesta che resta aperta fino a 30 s finché non c'è un'azione), e invia gli esiti con chiamate separate;
- avvia `@playwright/mcp` come processo figlio (MCP su stdio) e gli passa le azioni ricevute tramite il client MCP ufficiale;
- usa un profilo browser dedicato e persistente (`--user-data-dir`), visibile nel runner locale;
- limita la navigazione ai domini del profilo con un controllo proprio: prima di aprire un indirizzo e dopo ogni azione (se la pagina è finita fuori dominio torna indietro senza descriverla). L'opzione `--allowed-origins` di Playwright MCP non si usa: blocca anche le risorse dei portali su altri domini (per esempio le CDN del login Microsoft) e per sua documentazione non è un confine di sicurezza;
- dopo ogni azione restituisce la descrizione completa della pagina (`browser_snapshot`), perché il filtro su RST legge ruolo e nome degli elementi dall'ultima pagina; traduce `ref` in `target` e scarta gli argomenti che Playwright MCP non conosce (`plan_step`), e cancella i file di pagine e screenshot che Playwright MCP salva su disco;
- carica gli screenshot su RST.

Alternative scartate: WebSocket tramite ABAP Push Channel per il runner (più complesso da rendere affidabile attraverso proxy aziendali, guadagno minimo con azioni da secondi); Computer Use con screenshot (più costoso e lento della descrizione testuale della pagina; resta possibile in futuro per portali dove l'albero di accessibilità è povero).

### 5. Associazione del runner con un codice
Il consulente genera in Cinghy un codice monouso di associazione; al primo avvio il runner lo scambia con un token lungo, salvato in locale. RST conserva solo l'hash del token, legato all'utente del consulente, e permette di revocarlo. Il runner non conosce la password SAP del consulente.

### 6. Login rilevato dal runner, completato dal consulente
Il profilo elenca i domini di login (per Pittini `login.microsoftonline.com`). Se dopo un'azione la pagina è su un dominio di login, il runner restituisce "login richiesto" invece della descrizione della pagina: l'operazione va in stato sospeso e Cinghy chiede al consulente di accedere nel browser del runner. Il consulente preme "Ho fatto l'accesso" e l'operazione riprende. Così la pagina di login e ciò che vi si digita non arrivano mai al modello.

### 7. Cinghy: polling dello stato dell'operazione
`ChatService.js` invia l'istruzione al servizio HTTP di Cinghy su RST e riceve l'id dell'operazione, salvato con la conversazione in `sessionStorage`. Finché l'operazione è attiva, il pannello interroga lo stato ogni 2 s e mostra: passo in corso, piano con pulsanti "Conferma" e "Annulla", richiesta di login, esito con screenshot. Riaprendo il pannello si riprende il polling dall'id salvato.

Alternativa scartata per ora: ABAP Push Channel verso il pannello; il polling basta con un utente e un'operazione per volta.

### 8. Dati su RST
Configurazione in TuneCraft, app `CINGHY_AMS` (blank variant), letta con `/REG/CL_TUNECRAFT_CFG_READER` in una struttura `app_cfg_par` come in RoboDoc: impostazioni dell'agente (modelli disponibili e predefinito, passi massimi, timeout) e profili dei portali in tabelle denormalizzate per portale (portali con il loro modello facoltativo, domini, pulsanti "sicuri", corrispondenze dei valori), perché una colonna di tabella TuneCraft non può essere a sua volta una tabella. Lo storico delle revisioni di TuneCraft traccia autore e data di ogni modifica. Nessun segreto in TuneCraft: chi apre Run vede tutto.

Quattro tabelle nel namespace `/REG/`, pacchetto `/REG/CINGHY_AMS`, per i dati che crescono con l'uso: runner associati (`/REG/AMS_RUN`), operazioni con stato, modello usato, piano, esito e conversazione salvata in formato neutro (`/REG/AMS_OP`), passi (`/REG/AMS_STEP`), chiavi API dei modelli (`/REG/AMS_KEY`, decisione 2). Un passo è insieme elemento della coda per il runner e riga del registro: azioni del browser con elemento, esito e screenshot, piani proposti e decisioni del consulente.

Oggetto di autorizzazione proprio con campi portale e attività (usare), verificato dal servizio di Cinghy. Chi modifica i profili lo decide l'accesso a TuneCraft Run.

Alternativa scartata: tabelle dei profili con vista di manutenzione SM30. TuneCraft evita generatore di manutenzione e log tabellari ed è già lo strumento di configurazione di Regesta; il prezzo è che non ha autorizzazioni per singola app, quindi chiunque abbia TuneCraft Run può modificare i profili AMS (lo storico lo mostra, non lo impedisce).

### 9. Il testo del portale entra solo come dato
Il prompt di sistema contiene le regole e le istruzioni del profilo; il contenuto delle pagine arriva solo nei risultati degli strumenti, delimitato e preceduto dall'avviso che è contenuto non attendibile. Le difese reali restano quelle applicate dal codice (decisioni 3, 5, 6): anche se il modello seguisse un'istruzione malevola, non potrebbe modificare senza piano confermato né uscire dai domini del profilo.

## Risks / Trade-offs

- [Il portale cambia interfaccia] → le istruzioni del profilo descrivono cosa cercare (etichette, sezioni), non coordinate; un errore dell'agente si corregge aggiornando il profilo.
- [Pulsante "sicuro" che in realtà modifica] → elenco corto e rivisto, registro di ogni clic con nome dell'elemento.
- [Costi del modello per operazioni lunghe] → descrizioni di pagina ridotte nella conversazione, limite massimo di passi per operazione, costo per operazione nel registro.
- [Account condiviso Pittini bloccato da Microsoft] → nel pilota solo runner locale, dagli stessi PC da cui i consulenti accedono oggi.
- [Pittini non informato dell'uso di un agente] → accordo con il cliente prima del pilota su dati reali.
- [Dati dei clienti inviati al fornitore del modello] → il modello si sceglie per portale, quindi si può rispettare il vincolo contrattuale di ogni cliente; da confermare per ogni cliente in base ai contratti AMS.
- [Comportamento diverso tra modelli] → stessi strumenti e stesse regole applicate dal codice per tutti; le istruzioni dei profili vanno provate con il modello scelto per quel portale.
- [Runner spento o PC in standby] → stato "runner non collegato" esplicito e timeout dell'operazione.

## Migration Plan

1. Servizi, tabelle e autorizzazioni su RST; destinazioni SM59 e chiavi API dei fornitori usati.
2. Deploy di Cinghy anche sul Launchpad di RST, ruolo per il reparto AMS.
3. Runner installato sui PC dei consulenti del pilota e associato.
4. Profilo Pittini; prove prima in sola lettura, poi con modifiche su ticket di prova concordati.

Rollback: togliere il ruolo agli utenti; il runner smette di ricevere azioni. Nessun dato SAP di business viene modificato.

## Open Questions

- Per quanto tempo conservare registro e screenshot, e chi può consultarli.
- Se il Launchpad su cui è già installato Cinghy è RST o un altro sistema.
- Come distribuire il runner ai consulenti (pacchetto npm interno, eseguibile, script di installazione).
