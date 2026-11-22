sap.ui.define(["regesta/cinghy/ChatService"], function (ChatService) {
  "use strict";

  QUnit.module("ChatService (simulato)");

  QUnit.test("risponde in markdown dichiarando di essere simulato e citando il contesto", async function (assert) {
    const sAnswer = await ChatService.send([{ role: "user", text: "Ciao" }],
      { home: false, semanticObject: "PurchaseOrder", action: "manage", title: "Ordini" }, 0);
    assert.ok(sAnswer.includes("simulata"), "dichiara la simulazione");
    assert.ok(sAnswer.includes("**Ordini**"), "cita il titolo dell'app");
    assert.ok(sAnswer.includes("Ciao"), "cita il messaggio dell'utente");
  });

  QUnit.test("sulla Home cita la Home", async function (assert) {
    const sAnswer = await ChatService.send([{ role: "user", text: "x" }], { home: true }, 0);
    assert.ok(sAnswer.includes("**Home**"));
  });

  QUnit.test("fallisce quando il messaggio contiene #errore", async function (assert) {
    try {
      await ChatService.send([{ role: "user", text: "prova #errore" }], { home: true }, 0);
      assert.ok(false, "doveva fallire");
    } catch (oError) {
      assert.strictEqual(oError.message, "Errore simulato");
    }
  });
});
