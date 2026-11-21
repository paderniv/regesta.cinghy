# Plugin Fiori Launchpad – pulsante nella toolbar

Plugin dello shell per S/4HANA on-premise (release 2023, UI5 1.120) che aggiunge un pulsante personalizzato nella barra in alto del Launchpad.

- `webapp/Component.js`: versione con servizio Extension (`createHeaderItem`)
- `legacy/Component.renderer.js`: variante con Renderer per UI5 < 1.120
- `webapp/img/mia_icona.svg`: icona segnaposto da sostituire

## Deploy on-premise
1. Deploy come BSP (es. ZFLP_TB_PLUGIN).
2. Catalogo tecnico in /UI2/FLPD_CUST o Launchpad Content Manager.
3. Target mapping: semantic object `Shell`, azione `plugin`, ID `z.flp.toolbarplugin`.
4. Catalogo nel ruolo PFCG degli utenti.
5. Invalidare le cache (/UI2/INVALIDATE_GLOBAL_CACHES, /UI5/APP_INDEX_CALCULATE).
