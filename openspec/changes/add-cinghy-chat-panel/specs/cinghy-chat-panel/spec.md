# Spec Delta

## Purpose

Il pannello chat di Cinghy, l'assistente AI personale degli utenti S/4HANA: si apre dalla shell bar del Launchpad sopra l'app corrente e permette di conversare con l'assistente tenendo conto del contesto dell'app.

## ADDED Requirements

### Requirement: Pulsante Cinghy sempre disponibile
Il Launchpad SHALL mostrare il pulsante Cinghy nella shell bar sia sulla Home sia dentro ogni app, per gli utenti che hanno il plugin nel ruolo.

#### Scenario: Pulsante sulla Home
- **WHEN** l'utente apre la Home del Launchpad
- **THEN** il pulsante Cinghy è visibile nella shell bar

#### Scenario: Pulsante dentro un'app
- **WHEN** l'utente apre un'app qualsiasi dal Launchpad
- **THEN** il pulsante Cinghy è visibile nella shell bar

### Requirement: Apertura e chiusura del pannello
Il click sul pulsante Cinghy SHALL aprire il pannello se è chiuso e chiuderlo se è aperto. Il pannello SHALL chiudersi anche con il pulsante di chiusura nel suo header e con il tasto Esc. Il click sul pulsante MUST NOT provocare navigazione.

#### Scenario: Apertura
- **GIVEN** il pannello è chiuso
- **WHEN** l'utente clicca il pulsante Cinghy
- **THEN** il pannello si apre, l'URL resta invariato e il focus va al campo di input

#### Scenario: Chiusura con Esc
- **GIVEN** il pannello è aperto e il focus è dentro il pannello
- **WHEN** l'utente preme Esc
- **THEN** il pannello si chiude e il focus torna al pulsante Cinghy

#### Scenario: Chiusura con il pulsante del pannello
- **GIVEN** il pannello è aperto
- **WHEN** l'utente clicca la "x" nell'header del pannello
- **THEN** il pannello si chiude

### Requirement: Pannello sopra l'app corrente
Il pannello SHALL occupare una colonna fissa sul lato destro, sotto la shell bar e per tutta l'altezza restante, sovrapposta all'app senza ridimensionarla. La parte dell'app non coperta MUST restare utilizzabile mentre il pannello è aperto.

#### Scenario: App utilizzabile con pannello aperto
- **GIVEN** il pannello è aperto sopra un'app
- **WHEN** l'utente clicca un elemento dell'app nella parte non coperta
- **THEN** l'app reagisce normalmente e il pannello resta aperto

#### Scenario: Schermo stretto
- **WHEN** la finestra è più stretta della larghezza del pannello
- **THEN** il pannello occupa tutta la larghezza disponibile senza scroll orizzontale

### Requirement: Stato stabile durante la navigazione
Lo stato del pannello, aperto o chiuso, e la conversazione SHALL restare invariati quando l'utente naviga tra le app o torna alla Home.

#### Scenario: Navigazione con pannello aperto
- **GIVEN** il pannello è aperto con una conversazione in corso
- **WHEN** l'utente naviga verso un'altra app
- **THEN** il pannello resta aperto e mostra la stessa conversazione

### Requirement: Invio di un messaggio
L'utente SHALL poter inviare un messaggio con il pulsante di invio o con il tasto Invio. Il messaggio inviato SHALL comparire subito nella conversazione come bolla allineata a destra. Un messaggio vuoto o composto solo da spazi MUST NOT essere inviato.

#### Scenario: Invio con Invio
- **WHEN** l'utente scrive "Ciao" e preme Invio
- **THEN** compare una bolla a destra con "Ciao" e il campo di input si svuota

#### Scenario: Messaggio vuoto
- **WHEN** l'utente preme Invio con il campo vuoto o con soli spazi
- **THEN** non viene aggiunto nessun messaggio

### Requirement: Risposta di Cinghy
Dopo ogni messaggio dell'utente il pannello SHALL mostrare un indicatore "Cinghy sta scrivendo" fino all'arrivo della risposta, che SHALL comparire come bolla allineata a sinistra. Durante l'attesa l'invio di un nuovo messaggio MUST essere disabilitato. La conversazione SHALL scorrere fino all'ultimo messaggio.

#### Scenario: Attesa e risposta
- **WHEN** l'utente invia un messaggio
- **THEN** compare l'indicatore di attesa, l'invio è disabilitato, e all'arrivo della risposta l'indicatore sparisce, la risposta compare a sinistra e la vista scorre fino a essa

