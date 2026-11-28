# Runner dell'agente AMS

Il runner gira sul PC del consulente. Riceve da RST le azioni decise dall'agente AMS, le esegue in un browser Chrome visibile e rimanda a RST l'esito, la descrizione della pagina e gli screenshot.

Il runner si collega a RST solo in uscita, in HTTPS. Non conosce la password SAP del consulente. Non vede le password dei portali, perché gli accessi li fa il consulente nel browser del runner.

## Cosa serve

- Node.js 22.15 o successivo, controllabile con `node -v`.
- Google Chrome installato.
- L'indirizzo del servizio runner su RST, che dà l'amministratore. Ha questa forma: `https://<host>:<porta>/sap/bc/reg/cinghy_ams_rn?sap-client=100`.
- In Cinghy, un ruolo che permetta di usare l'agente AMS.

## Installazione

```sh
cd runner
npm install
```

## Associazione (solo la prima volta)

1. In Cinghy genera il **codice di associazione** del runner. È di 8 caratteri e vale 10 minuti.
2. Avvia il runner con l'indirizzo di RST:

   macOS / Linux:
   ```sh
   RST_URL="https://<host>:<porta>/sap/bc/reg/cinghy_ams_rn?sap-client=100" npm start
   ```
   Windows (PowerShell):
   ```powershell
   $env:RST_URL="https://<host>:<porta>/sap/bc/reg/cinghy_ams_rn?sap-client=100"; npm start
   ```
3. Il runner chiede il codice. Inseriscilo.

Il runner salva il proprio token in `~/.cinghy-ams-runner/token`, in un file leggibile solo dal tuo utente. Su RST resta solo l'hash del token. Un codice vale una sola volta: per associare un altro PC generane uno nuovo.

## Uso quotidiano

Avvia il runner con lo stesso comando. Si apre un Chrome dedicato, separato dal tuo browser personale. Il suo profilo è in `~/.cinghy-ams-runner/profile` e conserva le sessioni dei portali tra un avvio e l'altro.

- Accedi ai portali clienti in questa finestra, di persona. Puoi farlo anche prima di avviare un'operazione in Cinghy. Per aprire subito la pagina di accesso di un portale, aggiungi il suo indirizzo al comando: `npm start -- https://hdserver.pittini.it/`. Se il portale usa il login Microsoft, puoi aggiungere anche il tuo utente, che compare già compilato: `npm start -- https://hdserver.pittini.it/ nome@dominio.it`. La password la scrivi sempre tu.
- Se l'agente trova la pagina di login, si ferma e Cinghy ti chiede di accedere. Fai l'accesso nella finestra del runner, poi premi "Ho fatto l'accesso" in Cinghy.
- Puoi guardare l'agente lavorare nella finestra. Se un'azione non ti convince, interrompi l'operazione da Cinghy.
- Per spegnere il runner usa `Ctrl+C`. Le operazioni che aspettano azioni si fermano dopo il timeout, e Cinghy indica il runner come non collegato.

Il runner rifiuta da solo gli indirizzi fuori dai domini del profilo del portale. Se un clic porta fuori da quei domini, il runner torna indietro e non legge la pagina.

## Problemi comuni

| Messaggio | Cosa fare |
|---|---|
| `Token del runner sconosciuto o revocato` | Il token è stato revocato da Cinghy o non è più valido. Il runner lo cancella: genera un nuovo codice in Cinghy e riavvia il runner. |
| `Codice di associazione sbagliato, scaduto o gia' usato` | Genera un nuovo codice in Cinghy e riavvia il runner. |
| `RST non raggiungibile ... riprovo` | Rete o VPN assente. Il runner riprova da solo ogni 5–60 secondi. |
| `self-signed certificate` verso RST | RST usa un certificato autofirmato. Salva quel certificato una volta: `echo \| openssl s_client -connect <host>:<porta> -servername <host> 2>/dev/null \| openssl x509 > ~/.cinghy-ams-runner/rst-cert.pem`. Controlla che l'impronta (`openssl x509 -in ~/.cinghy-ams-runner/rst-cert.pem -noout -fingerprint -sha256`) sia quella che vedi in STRUST o nel browser. Il runner carica da solo quel file a ogni avvio. Non usare `NODE_TLS_REJECT_UNAUTHORIZED=0`: espone il token del runner. |
| Altri errori di certificato verso RST | Il certificato di RST è emesso da una CA aziendale. Avvia con `NODE_OPTIONS=--use-system-ca`, che usa i certificati del sistema operativo. |

## Variabili

| Variabile | Default | Uso |
|---|---|---|
| `RST_URL` | nessuno, obbligatoria | Indirizzo del servizio runner su RST |
| `AMS_RUNNER_HOME` | `~/.cinghy-ams-runner` | Cartella di token, profilo del browser e file temporanei |

## Sviluppo

```sh
npm test
```

I test usano un browser finto e un RST simulato in locale: non aprono Chrome e non chiamano RST.
