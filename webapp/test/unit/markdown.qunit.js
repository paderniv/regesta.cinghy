sap.ui.define([
  "regesta/cinghy/markdown",
  "sap/m/FormattedText",
  "sap/ui/test/utils/nextUIUpdate"
], function (markdown, FormattedText, nextUIUpdate) {
  "use strict";

  async function render(sMarkdown) {
    const oText = new FormattedText({ htmlText: markdown.toHtml(sMarkdown) });
    oText.placeAt("qunit-fixture");
    await nextUIUpdate();
    return oText;
  }

  QUnit.module("markdown + FormattedText", {
    afterEach: function () {
      delete window.__cinghyXss;
    }
  });

  QUnit.test("formatta grassetto, elenchi e codice", async function (assert) {
    const oText = await render("**importante**\n\n- uno\n- due\n\n`codice`");
    const oDom = oText.getDomRef();
    assert.strictEqual(oDom.querySelector("strong").textContent, "importante");
    assert.strictEqual(oDom.querySelectorAll("ul > li").length, 2);
    assert.ok(oDom.querySelector("code"));
    oText.destroy();
  });

  QUnit.test("script e gestori di eventi non arrivano al DOM", async function (assert) {
    const oText = await render("Testo <img src=x onerror=\"window.__cinghyXss=1\"> <script>window.__cinghyXss=2</script> **ok**");
    const oDom = oText.getDomRef();
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.notOk(oDom.querySelector("script"), "nessun <script>");
    assert.notOk(oDom.querySelector("[onerror]"), "nessun attributo onerror");
    assert.strictEqual(window.__cinghyXss, undefined, "nessun codice eseguito");
    assert.strictEqual(oDom.querySelector("strong").textContent, "ok", "il resto è mostrato");
    oText.destroy();
  });

  QUnit.test("i link si aprono in una nuova scheda e javascript: non passa", async function (assert) {
    const oText = await render("[sito](https://www.example.com) [male](javascript:alert(1))");
    const aLinks = [...oText.getDomRef().querySelectorAll("a")];
    const oGood = aLinks.find((a) => a.textContent === "sito");
    assert.strictEqual(oGood.getAttribute("target"), "_blank");
    assert.notOk(aLinks.some((a) => /^javascript:/i.test(a.getAttribute("href") || "")), "nessun href javascript:");
    oText.destroy();
  });
});