### Requirement: Risposte simulate nell'MVP
Finché il backend non è disponibile, le risposte di Cinghy SHALL essere generate localmente dopo un breve ritardo e SHALL dichiarare di essere simulate.

#### Scenario: Risposta simulata
- **WHEN** l'utente invia un messaggio
- **THEN** dopo un breve ritardo compare una risposta che indica di essere simulata e che contiene esempi di formattazione markdown

### Requirement: Errore nella risposta
Se la risposta non arriva o fallisce, il pannello SHALL mostrare al posto della risposta un messaggio di errore comprensibile con un'azione "Riprova" che reinvia lo stesso messaggio.

#### Scenario: Riprova dopo errore
- **GIVEN** l'ultima risposta è fallita e il pannello mostra l'errore
- **WHEN** l'utente clicca "Riprova"
- **THEN** il messaggio viene reinviato e il messaggio di errore viene sostituito dall'indicatore di attesa

### Requirement: Formattazione sicura delle risposte
Le risposte di Cinghy SHALL essere mostrate con la formattazione markdown (paragrafi, grassetto, corsivo, elenchi, codice, link). Il contenuto MUST essere filtrato in modo che script, gestori di eventi e altro HTML attivo non vengano mai eseguiti. I link SHALL aprirsi in una nuova scheda. I messaggi dell'utente SHALL essere mostrati come testo semplice.

#### Scenario: Markdown nella risposta
- **WHEN** arriva una risposta con `**importante**` e un elenco puntato
- **THEN** "importante" è in grassetto e l'elenco è mostrato come elenco

#### Scenario: HTML pericoloso nella risposta
- **WHEN** arriva una risposta che contiene `<img src=x onerror=alert(1)>` o `<script>`
- **THEN** nessuno script viene eseguito e il resto della risposta è mostrato normalmente

### Requirement: Contesto dell'app corrente
Il pannello SHALL mostrare, vicino al campo di input, l'app in cui si trova l'utente (titolo, oppure "Home") e SHALL aggiornarla a ogni navigazione. Ogni messaggio inviato SHALL portare con sé il contesto: intent dell'app (oggetto semantico e azione) e titolo, oppure l'indicazione Home.

#### Scenario: Cambio di app
- **GIVEN** il pannello è aperto e mostra il contesto dell'app A
- **WHEN** l'utente naviga all'app B
- **THEN** il pannello mostra il contesto dell'app B, e il messaggio successivo porta il contesto di B

### Requirement: Conversazione conservata nella sessione del browser
La conversazione SHALL sopravvivere al ricaricamento della pagina nella stessa scheda e SHALL sparire alla chiusura della scheda. Se il browser non permette di salvarla, il pannello MUST funzionare lo stesso, senza conservazione.

#### Scenario: Ricaricamento della pagina
- **GIVEN** una conversazione con alcuni messaggi
- **WHEN** l'utente ricarica la pagina e riapre il pannello
- **THEN** il pannello mostra la stessa conversazione

#### Scenario: Salvataggio non disponibile
- **WHEN** il salvataggio nella sessione del browser non è permesso
- **THEN** il pannello funziona normalmente e la conversazione si perde solo al ricaricamento

### Requirement: Aspetto coerente con il tema Fiori
Il pannello SHALL usare i colori, i caratteri e gli spazi del tema Fiori attivo, e SHALL adattarsi quando l'utente cambia tema, inclusi i temi scuri e ad alto contrasto, senza ricaricare la pagina.

#### Scenario: Tema scuro
- **WHEN** l'utente attiva il tema Horizon scuro
- **THEN** il pannello e le bolle usano i colori del tema scuro con testo leggibile

### Requirement: Accessibilità
Il pannello SHALL essere utilizzabile solo da tastiera, SHALL esporre ruolo e nome accessibile del pannello e della lista dei messaggi, e SHALL annunciare ai lettori di schermo l'arrivo di una nuova risposta.

#### Scenario: Uso da tastiera
- **WHEN** l'utente apre il pannello, scrive e invia un messaggio e lo chiude usando solo la tastiera
- **THEN** tutte le azioni sono raggiungibili con Tab e attivabili con Invio, Spazio o Esc

#### Scenario: Annuncio della risposta
- **WHEN** arriva una risposta di Cinghy
- **THEN** un lettore di schermo annuncia la nuova risposta
