sap.ui.define(["regesta/cinghy/ConversationStore"], function (ConversationStore) {
  "use strict";

  function memoryStorage() {
    const m = {};
    return { getItem: (k) => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); }, removeItem: (k) => { delete m[k]; } };
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

  QUnit.test("i messaggi transient (codice del runner) non si conservano", function (assert) {
    const oStorage = memoryStorage();
    ConversationStore.save([{ role: "user", text: "a" }, { role: "assistant", text: "ABCD2345", transient: true }], oStorage);
    assert.deepEqual(ConversationStore.load(oStorage), [{ role: "user", text: "a" }]);
  });

  QUnit.test("id dell'operazione in corso: salva, ripristina, cancella", function (assert) {
    const oStorage = memoryStorage();
    assert.strictEqual(ConversationStore.loadOperation(oStorage), "");
    ConversationStore.saveOperation("ABC", oStorage);
    assert.strictEqual(ConversationStore.loadOperation(oStorage), "ABC");
    ConversationStore.saveOperation("", oStorage);
    assert.strictEqual(ConversationStore.loadOperation(oStorage), "");
    ConversationStore.saveOperation("ABC", brokenStorage);
    assert.strictEqual(ConversationStore.loadOperation(brokenStorage), "", "storage bloccato");
  });
});
