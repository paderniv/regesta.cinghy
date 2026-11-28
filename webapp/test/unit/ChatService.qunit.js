sap.ui.define([
  "regesta/cinghy/ChatService",
  "regesta/cinghy/ChatPanel",
  "regesta/cinghy/test/SimulatedAms"
], function (ChatService, ChatPanel, SimulatedAms) {
  "use strict";

  // Segue l'operazione senza attese e restituisce gli stati visti, l'ultimo è quello finale.
  function followAll(sOpId, fnOnStatus) {
    return new Promise(function (resolve) {
      const aSeen = [];
      ChatService.follow(sOpId, function (oStatus) {
        aSeen.push(oStatus);
        if (fnOnStatus) {
          fnOnStatus(oStatus);
        }
        if (oStatus.final) {
          resolve(aSeen);
        }
      }, 0);
    });
  }

  QUnit.module("ChatService con backend simulato", {
    beforeEach: function () {
      ChatService.setTransport(SimulatedAms.create());
    }
  });

  QUnit.test("lettura: l'operazione avanza fino al riassunto", async function (assert) {
    const oStart = await ChatService.start("Pittini: leggi il ticket 12345");
    assert.strictEqual(oStart.status, "READING");
    const aSeen = await followAll(oStart.opId);
    const oLast = aSeen[aSeen.length - 1];
    assert.strictEqual(oLast.status, "DONE");
    assert.ok(oLast.result.includes("12345"), "riassunto del ticket");
    assert.ok(aSeen.some((o) => o.progress === "Apro il ticket 12345"), "passo in corso visibile");
  });

  QUnit.test("modifica: piano in attesa, conferma, esecuzione", async function (assert) {
    const oStart = await ChatService.start("Pittini: commenta il ticket 12345");
    let oPlan;
    await new Promise(function (resolve) {
      const fnStop = ChatService.follow(oStart.opId, function (oStatus) {
        if (oStatus.status === "PLAN_WAIT") {
          oPlan = oStatus;
          fnStop();
          resolve();
        }
      }, 0);
    });
    assert.strictEqual(oPlan.plan.steps.length, 2, "piano con i passi");
    assert.strictEqual((await ChatService.decide(oStart.opId, "confirm")).status, "EXECUTING");
    const aSeen = await followAll(oStart.opId);
    assert.strictEqual(aSeen[aSeen.length - 1].status, "DONE");
  });

  QUnit.test("annullare il piano non esegue nulla", async function (assert) {
    const oStart = await ChatService.start("Pittini: chiudi il ticket 12345");
    await new Promise(function (resolve) {
      const fnStop = ChatService.follow(oStart.opId, function (oStatus) {
        if (oStatus.status === "PLAN_WAIT") {
          fnStop();
          resolve();
        }
      }, 0);
    });
    const oCancelled = await ChatService.decide(oStart.opId, "cancel");
    assert.strictEqual(oCancelled.status, "CANCELLED");
    assert.ok(oCancelled.final);
  });

  QUnit.test("login: attesa e ripresa dopo Ho fatto l'accesso", async function (assert) {
    const oStart = await ChatService.start("Pittini: leggi il ticket 12345 #login");
    await new Promise(function (resolve) {
      const fnStop = ChatService.follow(oStart.opId, function (oStatus) {
        if (oStatus.status === "LOGIN_WAIT") {
          fnStop();
          resolve();
        }
      }, 0);
    });
    assert.strictEqual((await ChatService.loginDone(oStart.opId)).status, "READING");
    const aSeen = await followAll(oStart.opId);
    assert.strictEqual(aSeen[aSeen.length - 1].status, "DONE");
  });

  QUnit.test("interruzione", async function (assert) {
    const oStart = await ChatService.start("Pittini: leggi il ticket 12345");
    const oStopped = await ChatService.stop(oStart.opId);
    assert.strictEqual(oStopped.status, "CANCELLED");
  });

  QUnit.test("risposte di RST come 4xx con messaggio; guasti senza status", async function (assert) {
    await ChatService.start("Pittini #offline").then(() => assert.ok(false), (e) => assert.strictEqual(e.status, 409));
    await ChatService.start("leggi il ticket 1").then(() => assert.ok(false), (e) => {
      assert.strictEqual(e.status, 422);
      assert.ok(e.message.includes("PITTINI"), "elenca i portali");
    });
    await ChatService.start("Pittini #errore").then(() => assert.ok(false), (e) => assert.notOk(e.status >= 400));
  });

  QUnit.test("operazione sparita: follow la chiude con un errore", async function (assert) {
    const aSeen = await followAll("F".repeat(32));
    assert.strictEqual(aSeen.length, 1);
    assert.strictEqual(aSeen[0].status, "ERROR");
    assert.ok(aSeen[0].final);
  });

  QUnit.test("codice di associazione del runner", async function (assert) {
    const oCode = await ChatService.pairingCode();
    assert.strictEqual(oCode.code.length, 8);
    assert.strictEqual(oCode.validMinutes, 10);
  });

  QUnit.module("ChatService verso RST");

  QUnit.test("percorsi, header CSRF, messaggio d'errore e risposta non JSON", async function (assert) {
    const fnFetch = window.fetch;
    const aCalls = [];
    window.fetch = function (sUrl, oInit) {
      aCalls.push({ url: sUrl, init: oInit });
      if (sUrl.includes("/stop")) {
        return Promise.resolve(new Response(JSON.stringify({ error: "Operazione non trovata" }), { status: 404 }));
      }
      if (sUrl.includes("/login-done")) {
        return Promise.resolve(new Response("<html>login</html>", { status: 200 }));
      }
      return Promise.resolve(new Response(JSON.stringify({ opId: "X", status: "READING" }), { status: 200 }));
    };
    ChatService.setTransport(ChatService.http);
    try {
      await ChatService.start("Pittini: leggi il ticket 1");
      await ChatService.status("ABC");
      await ChatService.stop("ABC").then(() => assert.ok(false), (e) => {
        assert.strictEqual(e.status, 404);
        assert.strictEqual(e.message, "Operazione non trovata", "testo di RST");
      });
      await ChatService.loginDone("ABC").then(() => assert.ok(false), (e) => assert.strictEqual(e.status, 0, "sessione scaduta: guasto"));
    } finally {
      window.fetch = fnFetch;
    }
    assert.ok(aCalls[0].url.startsWith("/sap/bc/reg/cinghy_ams/operations"), aCalls[0].url);
    assert.strictEqual(aCalls[0].init.method, "POST");
    assert.strictEqual(aCalls[0].init.headers["X-Requested-With"], "XMLHttpRequest", "POST con header CSRF");
    assert.deepEqual(JSON.parse(aCalls[0].init.body), { instruction: "Pittini: leggi il ticket 1" });
    assert.ok(aCalls[1].url.startsWith("/sap/bc/reg/cinghy_ams/operations/ABC"));
    assert.notOk("X-Requested-With" in aCalls[1].init.headers, "GET senza header");
    assert.strictEqual(ChatService.runnerUrl(), location.origin + "/sap/bc/reg/cinghy_ams_rn", "indirizzo del servizio runner");
  });

  QUnit.module("Piano nel pannello");

  QUnit.test("il piano si mostra come testo: nessun HTML dal portale", function (assert) {
    const sHtml = ChatPanel.planHtml({
      steps: [{ number: 1, change: "Commento <b>x</b>", reply_text: "Riga 1\n<script>alert(1)</script>" }],
      notes: "nota & dubbio"
    });
    assert.ok(sHtml.includes("Commento &lt;b&gt;x&lt;/b&gt;"));
    assert.ok(sHtml.includes("Riga 1<br>&lt;script&gt;"));
    assert.ok(sHtml.includes("nota &amp; dubbio"));
    assert.notOk(sHtml.includes("<script>"));
    assert.ok(ChatPanel.planHtml("{\"steps\":[{\"change\":\"da stringa\"}]}").includes("da stringa"), "piano come stringa JSON");
  });
});
