# Spec Delta

## Purpose

I profili dei portali di ticketing dei clienti, conservati su RST, che permettono all'agente AMS di lavorare su un nuovo portale con sola configurazione e senza sviluppo.

## ADDED Requirements

### Requirement: Contenuto del profilo
Ogni portale cliente SHALL avere un profilo nella configurazione TuneCraft dell'agente su RST con: nome del cliente, URL di ingresso, domini consentiti, runner da usare (locale o centrale), modello da usare se diverso dal predefinito, modalità di login, istruzioni di navigazione in testo libero e corrispondenze dei valori (priorità, stati, gruppi).

#### Scenario: Profilo Pittini
- **WHEN** si configura il portale Pittini
- **THEN** il profilo contiene URL `https://hdserver.pittini.it/`, i domini del portale e di Microsoft Entra ID, runner locale e login con account condiviso

### Requirement: Modello scelto per configurazione
Il modello linguistico usato dall'agente SHALL essere una scelta di configurazione: un elenco di modelli disponibili di fornitori diversi, uno predefinito e, per ogni portale, un modello facoltativo che lo sostituisce. Cambiare modello o fornitore MUST NOT richiedere modifiche al codice. Un'operazione SHALL usare per tutta la sua durata il modello con cui è iniziata.

#### Scenario: Portale con un modello proprio
- **GIVEN** il modello predefinito è di OpenAI e il profilo Pittini indica un modello Gemini
- **WHEN** il consulente dà un'istruzione su Pittini
- **THEN** l'agente lavora con il modello Gemini e il registro dell'operazione indica quale modello è stato usato

#### Scenario: Cambio di modello durante un'operazione
- **GIVEN** un'operazione su Pittini è in attesa di conferma del piano
- **WHEN** un amministratore cambia il modello del profilo Pittini
- **THEN** l'operazione in corso prosegue con il modello con cui è iniziata e le operazioni successive usano il nuovo

### Requirement: Nuovo portale senza sviluppo
Aggiungere o cambiare un portale SHALL richiedere solo la modifica del suo profilo, senza modificare codice né trasportare oggetti di sviluppo.

#### Scenario: Secondo cliente
- **WHEN** un amministratore crea il profilo di un nuovo cliente
- **THEN** i consulenti autorizzati possono dare istruzioni su quel portale

### Requirement: Uso del profilo da parte dell'agente
Durante un'operazione l'agente SHALL seguire le istruzioni di navigazione del profilo e SHALL tradurre i valori con le sue corrispondenze.

#### Scenario: Priorità tradotta
- **GIVEN** nel profilo "priorità alta" corrisponde al valore "P2" del portale
- **WHEN** il consulente chiede di impostare la priorità alta
- **THEN** il piano proposto e l'esecuzione impostano "P2"

#### Scenario: Valore senza corrispondenza
- **WHEN** il consulente chiede un valore che non ha corrispondenza nel profilo né compare tra le scelte del portale
- **THEN** l'agente lo segnala nel piano invece di scegliere un valore a caso

### Requirement: Profilo senza credenziali
Il profilo MUST NOT contenere password o altri segreti di accesso al portale.

#### Scenario: Salvataggio di un profilo
- **WHEN** un amministratore salva un profilo
- **THEN** il profilo contiene al più il riferimento al tipo di login, mai la password

### Requirement: Gestione riservata dei profili
Solo gli utenti con accesso a TuneCraft Run SHALL poter creare e modificare i profili; ogni modifica SHALL essere tracciata con autore e data nello storico delle revisioni di TuneCraft.

#### Scenario: Consulente senza permesso
- **WHEN** un consulente senza accesso a TuneCraft Run prova a modificare un profilo
- **THEN** la modifica è rifiutata

#### Scenario: Modifica tracciata
- **WHEN** un utente con accesso a TuneCraft Run salva una modifica a un profilo
- **THEN** lo storico delle revisioni indica chi l'ha fatta e quando
