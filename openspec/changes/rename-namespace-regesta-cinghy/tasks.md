# Tasks

## 1. Rename e allineamento a UI5 1.136

- [x] 1.1 In `webapp/manifest.json` impostare `sap.app.id` a `regesta.cinghy` e `minUI5Version` a `1.136.0`; verificare che il JSON sia valido (`python3 -m json.tool webapp/manifest.json`)
- [x] 1.2 In `webapp/Component.js` rinominare la classe in `regesta.cinghy.Component` e il percorso icona in `regesta/cinghy/img/mia_icona.svg`; verificare con `grep -rn "toolbarplugin" webapp` che non restino occorrenze
- [x] 1.3 Cancellare la cartella `legacy/`; verificare con `git status` che risulti rimossa e con `grep -rn "legacy\|Renderer" --exclude-dir=openspec --exclude-dir=.git .` che nessun file la citi più

## 2. Documentazione

- [x] 2.1 Aggiornare `README.md`: UI5 1.136 al posto di "release 2023, UI5 1.120", BSP `/REG/CINGHY` al posto di `ZFLP_TB_PLUGIN`, target mapping `Shell-plugin` con ID componente `regesta.cinghy`, rimossa la riga sulla variante legacy; verificare con `grep -n "toolbarplugin\|ZFLP_TB_PLUGIN\|1.120\|legacy" README.md` che non restino vecchi riferimenti

## 3. Verifica in sistema

- [ ] 3.1 Dopo deploy su `/REG/CINGHY` (sistema UI5 1.136), target mapping `Shell-plugin` con ID `regesta.cinghy` e invalidazione cache: aprire il Launchpad con un utente del ruolo, entrare in un'app e verificare che il pulsante compaia (il comportamento del click resta segnaposto)

## Workflow follow-up

- Eliminare dal sistema l'eventuale target mapping con il vecchio ID `z.flp.toolbarplugin`, se era già stato creato.
- Archiviare la change dopo la verifica in sistema.
