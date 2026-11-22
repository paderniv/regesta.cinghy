sap.ui.define([
  "sap/ui/core/Component",
  "sap/ushell/Container",
  "sap/base/Log"
], function (Component, Container, Log) {
  "use strict";

  const BUTTON_ID = "regestaCinghyButton";

  function logError(oError) {
    Log.error("Cinghy: errore del plugin", oError, "regesta.cinghy");
  }

  return Component.extend("regesta.cinghy.Component", {
    metadata: { manifest: "json" },

    init: function () {
      this._oContext = { home: true };
      // init non deve restituire una Promise: l'avvio asincrono resta interno
      this._createButton().catch(logError);
      this._trackContext().catch(logError);
    },

    _createButton: async function () {
      const oExtension = await Container.getServiceAsync("Extension");
      const oItem = await oExtension.createHeaderItem({
        id: BUTTON_ID,
        icon: sap.ui.require.toUrl("regesta/cinghy/img/03_analisi_dati_occhiali_ar.webp"),
        tooltip: "Cinghy",
        ariaLabel: "Cinghy, assistente AI",
        press: () => this._togglePanel().catch(logError)
      }, {
        position: "end"
      });
      oItem.showForAllApps();
      oItem.showOnHome();
    },

    // Il pannello e i Web Components si caricano solo al primo click.
    _togglePanel: async function () {
      if (!this._pPanel) {
        this._pPanel = new Promise((resolve, reject) => {
          sap.ui.require(["regesta/cinghy/ChatPanel"], (ChatPanel) => {
            const oPanel = new ChatPanel(BUTTON_ID);
            oPanel.setContext(this._oContext);
            resolve(oPanel);
          }, reject);
        });
      }
      (await this._pPanel).toggle();
    },

    _trackContext: async function () {
      const oAppLifeCycle = await Container.getServiceAsync("AppLifeCycle");
      const fnUpdate = async () => {
        this._oContext = await readContext(oAppLifeCycle.getCurrentApplication());
        if (this._pPanel) {
          (await this._pPanel).setContext(this._oContext);
        }
      };
      oAppLifeCycle.attachAppLoaded(() => fnUpdate().catch(logError));
      await fnUpdate();
    }
  });

  async function readContext(oApp) {
    if (!oApp || oApp.homePage) {
      return { home: true };
    }
    const oIntent = (oApp.getIntent && await oApp.getIntent()) || {};
    let sTitle;
    try {
      sTitle = oApp.componentInstance && oApp.componentInstance.getManifestEntry("/sap.app/title");
    } catch (e) {
      // titolo non disponibile: si usa l'intent
    }
    return {
      home: false,
      semanticObject: oIntent.semanticObject,
      action: oIntent.action,
      title: sTitle && !sTitle.startsWith("{{") ? sTitle : undefined
    };
  }
});
