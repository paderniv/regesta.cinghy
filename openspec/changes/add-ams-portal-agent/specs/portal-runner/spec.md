# Spec Delta

## Purpose

Il runner che esegue nel browser le azioni dell'agente AMS sui portali clienti, collegandosi in uscita a RST, e che può girare sul PC del consulente o su un server Regesta.

## ADDED Requirements

### Requirement: Collegamento in uscita verso RST
Il runner SHALL collegarsi a RST solo con connessioni HTTPS in uscita e ricevere da lì le azioni da eseguire. RST MUST NOT dover aprire connessioni verso il runner.

#### Scenario: Runner dietro rete aziendale
- **GIVEN** il PC del consulente può raggiungere RST in HTTPS ma non è raggiungibile da RST
- **WHEN** l'agente ha un'azione per quel runner
- **THEN** il runner la riceve ed esegue

### Requirement: Runner associato e autenticato
Ogni runner SHALL essere associato a un utente RST (runner locale) o registrato come runner centrale, e SHALL autenticarsi a RST a ogni collegamento. Un runner locale MUST ricevere solo le azioni delle operazioni del proprio consulente.

#### Scenario: Azioni di un altro consulente
- **GIVEN** i runner locali di due consulenti sono collegati
- **WHEN** il primo consulente avvia un'operazione
- **THEN** solo il runner del primo consulente riceve le azioni

#### Scenario: Runner non autenticato
- **WHEN** un runner si collega senza un'autenticazione valida
- **THEN** RST rifiuta il collegamento e non gli consegna azioni

### Requirement: Runner non disponibile
Quando il runner richiesto dal profilo non è collegato, l'agente SHALL dirlo al consulente invece di attendere senza limite.

#### Scenario: Runner locale spento
- **GIVEN** il profilo Pittini richiede il runner locale e il runner del consulente non è collegato
- **WHEN** il consulente dà un'istruzione su Pittini
- **THEN** Cinghy risponde che il runner non è collegato e come avviarlo

### Requirement: Esecuzione delle azioni del browser
Il runner SHALL eseguire solo le azioni del browser ricevute da RST (navigare, leggere la pagina, cliccare, compilare, catturare screenshot) e restituire a RST l'esito e la descrizione della pagina risultante.

#### Scenario: Azione eseguita
- **WHEN** il runner riceve "apri il ticket 12345"
- **THEN** esegue l'azione e restituisce a RST la descrizione testuale della pagina aperta

#### Scenario: Azione fallita
- **WHEN** un elemento richiesto non esiste o la pagina non risponde entro il tempo massimo
- **THEN** il runner restituisce a RST un errore con la descrizione della pagina corrente

### Requirement: Accesso limitato ai portali del profilo
Il runner SHALL navigare solo verso i domini consentiti dal profilo del portale in uso, compresi quelli del login.

#### Scenario: Link esterno in un ticket
- **WHEN** l'agente chiede di aprire un indirizzo fuori dai domini del profilo
- **THEN** il runner rifiuta l'azione e lo segnala a RST

### Requirement: Login gestito dal runner
Il login al portale SHALL essere gestito dal runner senza il modello: nel runner locale tramite la sessione del browser del consulente, che il consulente apre di persona; nel runner centrale con credenziali conservate fuori da RST e dal modello.

#### Scenario: Sessione locale scaduta
- **GIVEN** il runner locale trova la pagina di login del portale
- **WHEN** l'agente sta eseguendo un'operazione
- **THEN** l'operazione si sospende, Cinghy chiede al consulente di accedere nel browser del runner e riprende dopo il login

#### Scenario: Sessione valida
- **GIVEN** il consulente ha già effettuato l'accesso nel browser del runner
- **WHEN** l'agente apre il portale
- **THEN** il portale è accessibile senza nuovo login

### Requirement: Browser visibile nel runner locale
Il runner locale SHALL usare un browser visibile al consulente, con un profilo dedicato che conserva le sessioni tra un avvio e l'altro, separato dal browser personale del consulente.

#### Scenario: Consulente che osserva
- **WHEN** l'agente lavora tramite il runner locale
- **THEN** il consulente vede nel browser del runner le pagine e le azioni in corso
