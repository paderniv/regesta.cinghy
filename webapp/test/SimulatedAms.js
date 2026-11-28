sap.ui.define([], function () {
  "use strict";

  // Backend AMS simulato per sandbox e test: stessi percorsi e stesse risposte del servizio
  // /sap/bc/reg/cinghy_ams su RST. Ogni lettura dello stato fa avanzare l'operazione di un passo.
  //   istruzione con "#errore"  -> guasto (nessuna risposta)
  //   istruzione con "#offline" -> 409 runner non collegato
  //   istruzione senza "Pittini" -> 422 portale non riconosciuto
  //   istruzione con "#login"   -> il portale chiede il login
  //   istruzione con "commenta", "chiudi" o "cambia" -> piano da confermare
  //   altrimenti                -> sola lettura
  const SCREENSHOT = "regesta/cinghy/img/01_pronto_sorridente.png";

  function fail(iStatus, sMessage) {
    return Promise.reject(Object.assign(new Error(sMessage), { status: iStatus }));
  }

  function create() {
    const mOps = {};
    let iNext = 1;

    function view(oOp) {
      return {
        opId: oOp.id, status: oOp.status, phase: oOp.phase, portal: "PITTINI", llm: "SIMULATO",
        final: ["DONE", "CANCELLED", "ERROR"].includes(oOp.status),
        progress: oOp.progress, plan: oOp.plan, result: oOp.result, steps: oOp.steps
      };
    }

    function set(oOp, sStatus, sProgress) {
      oOp.status = sStatus;
      oOp.progress = sProgress;
      oOp.steps++;
    }

    function plan(sNote) {
      return {
        steps: [
          { number: 1, change: "Aggiungo un commento al ticket 12345", reply_text: "Buongiorno,\nil fix è in produzione. <Cordiali> saluti" },
          { number: 2, change: "Porto lo stato a \"7 - Risolta\"" }
        ],
        notes: sNote ? "Modificato su richiesta: " + sNote : undefined
      };
    }

    function advance(oOp) {
      if (oOp.status === "READING") {
        if (oOp.steps < 2) {
          set(oOp, "READING", "Apro il ticket 12345");
        } else if (oOp.wantsLogin) {
          oOp.wantsLogin = false;
          set(oOp, "LOGIN_WAIT", "Il portale chiede l'accesso");
        } else if (oOp.wantsPlan) {
          oOp.plan = plan(oOp.note);
          set(oOp, "PLAN_WAIT", "Piano pronto: attendo la conferma");
        } else {
          oOp.result = "Ticket **12345** _(simulato)_: richiesta di verifica sulla ricerca VIM. Stato 2 - In lavorazione.";
          set(oOp, "DONE", "Operazione completata");
        }
      } else if (oOp.status === "EXECUTING") {
        oOp.result = "Piano eseguito _(simulato)_:\n1. Commento aggiunto: riuscito\n2. Stato 7 - Risolta: riuscito";
        oOp.screenshot = true;
        set(oOp, "DONE", "Operazione completata");
      }
    }

    function own(sId) {
      const oOp = mOps[sId];
      return oOp ? Promise.resolve(oOp) : fail(404, "Operazione non trovata");
    }

    async function request(sMethod, sPath, oBody) {
      const aParts = sPath.split("/").filter(Boolean);
      if (sMethod === "POST" && sPath === "/runners/pairing-code") {
        return { code: "ABCD2345", validMinutes: 10 };
      }
      if (sMethod === "POST" && sPath === "/operations") {
        const sText = oBody.instruction;
        if (sText.includes("#errore")) {
          throw Object.assign(new Error("Errore simulato"), { status: 0 });
        }
        if (sText.includes("#offline")) {
          return fail(409, "Il tuo runner non e' collegato: avvialo sul tuo PC (npm start nella cartella runner).");
        }
        if (!/pittini/i.test(sText)) {
          return fail(422, "Non riconosco il portale del cliente nell'istruzione. Indica uno dei portali disponibili: PITTINI");
        }
        const oOp = {
          id: String(iNext++).padStart(32, "0"), status: "READING", phase: "R", steps: 0,
          progress: "Avvio l'operazione", wantsLogin: sText.includes("#login"),
          wantsPlan: /commenta|chiudi|cambia/i.test(sText)
        };
        mOps[oOp.id] = oOp;
        return view(oOp);
      }
      const oOp = await own(aParts[1]);
      const sAction = sMethod + " " + (aParts[2] || "");
      if (sAction === "GET ") {
        advance(oOp);
      } else if (sAction === "POST stop") {
        if (!view(oOp).final) {
          set(oOp, "CANCELLED", "Operazione interrotta dal consulente");
        }
      } else if (sAction === "POST login-done" && oOp.status === "LOGIN_WAIT") {
        set(oOp, "READING", "Riprendo dopo l'accesso");
      } else if (sAction === "POST decision" && oOp.status === "PLAN_WAIT") {
        if (oBody.decision === "confirm") {
          oOp.phase = "E";
          set(oOp, "EXECUTING", "Eseguo il piano confermato");
        } else if (oBody.decision === "modify") {
          oOp.note = oBody.note;
          oOp.plan = undefined;
          set(oOp, "READING", "Rivedo il piano");
        } else {
          oOp.plan = undefined;
          set(oOp, "CANCELLED", "Piano annullato dal consulente: nessuna modifica eseguita");
        }
      } else {
        return fail(400, "Azione non ammessa nello stato " + oOp.status);
      }
      return view(oOp);
    }

    function url(sPath) {
      const aParts = sPath.split("/").filter(Boolean);
      const oOp = mOps[aParts[1]];
      // senza screenshot l'immagine non esiste, come il 404 di RST
      return sap.ui.require.toUrl(oOp && oOp.screenshot ? SCREENSHOT : "regesta/cinghy/img/nessuno.png");
    }

    return { request: request, url: url };
  }

  return { create: create };
});
