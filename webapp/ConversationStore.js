sap.ui.define([], function () {
  "use strict";

  const KEY = "regesta.cinghy.conversation";
  const KEY_OP = "regesta.cinghy.operation";

  function isMessage(o) {
    return o && (o.role === "user" || o.role === "assistant") && typeof o.text === "string";
  }

  function storage(oStorage) {
    return oStorage || window.sessionStorage;
  }

  // La conversazione vive in sessionStorage: sopravvive a F5, sparisce chiudendo la scheda.
  // Se il browser blocca lo storage, il pannello funziona senza conservazione.
  return {
    load: function (oStorage) {
      try {
        const aMessages = JSON.parse(storage(oStorage).getItem(KEY));
        return Array.isArray(aMessages) ? aMessages.filter(isMessage) : [];
      } catch (e) {
        return [];
      }
    },

    save: function (aMessages, oStorage) {
      try {
        // i messaggi "transient" (codice di associazione del runner) non si conservano
        storage(oStorage).setItem(KEY, JSON.stringify(aMessages.filter((o) => isMessage(o) && !o.transient)));
      } catch (e) {
        // storage non disponibile o pieno: si continua senza conservazione
      }
    },

    // Id dell'operazione AMS in corso: riaprendo la pagina il pannello riprende a seguirla.
    loadOperation: function (oStorage) {
      try {
        return storage(oStorage).getItem(KEY_OP) || "";
      } catch (e) {
        return "";
      }
    },

    saveOperation: function (sOpId, oStorage) {
      try {
        if (sOpId) {
          storage(oStorage).setItem(KEY_OP, sOpId);
        } else {
          storage(oStorage).removeItem(KEY_OP);
        }
      } catch (e) {
        // storage non disponibile: l'operazione continua su RST, il pannello non la ritrova dopo F5
      }
    }
  };
});
