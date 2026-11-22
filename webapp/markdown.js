sap.ui.define(["marked"], function (markedModule) {
  "use strict";

  const oMarked = new markedModule.Marked({
    gfm: true,
    breaks: true,
    renderer: {
      // link sempre in una nuova scheda; rel non serve: FormattedText lo scarta
      // e i browser applicano già noopener ai link con target="_blank"
      link: function (oToken) {
        const sText = this.parser.parseInline(oToken.tokens);
        return "<a href=\"" + oToken.href.replace(/"/g, "&quot;") + "\" target=\"_blank\">" + sText + "</a>";
      }
    }
  });

  /**
   * Markdown -> HTML. Il filtro di sicurezza è quello di sap.m.FormattedText,
   * che riceve questo HTML e scarta tag e attributi non ammessi (script, on*).
   */
  return {
    toHtml: function (sMarkdown) {
      return oMarked.parse(sMarkdown || "", { async: false });
    },

    // testo semplice per i lettori di schermo (DOMParser non esegue script)
    toText: function (sMarkdown) {
      return new DOMParser().parseFromString(this.toHtml(sMarkdown), "text/html").body.textContent.trim();
    }
  };
});
