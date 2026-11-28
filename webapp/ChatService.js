sap.ui.define([], function () {
  "use strict";

  // Servizio dell'agente AMS su RST (design 7). Nella sandbox flpInit sostituisce il trasporto
  // con un backend simulato (test/SimulatedAms.js); il resto del modulo non cambia.
  const BASE = "/sap/bc/reg/cinghy_ams";
  const POLL_MS = 2000;

  function url(sPath) {
    const sClient = new URLSearchParams(window.location.search).get("sap-client");
    return BASE + sPath + (sClient ? "?sap-client=" + encodeURIComponent(sClient) : "");
  }

  async function request(sMethod, sPath, oBody) {
    const oHeaders = { Accept: "application/json" };
    if (sMethod !== "GET") {
      oHeaders["Content-Type"] = "application/json";
      oHeaders["X-Requested-With"] = "XMLHttpRequest"; // RST rifiuta le POST senza (CSRF)
    }
    const oResponse = await fetch(url(sPath), {
      method: sMethod,
      credentials: "same-origin",
      headers: oHeaders,
      body: oBody ? JSON.stringify(oBody) : undefined
    });
    let oJson;
    try {
      oJson = await oResponse.json();
    } catch (e) {
      // per esempio la pagina di login dopo una sessione scaduta
      throw Object.assign(new Error("Risposta inattesa da RST (" + oResponse.status + ")"), { status: 0 });
    }
    if (!oResponse.ok) {
      throw Object.assign(new Error(oJson.error || "Errore " + oResponse.status), { status: oResponse.status });
    }
    return oJson;
  }

  const oHttp = { request: request, url: url };
  let oTransport = oHttp;

  /**
   * Errori con status 4xx: RST ha risposto con un messaggio per il consulente (runner spento,
   * portale non configurato, non autorizzato). Gli altri sono guasti: rete, sessione, server.
   */
  return {
    POLL_MS: POLL_MS,

    /** Trasporto verso RST, il predefinito. */
    http: oHttp,

    /** @param {{request: function, url: function}} oNewTransport */
    setTransport: function (oNewTransport) {
      oTransport = oNewTransport;
    },

    start: function (sInstruction) {
      return oTransport.request("POST", "/operations", { instruction: sInstruction });
    },

    status: function (sOpId) {
      return oTransport.request("GET", "/operations/" + sOpId);
    },

    /** @param {"confirm"|"cancel"|"modify"} sDecision */
    decide: function (sOpId, sDecision, sNote) {
      return oTransport.request("POST", "/operations/" + sOpId + "/decision", { decision: sDecision, note: sNote || "" });
    },

    stop: function (sOpId) {
      return oTransport.request("POST", "/operations/" + sOpId + "/stop");
    },

    loginDone: function (sOpId) {
      return oTransport.request("POST", "/operations/" + sOpId + "/login-done");
    },

    pairingCode: function () {
      return oTransport.request("POST", "/runners/pairing-code");
    },

    // Indirizzo del servizio per il runner, da dare al consulente con il codice di associazione.
    runnerUrl: function () {
      return window.location.origin + url("").replace(BASE, BASE + "_rn");
    },

    screenshotUrl: function (sOpId) {
      return oTransport.url("/operations/" + sOpId + "/screenshot");
    },

    /**
     * Segue l'operazione finché non è finita: chiama fnUpdate a ogni stato letto.
     * Un 4xx (operazione sparita o non più autorizzata) la chiude con un errore; un guasto
     * di rete si ritenta al giro successivo.
     * @returns {function} ferma il polling
     */
    follow: function (sOpId, fnUpdate, iInterval) {
      let bStopped = false;
      const fnTick = async () => {
        let oStatus;
        try {
          oStatus = await this.status(sOpId);
        } catch (oError) {
          if (oError.status >= 400 && oError.status < 500) {
            oStatus = { opId: sOpId, status: "ERROR", final: true, progress: oError.message };
          }
        }
        if (bStopped) {
          return;
        }
        if (oStatus) {
          fnUpdate(oStatus);
        }
        if (!oStatus || !oStatus.final) {
          setTimeout(fnTick, iInterval === undefined ? POLL_MS : iInterval);
        }
      };
      fnTick();
      return function () {
        bStopped = true;
      };
    }
  };
});
