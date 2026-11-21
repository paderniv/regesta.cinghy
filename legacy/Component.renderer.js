// Variante per release con UI5 < 1.120 (API Renderer)
sap.ui.define(["sap/ui/core/Component"], function (Component) {
  "use strict";

  return Component.extend("z.flp.toolbarplugin.Component", {
    metadata: { manifest: "json" },

    init: function () {
      sap.ushell.Container.getRenderer("fiori2")
        .addHeaderEndItem({
          id: "zMyToolbarButton",
          icon: "sap-icon://da-2",
          tooltip: "La mia applicazione",
          press: function () {
            sap.ushell.Container.getService("CrossApplicationNavigation")
              .toExternal({ target: { semanticObject: "ZMiaApp", action: "display" } });
          }
        }, true, false);
    }
  });
});
