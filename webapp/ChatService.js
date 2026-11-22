sap.ui.define([], function () {
  "use strict";

  // Risposte simulate finché non esiste il backend ABAP: il backend sostituirà solo send().
  const DELAY_MS = 1200;
  const FORCE_ERROR = "#errore";

  return {
    /**
     * @param {Array<{role: "user"|"assistant", text: string}>} aMessages cronologia completa, l'ultimo è dell'utente
     * @param {{home: boolean, semanticObject?: string, action?: string, title?: string}} oContext app corrente
     * @param {number} [iDelay] ritardo in ms (i test lo azzerano)
     * @returns {Promise<string>} risposta in markdown
     */
    send: function (aMessages, oContext, iDelay) {
      const sQuestion = aMessages[aMessages.length - 1].text;
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (sQuestion.includes(FORCE_ERROR)) {
            reject(new Error("Errore simulato"));
            return;
          }
          const sWhere = oContext.home ? "la **Home** del Launchpad"
            : "l'app **" + (oContext.title || oContext.semanticObject + "-" + oContext.action) + "**";
          resolve([
            "_Risposta simulata: il backend di Cinghy non è ancora collegato._",
            "",
            "Hai scritto: \"" + sQuestion + "\" mentre eri su " + sWhere + ".",
            "",
            "Quando il backend sarà attivo potrò, per esempio:",
            "- spiegarti cosa vedi in questa pagina",
            "- rispondere a domande sui processi SAP",
            "- usare `codice` e [link](https://www.regestaitalia.eu) come questi",
            "",
            "Scrivi `" + FORCE_ERROR + "` in un messaggio per provare la gestione degli errori."
          ].join("\n"));
        }, iDelay === undefined ? DELAY_MS : iDelay);
      });
    }
  };
});
