sap.ui.define([
  "sap/m/VBox",
  "sap/m/HBox",
  "sap/m/FlexItemData",
  "sap/m/Toolbar",
  "sap/m/ToolbarSpacer",
  "sap/m/Title",
  "sap/m/Avatar",
  "sap/m/Button",
  "sap/m/ScrollContainer",
  "sap/m/List",
  "sap/m/CustomListItem",
  "sap/m/Text",
  "sap/m/FormattedText",
  "sap/m/BusyIndicator",
  "sap/ui/core/Icon",
  "sap/ui/core/InvisibleMessage",
  "sap/ui/core/library",
  "@ui5/webcomponents-ai/dist/PromptInput",
  "./ChatService",
  "./ConversationStore",
  "./markdown"
], function (VBox, HBox, FlexItemData, Toolbar, ToolbarSpacer, Title, Avatar, Button, ScrollContainer, List,
  CustomListItem, Text, FormattedText, BusyIndicator, Icon, InvisibleMessage, coreLibrary, PromptInput,
  ChatService, ConversationStore, markdown) {
  "use strict";

  const InvisibleMessageMode = coreLibrary.InvisibleMessageMode;
  const SHELL_HEADER_ID = "shell-header";
  const FALLBACK_TOP_PX = 52;
  const AVATAR = "regesta/cinghy/img/01_pronto_sorridente.webp";
  const AVATAR_THINKING = "regesta/cinghy/img/02_elaborazione_pensieroso.webp";
  const WELCOME = "Ciao! Sono **Cinghy**, il tuo assistente. Come posso aiutarti?";

  /**
   * Pannello chat fisso a destra, montato in un contenitore proprio sotto <body>:
   * vive per tutta la sessione del Launchpad, fuori dal contenitore delle app.
   */
  class ChatPanel {
    /**
     * @param {string} sButtonId id del pulsante nella shell bar, per riportarci il focus
     */
    constructor(sButtonId) {
      this._sButtonId = sButtonId;
      this._aMessages = ConversationStore.load();
      this._bBusy = false;
      this._bError = false;
      this._oContext = { home: true };
      this._create();
      this._render();
    }

    isOpen() {
      return !this._oDiv.hidden;
    }

    toggle() {
      if (this.isOpen()) {
        this.close(false);
      } else {
        this.open();
      }
    }

    open() {
      this._oDiv.style.top = this._getShellBottom() + "px";
      this._oDiv.hidden = false;
      this._scrollToEnd();
      setTimeout(() => this._oInput.focus(), 0);
    }

    close(bFocusButton) {
      this._oDiv.hidden = true;
      if (bFocusButton) {
        const oButton = document.getElementById(this._sButtonId);
        if (oButton) {
          oButton.focus();
        }
      }
    }

    setContext(oContext) {
      this._oContext = oContext;
      this._oContextText.setText(oContext.home ? "Home"
        : oContext.title || oContext.semanticObject + "-" + oContext.action);
    }

    // Unica lettura del DOM della shell (sola lettura): l'altezza della shell bar.
    _getShellBottom() {
      const oHeader = document.getElementById(SHELL_HEADER_ID);
      return oHeader ? Math.round(oHeader.getBoundingClientRect().bottom) : FALLBACK_TOP_PX;
    }

    _create() {
      this._oDiv = document.createElement("div");
      this._oDiv.id = "regestaCinghyPanel";
      this._oDiv.className = "cinghyPanel";
      this._oDiv.hidden = true;
      this._oDiv.setAttribute("role", "complementary");
      this._oDiv.setAttribute("aria-label", "Cinghy, assistente AI");
      this._oDiv.addEventListener("keydown", (oEvent) => {
        if (oEvent.key === "Escape") {
          oEvent.stopPropagation();
          this.close(true);
        }
      });
      document.body.appendChild(this._oDiv);

      const oTitle = new Title({ text: "Cinghy", level: "H2" });
      const oHeader = new Toolbar({
        content: [
          this._createAvatar(),
          oTitle,
          new ToolbarSpacer(),
          new Button({
            icon: "sap-icon://decline",
            type: "Transparent",
            tooltip: "Chiudi Cinghy",
            press: () => this.close(true)
          })
        ]
      }).addStyleClass("cinghyHeader");

      this._oList = new List({
        showNoData: false,
        showSeparators: "None",
        ariaLabelledBy: [oTitle]
      }).addStyleClass("cinghyList");
      this._oList.addEventDelegate({ onAfterRendering: () => this._scrollToEnd() });

      this._oScroll = new ScrollContainer({
        vertical: true,
        horizontal: false,
        height: "100%",
        content: [this._oList],
        layoutData: new FlexItemData({ growFactor: 1, minHeight: "0" })
      }).addStyleClass("cinghyScroll");

      this._oInput = new PromptInput({
        placeholder: "Scrivi a Cinghy...",
        submit: () => this._onSubmit()
      }).addStyleClass("cinghyInput");

      this._oContextText = new Text({ text: "Home", wrapping: false });
      const oContext = new HBox({
        alignItems: "Center",
        items: [
          new Icon({ src: "sap-icon://locate-me", decorative: true }).addStyleClass("cinghyContextIcon"),
          new Text({ text: "Contesto:", wrapping: false }).addStyleClass("cinghyContextLabel"),
          this._oContextText
        ]
      }).addStyleClass("cinghyContext");

      new VBox({
        fitContainer: true,
        items: [
          oHeader,
          this._oScroll,
          new VBox({ items: [this._oInput, oContext] }).addStyleClass("cinghyFooter")
        ]
      }).addStyleClass("cinghyRoot").placeAt(this._oDiv);
    }

    _createAvatar(bThinking) {
      return new Avatar({
        src: sap.ui.require.toUrl(bThinking ? AVATAR_THINKING : AVATAR),
        displaySize: "XS",
        decorative: true
      }).addStyleClass("cinghyAvatar");
    }

    _createItem(oMessage) {
      const bUser = oMessage.role === "user";
      const oContent = bUser
        ? new Text({ text: oMessage.text, renderWhitespace: true })
        : new FormattedText({ htmlText: markdown.toHtml(oMessage.text) });
      return this._wrap(bUser ? "user" : "bot", [oContent]);
    }

    _wrap(sKind, aBubbleContent) {
      // etichetta solo per i lettori di schermo: chi ha scritto il messaggio
      const oSpeaker = new Text({ text: sKind === "user" ? "Tu:" : "Cinghy:" }).addStyleClass("cinghySrOnly");
      const oBubble = new VBox({ items: [oSpeaker].concat(aBubbleContent) }).addStyleClass("cinghyBubble");
      const aItems = sKind === "user" ? [oBubble] : [this._createAvatar(sKind === "typing"), oBubble];
      return new CustomListItem({
        type: "Inactive",
        content: [new HBox({ items: aItems }).addStyleClass("cinghyMsg cinghyMsg--" + sKind)]
      }).addStyleClass("cinghyItem");
    }

    _render() {
      this._oList.destroyItems();
      this._oList.addItem(this._wrap("bot", [new FormattedText({ htmlText: markdown.toHtml(WELCOME) })]));
      this._aMessages.forEach((oMessage) => this._oList.addItem(this._createItem(oMessage)));
      if (this._bBusy) {
        this._oList.addItem(this._wrap("typing", [new HBox({
          alignItems: "Center",
          items: [
            new BusyIndicator({ size: "0.5rem" }),
            new Text({ text: "Cinghy sta scrivendo" })
          ]
        })]));
      }
      if (this._bError) {
        this._oList.addItem(this._wrap("error", [
          new Text({ text: "Non sono riuscito a rispondere. Riprova tra poco." }),
          new Button({
            text: "Riprova",
            icon: "sap-icon://refresh",
            type: "Transparent",
            press: () => this._send()
          }).addStyleClass("cinghyRetry")
        ]));
      }
    }

    _scrollToEnd() {
      const oDom = this._oScroll.getDomRef();
      if (oDom) {
        oDom.scrollTop = oDom.scrollHeight;
      }
    }

    _onSubmit() {
      const sText = this._oInput.getValue().trim();
      if (this._bBusy || !sText) {
        return;
      }
      this._oInput.setValue("");
      this._aMessages.push({ role: "user", text: sText });
      this._send();
    }

    _send() {
      this._bBusy = true;
      this._bError = false;
      this._oInput.setEnabled(false);
      ConversationStore.save(this._aMessages);
      this._render();

      ChatService.send(this._aMessages.slice(), this._oContext).then((sAnswer) => {
        this._aMessages.push({ role: "assistant", text: sAnswer });
        InvisibleMessage.getInstance().announce("Risposta di Cinghy: " + markdown.toText(sAnswer),InvisibleMessageMode.Polite);
      }, () => {
        this._bError = true;
        InvisibleMessage.getInstance().announce("Cinghy non è riuscito a rispondere", InvisibleMessageMode.Assertive);
      }).finally(() => {
        this._bBusy = false;
        this._oInput.setEnabled(true);
        ConversationStore.save(this._aMessages);
        this._render();
        if (this.isOpen()) {
          setTimeout(() => this._oInput.focus(), 0);
        }
      });
    }
  }

  return ChatPanel;
});
