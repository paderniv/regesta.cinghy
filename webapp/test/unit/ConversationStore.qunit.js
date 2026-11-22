sap.ui.define(["regesta/cinghy/ConversationStore"], function (ConversationStore) {
  "use strict";

  function memoryStorage() {
    const m = {};
    return { getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); } };
  }
  const brokenStorage = {
    getItem: () => { throw new Error("SecurityError"); },
    setItem: () => { throw new Error("QuotaExceededError"); }
  };

  QUnit.module("ConversationStore");

  QUnit.test("salva e ripristina la conversazione", function (assert) {
    const oStorage = memoryStorage();
    const aMessages = [{ role: "user", text: "Ciao" }, { role: "assistant", text: "**Ciao!**" }];
    ConversationStore.save(aMessages, oStorage);
    assert.deepEqual(ConversationStore.load(oStorage), aMessages);
  });

  QUnit.test("storage vuoto o contenuto non valido: conversazione vuota", function (assert) {
    const oStorage = memoryStorage();
    assert.deepEqual(ConversationStore.load(oStorage), [], "vuoto");
    oStorage.setItem("regesta.cinghy.conversation", "{non json");
    assert.deepEqual(ConversationStore.load(oStorage), [], "JSON rotto");
    oStorage.setItem("regesta.cinghy.conversation", JSON.stringify([{ role: "user", text: "ok" }, { role: "hacker", text: "x" }, { role: "user" }]));
    assert.deepEqual(ConversationStore.load(oStorage), [{ role: "user", text: "ok" }], "scarta gli elementi non validi");
  });

  QUnit.test("storage bloccato: nessuna eccezione, conversazione vuota", function (assert) {
    assert.deepEqual(ConversationStore.load(brokenStorage), []);
    ConversationStore.save([{ role: "user", text: "x" }], brokenStorage);
    assert.ok(true, "save non lancia");
  });
});
