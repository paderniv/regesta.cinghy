# Proposal

## Why

Lo scheletro del plugin usa ancora nomi segnaposto (`z.flp.toolbarplugin`) ed è pensato per S/4HANA 2023 con UI5 1.120. Prima del primo deploy serve il namespace definitivo del progetto Cinghy, coerente con il BSP `/REG/CINGHY`, e l'allineamento al sistema target reale, che ha UI5 1.136.

## What Changes

- **BREAKING** ID del componente UI5 da `z.flp.toolbarplugin` a `regesta.cinghy` (manifest `sap.app.id`, nome classe `regesta.cinghy.Component`, percorso risorse `regesta/cinghy/...`).
- **BREAKING** `minUI5Version` da `1.71.0` a `1.136.0`: il plugin dichiara la versione UI5 del sistema target.
- Rimossa la variante `legacy/` (API Renderer per UI5 < 1.120): non serve su un sistema 1.136.
- README: BSP `/REG/CINGHY`, target mapping del plugin `Shell-plugin` con ID componente `regesta.cinghy`, sistema target con UI5 1.136, nessun riferimento alla variante legacy.

Fuori scope:

- Il comportamento del click (oggi navigazione segnaposto a `ZMiaApp-display`): Cinghy sarà una chat in un pannello sopra l'app corrente, gestita in una change successiva che sostituirà il handler. Nessun intent `RegestaCinghy-display` serve.
- Le altre correzioni emerse dall'audit (visibilità su Home, gestione errori) e la configurazione di build/deploy (`ui5.yaml`).

## Capabilities

### New Capabilities

Nessuna.

### Modified Capabilities

Nessuna. È un rename di identificativi e configurazione: il comportamento del plugin (pulsante nella shell bar che apre un'app via intent) non cambia. La change imposta `skip_specs: true`.

## Impact

- Codice: `webapp/manifest.json`, `webapp/Component.js`, `README.md`; cancellata la cartella `legacy/`.
- Il plugin non è più installabile su sistemi con UI5 < 1.136.
- Sistema SAP: BSP `/REG/CINGHY`; target mapping `Shell-plugin` da creare con ID `regesta.cinghy` (un eventuale target mapping con il vecchio ID `z.flp.toolbarplugin` non funziona più). L'oggetto semantico `RegestaCinghy` già creato non è usato da questa change.
