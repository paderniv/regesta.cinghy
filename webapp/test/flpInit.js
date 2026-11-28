sap.ui.define([
  "sap/ushell/Container",
  "regesta/cinghy/ChatService",
  "regesta/cinghy/test/SimulatedAms"
], async function (Container, ChatService, SimulatedAms) {
  "use strict";
  // Nella sandbox non c'è RST: il pannello parla con l'agente AMS simulato.
  ChatService.setTransport(SimulatedAms.create());
  const oRenderer = await Container.createRendererInternal("fiori2");
  oRenderer.placeAt("content");
});
