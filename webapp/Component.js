sap.ui.define([
  "sap/ui/core/Component"
], function (Component) {
  "use strict";

  return Component.extend("z.flp.toolbarplugin.Component", {
    metadata: { manifest: "json" },

    init: async function () {
      const oContainer = sap.ushell.Container;
      const oExtension = await oContainer.getServiceAsync("Extension");

      // Icona: font SAP ("sap-icon://...") oppure URI di un'immagine propria
      const sIcon = sap.ui.require.toUrl("z/flp/toolbarplugin/img/mia_icona.svg");

      const oItem = await oExtension.createHeaderItem({
        id: "zMyToolbarButton",
        icon: sIcon,
        tooltip: "La mia applicazione",
        ariaLabel: "La mia applicazione",
        press: this._onPress.bind(this)
      }, {
        position: "end"
      });

      oItem.showForAllApps();
    },

    _onPress: async function () {
      // Opzione A: navigazione intent-based verso la tua app Fiori
      const oNav = await sap.ushell.Container.getServiceAsync("Navigation");
      oNav.navigate({
        target: { semanticObject: "ZMiaApp", action: "display" }
      });

      // Opzione B: aprire un'app esterna
      // window.open("https://mia-app.esempio.it", "_blank");
    }
  });
});
