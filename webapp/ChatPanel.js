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
  "sap/m/Image",
  "sap/m/BusyIndicator",
  "sap/ui/core/Icon",
  "sap/ui/core/InvisibleMessage",
  "sap/ui/core/library",
  "@ui5/webcomponents-ai/dist/PromptInput",
  "./ChatService",
  "./ConversationStore",
  "./markdown"
], function (VBox, HBox, FlexItemData, Toolbar, ToolbarSpacer, Title, Avatar, Button, ScrollContainer, List,
  CustomListItem, Text, FormattedText, Image, BusyIndicator, Icon, InvisibleMessage, coreLibrary, PromptInput,
  ChatService, ConversationStore, markdown) {
  "use strict";

  const InvisibleMessageMode = coreLibrary.InvisibleMessageMode;
  const SHELL_HEADER_ID = "shell-header";
  const FALLBACK_TOP_PX = 52;
  const AVATAR = "regesta/cinghy/img/01_pronto_sorridente.png";
  const AVATAR_THINKING = "regesta/cinghy/img/02_elaborazione_pensieroso.png";
  const WELCOME = "Ciao! Sono **Cinghy**, l'agente AMS. Dimmi su quale portale cliente lavorare e cosa fare, " +
    "per esempio: _Pittini: leggi il ticket 144090 e riassumilo_.";
  const PLACEHOLDER = "Scrivi a Cinghy...";
  const PLACEHOLDER_PLAN = "Scrivi cosa cambiare nel piano...";
  const LOGIN_HTML = "<p>Il portale chiede l'accesso. Accedi nella finestra Chrome del runner, " +
    "poi premi <strong>Ho fatto l'accesso</strong>.</p>";

  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" })[c]);
  }

  // Il piano arriva dal modello e può citare testo del portale: si mostra come testo, mai come HTML.
  function planHtml(vPlan) {
    let oPlan = vPlan;
    if (typeof vPlan === "string") {
      try {
        oPlan = JSON.parse(vPlan);
      } catch (e) {
        oPlan = {};
      }
    }
    const aSteps = (oPlan && oPlan.steps) || [];
    let sHtml = "<p><strong>Piano proposto</strong></p><ol>" + aSteps.map((o) => "<li>" + escapeHtml(o.change || "") +
      (o.reply_text ? "<br><em>Risposta al cliente:</em><br>" + escapeHtml(o.reply_text).replace(/\n/g, "<br>") : "") +
      "</li>").join("") + "</ol>";
    if (oPlan && oPlan.notes) {
      sHtml += "<p><em>Note:</em> " + escapeHtml(oPlan.notes) + "</p>";
    }
    return sHtml + "<p>Conferma per eseguirlo, annullalo, oppure scrivi qui sotto cosa cambiare.</p>";
  }

  /**
   * Pannello chat fisso a destra, montato in un contenitore proprio sotto <body>:
   * vive per tutta la sessione del Launchpad, fuori dal contenitore delle app.
   * Ogni istruzione avvia un'operazione dell'agente AMS su RST, seguita finché non finisce.
   */
  class ChatPanel {
    /**
     * @param {string} sButtonId id del pulsante nella shell bar, per riportarci il focus
     */
    constructor(sButtonId) {
      this._sButtonId = sButtonId;
      this._aMessages = ConversationStore.load();
      this._sOpId = ConversationStore.loadOperation();
      this._oOp = null;
      this._bBusy = false;
      this._bError = false;
      this._oContext = { home: true };
      this._create();
      this._render();
      this._updateLive();
      if (this._sOpId) {
        this._follow(); // operazione avviata prima di ricaricare la pagina
      }
    }

    static planHtml(vPlan) {
      return planHtml(vPlan);
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
            icon: "sap-icon://chain-link",
            type: "Transparent",
            tooltip: "Associa il runner AMS di questo PC",
            press: () => this._pair()
          }),
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

      this._createLive();

      this._oScroll = new ScrollContainer({
        vertical: true,
        horizontal: false,
        height: "100%",
        content: [this._oList, this._oLive],
        layoutData: new FlexItemData({ growFactor: 1, minHeight: "0" })
      }).addStyleClass("cinghyScroll");

      this._oInput = new PromptInput({
        placeholder: PLACEHOLDER,
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

    // Operazione in corso: controlli fissi aggiornati sul posto, così il focus resta sul pulsante.
    _createLive() {
      this._oLiveBusy = new BusyIndicator({ size: "0.5rem" });
      this._oLiveText = new Text();
      this._oLiveDetail = new FormattedText({ visible: false });
      this._oConfirm = new Button({
        text: "Conferma", type: "Emphasized",
        press: () => this._act((sId) => ChatService.decide(sId, "confirm"))
      });
      this._oCancel = new Button({
        text: "Annulla",
        press: () => this._act((sId) => ChatService.decide(sId, "cancel"))
      });
      this._oLoginDone = new Button({
        text: "Ho fatto l'accesso", type: "Emphasized",
        press: () => this._act((sId) => ChatService.loginDone(sId))
      });
      this._oStop = new Button({
        text: "Interrompi", icon: "sap-icon://stop",
        press: () => this._act((sId) => ChatService.stop(sId))
      });
      this._aLiveButtons = [this._oConfirm, this._oCancel, this._oLoginDone, this._oStop];
      this._oLive = new HBox({
        visible: false,
        items: [
          this._createAvatar(true),
          new VBox({
            items: [
              new Text({ text: "Cinghy, operazione in corso:" }).addStyleClass("cinghySrOnly"),
              new HBox({ alignItems: "Center", items: [this._oLiveBusy, this._oLiveText] }).addStyleClass("cinghyLiveStatus"),
              this._oLiveDetail,
              new HBox({ wrap: "Wrap", items: this._aLiveButtons }).addStyleClass("cinghyActions")
            ]
          }).addStyleClass("cinghyBubble")
        ]
      }).addStyleClass("cinghyMsg cinghyMsg--bot cinghyLive");
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
      const aContent = [bUser
        ? new Text({ text: oMessage.text, renderWhitespace: true })
        : new FormattedText({ htmlText: markdown.toHtml(oMessage.text) })];
      if (oMessage.screenshotOp) {
        const sUrl = ChatService.screenshotUrl(oMessage.screenshotOp);
        const oImage = new Image({
          src: sUrl,
          alt: "Screenshot del portale a fine operazione",
          tooltip: "Apri lo screenshot in una nuova scheda",
          width: "100%",
          densityAware: false,
          press: () => window.open(sUrl, "_blank", "noopener"),
          error: () => oImage.setVisible(false) // operazione senza screenshot
        }).addStyleClass("cinghyScreenshot");
        aContent.push(oImage);
      }
      return this._wrap(bUser ? "user" : "bot", aContent);
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
            new Text({ text: "Cinghy avvia l'operazione" })
          ]
        })]));
      }
      if (this._bError) {
        this._oList.addItem(this._wrap("error", [
          new Text({ text: "Non sono riuscito a raggiungere RST. Riprova tra poco." }),
          new Button({
            text: "Riprova",
            icon: "sap-icon://refresh",
            type: "Transparent",
            press: () => this._send()
          }).addStyleClass("cinghyRetry")
        ]));
      }
    }

    _updateLive(oPrev) {
      const oOp = this._oOp;
      const sStatus = oOp ? oOp.status : "";
      const bFocusInLive = this._oLive.getDomRef() && this._oLive.getDomRef().contains(document.activeElement);

      this._oLive.setVisible(!!this._sOpId);
      this._oLiveText.setText(oOp ? oOp.progress || sStatus : "Riprendo l'operazione in corso");
      this._oLiveBusy.setVisible(!oOp || sStatus === "READING" || sStatus === "EXECUTING");
      const sDetail = sStatus === "PLAN_WAIT" ? planHtml(oOp.plan) : sStatus === "LOGIN_WAIT" ? LOGIN_HTML : "";
      this._oLiveDetail.setHtmlText(sDetail);
      this._oLiveDetail.setVisible(!!sDetail);
      this._oConfirm.setVisible(sStatus === "PLAN_WAIT");
      this._oCancel.setVisible(sStatus === "PLAN_WAIT");
      this._oLoginDone.setVisible(sStatus === "LOGIN_WAIT");
      this._oStop.setVisible(!!oOp && sStatus !== "PLAN_WAIT");
      this._aLiveButtons.forEach((oButton) => oButton.setEnabled(true));
      this._updateInput();

      if (oOp && (!oPrev || oPrev.status !== sStatus || oPrev.progress !== oOp.progress)) {
        const bAsk = sStatus === "PLAN_WAIT" || sStatus === "LOGIN_WAIT";
        const sAsk = sStatus === "PLAN_WAIT" ? ". Piano pronto: conferma, annulla o scrivi cosa cambiare"
          : sStatus === "LOGIN_WAIT" ? ". Accedi nel browser del runner, poi premi Ho fatto l'accesso" : "";
        InvisibleMessage.getInstance().announce((oOp.progress || "") + sAsk,
          bAsk ? InvisibleMessageMode.Assertive : InvisibleMessageMode.Polite);
      }
      // un pulsante appena nascosto perde il focus: lo si passa al primo visibile, o all'input
      if (bFocusInLive) {
        setTimeout(() => {
          if (this._oLive.getDomRef() && this._oLive.getDomRef().contains(document.activeElement)) {
            return;
          }
          const oNext = this._aLiveButtons.find((oButton) => oButton.getVisible());
          if (oNext) {
            oNext.focus();
          } else {
            this._oInput.focus();
          }
        }, 0);
      }
      this._scrollToEnd();
    }

    _updateInput() {
      const bPlan = !!this._oOp && this._oOp.status === "PLAN_WAIT";
      this._oInput.setEnabled(!this._bBusy && (!this._sOpId || bPlan));
      this._oInput.setPlaceholder(bPlan ? PLACEHOLDER_PLAN : PLACEHOLDER);
    }

    _scrollToEnd() {
      const oDom = this._oScroll.getDomRef();
      if (oDom) {
        oDom.scrollTop = oDom.scrollHeight;
      }
    }

    _onSubmit() {
      const sText = this._oInput.getValue().trim();
      const bPlan = !!this._oOp && this._oOp.status === "PLAN_WAIT";
      if (this._bBusy || !sText || (this._sOpId && !bPlan)) {
        return;
      }
      this._oInput.setValue("");
      this._aMessages.push({ role: "user", text: sText });
      ConversationStore.save(this._aMessages);
      this._render();
      if (bPlan) {
        this._act((sId) => ChatService.decide(sId, "modify", sText));
      } else {
        this._send();
      }
    }

    // Avvia l'operazione con l'ultimo messaggio del consulente (anche da "Riprova").
    _send() {
      const sInstruction = this._aMessages[this._aMessages.length - 1].text;
      this._bBusy = true;
      this._bError = false;
      this._updateInput();
      this._render();

      ChatService.start(sInstruction).then((oStatus) => {
        this._sOpId = oStatus.opId;
        ConversationStore.saveOperation(this._sOpId);
        this._onStatus(oStatus);
        if (!oStatus.final) {
          this._follow();
        }
      }, (oError) => {
        if (oError.status >= 400 && oError.status < 500) {
          this._answer(oError.message); // RST ha risposto: runner spento, portale sconosciuto, ...
        } else {
          this._bError = true;
          InvisibleMessage.getInstance().announce("Cinghy non è riuscito a raggiungere RST", InvisibleMessageMode.Assertive);
        }
      }).finally(() => {
        this._bBusy = false;
        this._updateInput();
        this._render();
        if (this.isOpen()) {
          setTimeout(() => this._oInput.focus(), 0);
        }
      });
    }

    _follow() {
      if (this._fnStopFollow) {
        this._fnStopFollow();
      }
      this._fnStopFollow = ChatService.follow(this._sOpId, (oStatus) => this._onStatus(oStatus));
    }

    _onStatus(oStatus) {
      if (!this._sOpId || oStatus.opId !== this._sOpId) {
        return; // risposta arrivata dopo la fine dell'operazione
      }
      const oPrev = this._oOp;
      this._oOp = oStatus;
      if (oStatus.final) {
        this._finish(oStatus);
      } else {
        this._updateLive(oPrev);
      }
    }

    _finish(oStatus) {
      if (this._fnStopFollow) {
        this._fnStopFollow();
        this._fnStopFollow = null;
      }
      const sDetail = oStatus.result || oStatus.progress || "";
      const sText = oStatus.status === "DONE" ? sDetail
        : oStatus.status === "CANCELLED" ? sDetail || "Operazione annullata"
          : "L'operazione si è interrotta: " + (sDetail || "errore sconosciuto");
      this._sOpId = "";
      this._oOp = null;
      ConversationStore.saveOperation("");
      this._answer(sText, oStatus.status === "DONE" ? oStatus.opId : undefined);
      this._updateLive();
      if (this.isOpen()) {
        setTimeout(() => this._oInput.focus(), 0);
      }
    }

    _answer(sText, sScreenshotOp, bTransient) {
      this._aMessages.push({ role: "assistant", text: sText, screenshotOp: sScreenshotOp, transient: bTransient });
      ConversationStore.save(this._aMessages);
      this._render();
      InvisibleMessage.getInstance().announce("Risposta di Cinghy: " + markdown.toText(sText), InvisibleMessageMode.Polite);
    }

    _act(fnCall) {
      const sOpId = this._sOpId;
      this._aLiveButtons.forEach((oButton) => oButton.setEnabled(false));
      fnCall(sOpId).then((oStatus) => this._onStatus(oStatus), (oError) => {
        this._aLiveButtons.forEach((oButton) => oButton.setEnabled(true));
        this._answer("Azione non riuscita: " + oError.message);
      });
    }

    _pair() {
      ChatService.pairingCode().then((oCode) => {
        this._answer([
          "Codice di associazione del runner: **" + oCode.code + "**",
          "",
          "Vale " + oCode.validMinutes + " minuti e una sola volta. Nella cartella `runner` del tuo PC avvia:",
          "",
          "```",
          "RST_URL=\"" + ChatService.runnerUrl() + "\" npm start",
          "```",
          "",
          "e inserisci il codice quando il runner lo chiede."
        ].join("\n"), undefined, true);
      }, (oError) => this._answer("Non sono riuscito a generare il codice di associazione: " + oError.message));
    }
  }

  return ChatPanel;
});
