sap.ui.define([], function () {
  "use strict";

  const KEY = "regesta.cinghy.conversation";

  function isMessage(o) {
    return o && (o.role === "user" || o.role === "assistant") && typeof o.text === "string";
  }

  // La conversazione vive in sessionStorage: sopravvive a F5, sparisce chiudendo la scheda.
  // Se il browser blocca lo storage, il pannello funziona senza conservazione.
  return {
    load: function (oStorage) {
      try {
        const aMessages = JSON.parse((oStorage || window.sessionStorage).getItem(KEY));
        return Array.isArray(aMessages) ? aMessages.filter(isMessage) : [];
      } catch (e) {
        return [];
      }
    },

    save: function (aMessages, oStorage) {
      try {
        (oStorage || window.sessionStorage).setItem(KEY, JSON.stringify(aMessages.filter(isMessage)));
      } catch (e) {
        // storage non disponibile o pieno: si continua senza conservazione
      }
    }
  };
});
