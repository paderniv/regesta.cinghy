"! Passo dell'agente AMS e decisioni del consulente sul piano.
"! Le decisioni senza database (handle_response, apply_decision) sono separate dal passo (step,
"! decide), che legge e scrive operazione, conversazione e passi: le prime si verificano con
"! ABAP Unit, il secondo con le operazioni reali.
CLASS /reg/cl_ams_agent DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF c_kind,
        action   TYPE /reg/ams_step-kind VALUE 'ACTION',
        plan     TYPE /reg/ams_step-kind VALUE 'PLAN',
        decision TYPE /reg/ams_step-kind VALUE 'DECISION',
        report   TYPE /reg/ams_step-kind VALUE 'REPORT',
        "! Chiamata al modello, con il suo costo in token.
        llm      TYPE /reg/ams_step-kind VALUE 'LLM',
        "! Interruzione o accesso fatto, chiesti dal consulente.
        control  TYPE /reg/ams_step-kind VALUE 'CONTROL',
      END OF c_kind,
      "! Esito dell'azione che ha trovato la pagina di login del portale.
      c_login_outcome TYPE /reg/ams_step-outcome VALUE 'LOGIN',
      "! Un runner e' collegato se si e' fatto vivo negli ultimi secondi (il long polling dura 30 s).
      c_runner_grace_seconds TYPE i VALUE 90,
      "! Stato di un'azione per il runner.
      BEGIN OF c_step,
        queued   TYPE /reg/ams_step-status VALUE 'Q',
        sent     TYPE /reg/ams_step-status VALUE 'S',
        done     TYPE /reg/ams_step-status VALUE 'D',
        consumed TYPE /reg/ams_step-status VALUE 'C',
        rejected TYPE /reg/ams_step-status VALUE 'R',
      END OF c_step,
      BEGIN OF c_decision,
        confirm TYPE c LENGTH 1 VALUE 'C',
        cancel  TYPE c LENGTH 1 VALUE 'A',
        modify  TYPE c LENGTH 1 VALUE 'M',
      END OF c_decision.

    TYPES:
      BEGIN OF ty_context,
        phase      TYPE /reg/ams_op-phase,
        plan_steps TYPE i,
        snapshot   TYPE string,
        domains    TYPE string_table,
        safe       TYPE string_table,
        forbidden  TYPE string_table,
        "! Uno screenshot e' stato catturato dopo l'ultima modifica eseguita.
        screenshot_after_changes TYPE abap_bool,
      END OF ty_context,
      BEGIN OF ty_action,
        call     TYPE /reg/if_ams_llm=>ty_tool_call,
        decision TYPE /reg/cl_ams_tools=>ty_decision,
      END OF ty_action,
      ty_actions TYPE STANDARD TABLE OF ty_action WITH EMPTY KEY,
      BEGIN OF ty_outcome,
        "! Risultati degli strumenti da aggiungere subito alla conversazione (rifiuti).
        messages    TYPE /reg/if_ams_llm=>ty_messages,
        "! Azioni ammesse, da mettere in coda per il runner.
        actions     TYPE ty_actions,
        "! Azioni rifiutate, per il registro.
        rejected    TYPE ty_actions,
        "! Nuovo stato dell'operazione; vuoto se invariato.
        status      TYPE /reg/ams_op-status,
        plan_json   TYPE string,
        result_text TYPE string,
      END OF ty_outcome,
      ty_rows TYPE STANDARD TABLE OF /reg/ams_step WITH EMPTY KEY.

    "! Cosa fare con una risposta del modello.
    CLASS-METHODS handle_response
      IMPORTING is_context        TYPE ty_context
                is_response       TYPE /reg/if_ams_llm=>ty_response
      RETURNING VALUE(rs_outcome) TYPE ty_outcome.

    "! Risposta del consulente al piano in attesa, come risultato di propose_plan.
    "! @raising /reg/cx_ams | Nessun piano in attesa nella conversazione
    CLASS-METHODS apply_decision
      IMPORTING is_conversation TYPE /reg/if_ams_llm=>ty_conversation
                iv_decision     TYPE c
                iv_note         TYPE string OPTIONAL
      EXPORTING es_conversation TYPE /reg/if_ams_llm=>ty_conversation
                ev_status       TYPE /reg/ams_op-status
      RAISING   /reg/cx_ams.

    CLASS-METHODS plan_step_count
      IMPORTING iv_plan_json    TYPE string
      RETURNING VALUE(rv_count) TYPE i.

    "! Un passo: esiti del runner nella conversazione, chiamata al modello, azioni in coda,
    "! piano o report. Chiamato dall'unita' bgPF; il framework conferma al termine.
    CLASS-METHODS step
      IMPORTING iv_op_id TYPE sysuuid_x16
      RAISING   cx_static_check.

    "! Decisione del consulente sul piano in attesa; avvia il passo successivo (senza COMMIT).
    "! @raising /reg/cx_ams | Nessun piano in attesa o consulente diverso da chi ha avviato l'operazione
    CLASS-METHODS decide
      IMPORTING iv_op_id    TYPE sysuuid_x16
                iv_decision TYPE c
                iv_note     TYPE string OPTIONAL
      RAISING   /reg/cx_ams.

    "! Righe del registro per una risposta del modello: la chiamata con il suo costo, le azioni
    "! in coda o rifiutate, il piano, il report. Ogni riga porta il consulente dell'operazione.
    CLASS-METHODS log_rows
      IMPORTING is_op          TYPE /reg/ams_op
                iv_model       TYPE string
                is_response    TYPE /reg/if_ams_llm=>ty_response
                is_outcome     TYPE ty_outcome
                iv_seq         TYPE i
                iv_now         TYPE timestampl
      RETURNING VALUE(rt_rows) TYPE ty_rows.

    "! Esito di un'azione dal runner (servizio per i runner). Avvia il passo successivo quando non
    "! restano azioni in attesa; con login_required sospende l'operazione in attesa di login (senza COMMIT).
    "! @raising /reg/cx_ams | Azione inesistente o esito gia' ricevuto
    CLASS-METHODS action_result
      IMPORTING iv_step_id        TYPE sysuuid_x16
                iv_result         TYPE string
                iv_is_error       TYPE abap_bool
                iv_summary        TYPE string OPTIONAL
                iv_login_required TYPE abap_bool OPTIONAL
                iv_screenshot     TYPE xstring OPTIONAL
      RAISING   /reg/cx_ams.

    "! Il consulente ha fatto l'accesso al portale: l'operazione riprende nella sua fase (senza COMMIT).
    "! @raising /reg/cx_ams | Operazione non in attesa di login o di un altro consulente
    CLASS-METHODS login_done
      IMPORTING iv_op_id TYPE sysuuid_x16
      RAISING   /reg/cx_ams.

    "! Interruzione chiesta dal consulente: subito se l'operazione e' in attesa del consulente,
    "! altrimenti dopo l'azione in corso. Le azioni non ancora consegnate al runner non partono (senza COMMIT).
    "! @raising /reg/cx_ams | Operazione di un altro consulente
    CLASS-METHODS stop
      IMPORTING iv_op_id TYPE sysuuid_x16
      RAISING   /reg/cx_ams.

    "! Runner collegato per il consulente (runner locale) o runner centrale collegato.
    CLASS-METHODS runner_online
      IMPORTING iv_consultant    TYPE syuname
                iv_runner_kind   TYPE string
      RETURNING VALUE(rv_online) TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS by_model
      IMPORTING is_cfg          TYPE /reg/cl_ams_cfg=>ty_app_config
                iv_llm          TYPE string
      RETURNING VALUE(rv_model) TYPE string.

    CLASS-METHODS check_owner
      IMPORTING is_op TYPE /reg/ams_op
      RAISING   /reg/cx_ams.

    CLASS-METHODS progress_text
      IMPORTING is_action      TYPE ty_action
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS log_step
      IMPORTING is_step TYPE /reg/ams_step.

    CLASS-METHODS next_seq
      IMPORTING iv_op_id      TYPE sysuuid_x16
      RETURNING VALUE(rv_seq) TYPE i.
ENDCLASS.


CLASS /reg/cl_ams_agent IMPLEMENTATION.

  METHOD handle_response.
    TYPES: BEGIN OF ty_step_result,
             number  TYPE i,
             applied TYPE abap_bool,
             detail  TYPE string,
           END OF ty_step_result,
           BEGIN OF ty_report,
             text               TYPE string,
             steps              TYPE STANDARD TABLE OF ty_step_result WITH EMPTY KEY,
             suspicious_content TYPE string,
           END OF ty_report.

    IF is_response-tool_calls IS INITIAL.
      " Testo senza strumenti: vale come risposta finale.
      CASE is_response-stop_reason.
        WHEN /reg/if_ams_llm=>c_stop-max_tokens.
          rs_outcome-status      = /reg/cl_ams_op=>c_status-error.
          rs_outcome-result_text = `Risposta del modello troncata: limite di token raggiunto`.
        WHEN /reg/if_ams_llm=>c_stop-refused.
          rs_outcome-status      = /reg/cl_ams_op=>c_status-error.
          rs_outcome-result_text = |Il modello ha rifiutato di proseguire: { is_response-text }|.
        WHEN OTHERS.
          rs_outcome-status      = /reg/cl_ams_op=>c_status-done.
          rs_outcome-result_text = is_response-text.
      ENDCASE.
      RETURN.
    ENDIF.

    " Piano o report fermano il passo: le altre azioni della stessa risposta non si eseguono.
    DATA(lv_stops) = xsdbool( line_exists( is_response-tool_calls[ name = /reg/cl_ams_tools=>c_tool-propose_plan ] )
                              OR line_exists( is_response-tool_calls[ name = /reg/cl_ams_tools=>c_tool-report ] ) ).

    LOOP AT is_response-tool_calls INTO DATA(ls_call).
      CASE ls_call-name.
        WHEN /reg/cl_ams_tools=>c_tool-propose_plan.
          " Il risultato di propose_plan arriva con la decisione del consulente.
          rs_outcome-status    = /reg/cl_ams_op=>c_status-plan_wait.
          rs_outcome-plan_json = ls_call-arguments.

        WHEN /reg/cl_ams_tools=>c_tool-report.
          DATA(ls_report) = VALUE ty_report( ).
          /ui2/cl_json=>deserialize( EXPORTING json = ls_call-arguments CHANGING data = ls_report ).

          " Dopo un piano eseguito il report vale solo con l'esito di ogni passo e lo screenshot del risultato.
          IF is_context-phase = /reg/cl_ams_op=>c_phase-execute.
            DATA(lv_missing) = REDUCE string( INIT m = ``
                                              FOR n = 1 UNTIL n > is_context-plan_steps
                                              NEXT m = COND #( WHEN line_exists( ls_report-steps[ number = n ] ) THEN m
                                                               WHEN m IS INITIAL THEN |{ n }| ELSE |{ m }, { n }| ) ).
            DATA(lv_refusal) = COND string(
              WHEN lv_missing IS NOT INITIAL
              THEN |Report non accettato: manca l'esito verificato dei passi { lv_missing } del piano|
              WHEN is_context-screenshot_after_changes = abap_false
              THEN |Report non accettato: cattura prima uno screenshot del risultato con { /reg/cl_ams_tools=>c_tool-screenshot }| ).
            IF lv_refusal IS NOT INITIAL.
              APPEND VALUE #( role = /reg/if_ams_llm=>c_role-tool tool_call_id = ls_call-id tool_name = ls_call-name is_error = abap_true
                              text = lv_refusal ) TO rs_outcome-messages.
              CONTINUE.
            ENDIF.
          ENDIF.

          rs_outcome-status      = /reg/cl_ams_op=>c_status-done.
          rs_outcome-result_text = ls_report-text.
          IF ls_report-steps IS NOT INITIAL.
            SORT ls_report-steps BY number.
            DATA(lv_failed) = REDUCE i( INIT f = 0 FOR s IN ls_report-steps WHERE ( applied = abap_false ) NEXT f = f + 1 ).
            rs_outcome-result_text = rs_outcome-result_text &&
              |\n\nEsito delle modifiche ({ lines( ls_report-steps ) - lv_failed } riuscite, { lv_failed } non riuscite):| &&
              REDUCE string( INIT t = `` FOR s IN ls_report-steps
                             NEXT t = t && |\n- Passo { s-number }: { COND string( WHEN s-applied = abap_true THEN `riuscito`
                                                                                    ELSE `NON riuscito` ) }| &&
                                      COND string( WHEN s-detail IS NOT INITIAL THEN | - { s-detail }| ) ).
          ENDIF.
          IF ls_report-suspicious_content IS NOT INITIAL.
            rs_outcome-result_text = |{ rs_outcome-result_text }\n\nRichieste sospette trovate nel portale: { ls_report-suspicious_content }|.
          ENDIF.

        WHEN OTHERS.
          IF lv_stops = abap_true.
            APPEND VALUE #( role = /reg/if_ams_llm=>c_role-tool tool_call_id = ls_call-id tool_name = ls_call-name is_error = abap_true
                            text = `Non eseguita: l'operazione si ferma per il piano o il report` ) TO rs_outcome-messages.
            CONTINUE.
          ENDIF.
          DATA(ls_decision) = /reg/cl_ams_tools=>check( is_call       = ls_call
                                                        iv_phase      = is_context-phase
                                                        it_domains    = is_context-domains
                                                        it_safe       = is_context-safe
                                                        it_forbidden  = is_context-forbidden
                                                        iv_snapshot   = is_context-snapshot
                                                        iv_plan_steps = is_context-plan_steps ).
          IF ls_decision-allowed = abap_true.
            APPEND VALUE #( call = ls_call decision = ls_decision ) TO rs_outcome-actions.
          ELSE.
            APPEND VALUE #( call = ls_call decision = ls_decision ) TO rs_outcome-rejected.
            APPEND VALUE #( role = /reg/if_ams_llm=>c_role-tool tool_call_id = ls_call-id tool_name = ls_call-name is_error = abap_true
                            text = ls_decision-reason ) TO rs_outcome-messages.
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD apply_decision.
    DATA lv_call_id TYPE string.

    es_conversation = is_conversation.
    " Ultima chiamata a propose_plan ancora senza risultato.
    LOOP AT is_conversation-messages INTO DATA(ls_message) WHERE role = /reg/if_ams_llm=>c_role-assistant.
      LOOP AT ls_message-tool_calls INTO DATA(ls_call) WHERE name = /reg/cl_ams_tools=>c_tool-propose_plan.
        lv_call_id = ls_call-id.
      ENDLOOP.
    ENDLOOP.
    IF lv_call_id IS INITIAL
       OR line_exists( is_conversation-messages[ role = /reg/if_ams_llm=>c_role-tool tool_call_id = lv_call_id ] ).
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Nessun piano in attesa di conferma` ).
    ENDIF.

    DATA(lv_text) = SWITCH string( iv_decision
      WHEN c_decision-confirm THEN `Piano confermato dal consulente. Eseguilo passo per passo indicando plan_step in ogni modifica, ` &&
                                   `poi verifica sul portale che ogni modifica risulti applicata e chiudi con report.`
      WHEN c_decision-cancel  THEN `Piano annullato dal consulente: nessuna modifica va eseguita. Chiudi con report.`
      WHEN c_decision-modify  THEN |Il consulente chiede di cambiare il piano: { iv_note }. Proponi un nuovo piano con propose_plan.| ).
    IF lv_text IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Decisione { iv_decision } sconosciuta| ).
    ENDIF.

    ev_status = SWITCH #( iv_decision
      WHEN c_decision-confirm THEN /reg/cl_ams_op=>c_status-executing
      WHEN c_decision-cancel  THEN /reg/cl_ams_op=>c_status-cancelled
      WHEN c_decision-modify  THEN /reg/cl_ams_op=>c_status-reading ).

    APPEND VALUE #( role = /reg/if_ams_llm=>c_role-tool tool_call_id = lv_call_id
                    tool_name = /reg/cl_ams_tools=>c_tool-propose_plan text = lv_text ) TO es_conversation-messages.
  ENDMETHOD.

  METHOD plan_step_count.
    TYPES: BEGIN OF ty_step,
             number TYPE i,
           END OF ty_step,
           BEGIN OF ty_plan,
             steps TYPE STANDARD TABLE OF ty_step WITH EMPTY KEY,
           END OF ty_plan.
    DATA ls_plan TYPE ty_plan.
    /ui2/cl_json=>deserialize( EXPORTING json = iv_plan_json CHANGING data = ls_plan ).
    rv_count = lines( ls_plan-steps ).
  ENDMETHOD.

  METHOD step.
    DATA lv_now TYPE timestampl.
    DATA lt_snapshot TYPE string_table.

    DATA(ls_op)  = /reg/cl_ams_op=>get( iv_op_id ).
    DATA(ls_cfg) = NEW /reg/cl_ams_cfg( )->app_cfg_par.

    " Senza runner collegato non c'e' nessuno che esegua le azioni: meglio dirlo subito.
    DATA(lv_runner_kind) = VALUE string( ls_cfg-portals[ portal = ls_op-portal ]-runner_kind OPTIONAL ).
    IF runner_online( iv_consultant = ls_op-consultant iv_runner_kind = lv_runner_kind ) = abap_false.
      /reg/cl_ams_op=>fail( iv_op_id  = iv_op_id
                            iv_reason = COND #( WHEN to_upper( lv_runner_kind ) = `CENTRAL`
                                                THEN `Il runner centrale non e' collegato: avvisa l'amministratore dell'agente AMS`
                                                ELSE `Il tuo runner non e' collegato: avvialo sul tuo PC (npm start nella cartella runner) ` &&
                                                     `e ripeti l'istruzione` ) ).
      RETURN.
    ENDIF.

    DATA(ls_conversation) = /reg/cl_ams_conv=>load( iv_op_id ).
    IF ls_conversation-messages IS INITIAL.
      ls_conversation-system = /reg/cl_ams_prompt=>system_prompt( is_cfg = ls_cfg iv_portal = CONV #( ls_op-portal ) ).
      APPEND VALUE #( role = /reg/if_ams_llm=>c_role-user text = ls_op-instruction ) TO ls_conversation-messages.
    ENDIF.

    " Esiti del runner: si prosegue solo quando tutte le azioni in coda hanno un esito.
    SELECT * FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND kind = @c_kind-action
        AND ( status = @c_step-queued OR status = @c_step-sent OR status = @c_step-done )
      ORDER BY seq
      INTO TABLE @DATA(lt_open).
    IF line_exists( lt_open[ status = c_step-queued ] ) OR line_exists( lt_open[ status = c_step-sent ] ).
      RETURN.
    ENDIF.
    LOOP AT lt_open ASSIGNING FIELD-SYMBOL(<ls_done>).
      APPEND VALUE #( role         = /reg/if_ams_llm=>c_role-tool
                      tool_call_id = <ls_done>-call_id
                      tool_name    = <ls_done>-tool
                      is_error     = <ls_done>-is_error
                      text         = COND #( WHEN <ls_done>-is_error = abap_true THEN <ls_done>-result_text
                                             ELSE /reg/cl_ams_prompt=>wrap_portal_content( <ls_done>-result_text ) )
                      reducible    = xsdbool( <ls_done>-is_error = abap_false )
                      summary      = COND #( WHEN <ls_done>-outcome IS NOT INITIAL THEN <ls_done>-outcome
                                             ELSE |{ <ls_done>-tool }: pagina letta| ) ) TO ls_conversation-messages.
      <ls_done>-status = c_step-consumed.
    ENDLOOP.
    UPDATE /reg/ams_step FROM TABLE @lt_open.

    " Ultima pagina letta, per il filtro delle azioni.
    SELECT result_text FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND status = @c_step-consumed AND is_error = @abap_false
      ORDER BY seq DESCENDING
      INTO TABLE @lt_snapshot UP TO 1 ROWS.

    " Screenshot del risultato: deve venire dopo l'ultima azione di modifica (plan_step > 0).
    SELECT MAX( seq ) FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND status = @c_step-consumed AND plan_step > 0
      INTO @DATA(lv_last_change).
    SELECT MAX( seq ) FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND status = @c_step-consumed AND is_error = @abap_false
        AND tool = @/reg/cl_ams_tools=>c_tool-screenshot
      INTO @DATA(lv_last_screenshot).

    " Chiamata al modello registrato nell'operazione: resta lo stesso fino alla fine.
    DATA(lo_llm) = /reg/cl_ams_llm_factory=>create( /reg/cl_ams_llm_factory=>by_code( is_cfg = ls_cfg iv_llm = CONV #( ls_op-llm ) ) ).
    ls_conversation = /reg/cl_ams_conv=>reduce( ls_conversation ).
    DATA(ls_response) = lo_llm->complete( is_conversation = ls_conversation
                                          it_tools        = /reg/cl_ams_tools=>definitions( ) ).
    APPEND VALUE #( role          = /reg/if_ams_llm=>c_role-assistant
                    text          = ls_response-text
                    tool_calls    = ls_response-tool_calls
                    provider_data = ls_response-provider_data ) TO ls_conversation-messages.

    DATA(ls_outcome) = handle_response(
      is_context  = VALUE #( phase      = ls_op-phase
                             plan_steps = plan_step_count( ls_op-plan_json )
                             snapshot   = VALUE #( lt_snapshot[ 1 ] OPTIONAL )
                             domains    = VALUE #( FOR d IN ls_cfg-portal_domains WHERE ( portal = ls_op-portal ) ( to_lower( d-domain ) ) )
                             safe       = VALUE #( FOR b IN ls_cfg-safe_buttons WHERE ( portal = ls_op-portal ) ( b-label ) )
                             forbidden  = VALUE #( FOR f IN ls_cfg-forbidden_elements WHERE ( portal = ls_op-portal ) ( f-label ) )
                             screenshot_after_changes = xsdbool( lv_last_screenshot > lv_last_change ) )
      is_response = ls_response ).
    APPEND LINES OF ls_outcome-messages TO ls_conversation-messages.

    " Registro e coda: chiamata al modello con il costo, azioni ammesse in coda, rifiutate solo nel registro.
    GET TIME STAMP FIELD lv_now.
    LOOP AT log_rows( is_op       = ls_op
                      iv_model    = by_model( is_cfg = ls_cfg iv_llm = CONV #( ls_op-llm ) )
                      is_response = ls_response
                      is_outcome  = ls_outcome
                      iv_seq      = next_seq( iv_op_id )
                      iv_now      = lv_now ) INTO DATA(ls_row).
      log_step( ls_row ).
    ENDLOOP.

    " Operazione: passi, costo, piano, avanzamento.
    DATA(lv_progress) = COND /reg/ams_op-progress( WHEN ls_outcome-actions IS NOT INITIAL
                                                   THEN progress_text( ls_outcome-actions[ 1 ] )
                                                   ELSE ls_op-progress ).
    UPDATE /reg/ams_op SET steps         = steps + 1,
                           input_tokens  = input_tokens + @ls_response-input_tokens,
                           output_tokens = output_tokens + @ls_response-output_tokens,
                           progress      = @lv_progress,
                           changed_at    = @lv_now
                       WHERE op_id = @iv_op_id.
    IF ls_outcome-plan_json IS NOT INITIAL.
      UPDATE /reg/ams_op SET plan_json = @ls_outcome-plan_json WHERE op_id = @iv_op_id.
    ENDIF.
    /reg/cl_ams_conv=>save( iv_op_id = iv_op_id is_conversation = ls_conversation ).

    IF ls_outcome-status IS NOT INITIAL.
      /reg/cl_ams_op=>set_status( iv_op_id    = iv_op_id
                                  iv_status   = ls_outcome-status
                                  iv_progress = SWITCH string( ls_outcome-status
                                                  WHEN /reg/cl_ams_op=>c_status-plan_wait THEN `Piano pronto: in attesa della tua conferma`
                                                  WHEN /reg/cl_ams_op=>c_status-done      THEN `Operazione completata`
                                                  ELSE `Operazione terminata con errore` )
                                  iv_result   = ls_outcome-result_text ).
    ELSEIF ls_outcome-actions IS INITIAL.
      " Solo azioni rifiutate: il modello deve reagire subito, non c'e' nulla da attendere dal runner.
      /reg/cl_ams_op=>schedule_step( iv_op_id ).
    ENDIF.
  ENDMETHOD.

  METHOD decide.
    DATA lv_now TYPE timestampl.

    DATA(ls_op) = /reg/cl_ams_op=>get( iv_op_id ).
    check_owner( ls_op ).
    IF ls_op-status <> /reg/cl_ams_op=>c_status-plan_wait.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Nessun piano in attesa: l'operazione e' in stato { ls_op-status }| ).
    ENDIF.

    apply_decision( EXPORTING is_conversation = /reg/cl_ams_conv=>load( iv_op_id )
                              iv_decision     = iv_decision
                              iv_note         = iv_note
                    IMPORTING es_conversation = DATA(ls_conversation)
                              ev_status       = DATA(lv_status) ).
    /reg/cl_ams_conv=>save( iv_op_id = iv_op_id is_conversation = ls_conversation ).

    GET TIME STAMP FIELD lv_now.
    log_step( VALUE #( op_id = iv_op_id seq = next_seq( iv_op_id ) kind = c_kind-decision
                       outcome = SWITCH #( iv_decision WHEN c_decision-confirm THEN `Piano confermato`
                                                       WHEN c_decision-cancel  THEN `Piano annullato`
                                                       ELSE `Modifica del piano richiesta` )
                       args = iv_note created_by = sy-uname created_at = lv_now ) ).

    /reg/cl_ams_op=>set_status(
      iv_op_id    = iv_op_id
      iv_status   = lv_status
      iv_progress = SWITCH string( iv_decision WHEN c_decision-confirm THEN `Piano confermato: eseguo le modifiche`
                                               WHEN c_decision-cancel  THEN `Piano annullato`
                                               ELSE `Preparo un nuovo piano` )
      iv_result   = COND #( WHEN iv_decision = c_decision-cancel THEN `Piano annullato: nessuna modifica eseguita sul portale` ) ).

    IF lv_status <> /reg/cl_ams_op=>c_status-cancelled.
      /reg/cl_ams_op=>schedule_step( iv_op_id ).
    ENDIF.
  ENDMETHOD.

  METHOD log_rows.
    DATA(lv_seq) = iv_seq.

    APPEND VALUE #( op_id = is_op-op_id seq = lv_seq kind = c_kind-llm tool = is_op-llm elem_name = iv_model
                    outcome = is_response-stop_reason
                    input_tokens = is_response-input_tokens output_tokens = is_response-output_tokens
                    created_by = is_op-consultant created_at = iv_now ) TO rt_rows.
    lv_seq += 1.

    LOOP AT is_outcome-actions INTO DATA(ls_action).
      APPEND VALUE #( op_id = is_op-op_id seq = lv_seq kind = c_kind-action tool = ls_action-call-name call_id = ls_action-call-id
                      plan_step = ls_action-decision-plan_step elem_role = ls_action-decision-elem_role
                      elem_name = ls_action-decision-elem_name status = c_step-queued args = ls_action-call-arguments
                      created_by = is_op-consultant created_at = iv_now ) TO rt_rows.
      lv_seq += 1.
    ENDLOOP.
    LOOP AT is_outcome-rejected INTO ls_action.
      APPEND VALUE #( op_id = is_op-op_id seq = lv_seq kind = c_kind-action tool = ls_action-call-name call_id = ls_action-call-id
                      plan_step = ls_action-decision-plan_step elem_role = ls_action-decision-elem_role
                      elem_name = ls_action-decision-elem_name status = c_step-rejected is_error = abap_true
                      outcome = ls_action-decision-reason args = ls_action-call-arguments
                      created_by = is_op-consultant created_at = iv_now ) TO rt_rows.
      lv_seq += 1.
    ENDLOOP.
    IF is_outcome-plan_json IS NOT INITIAL.
      APPEND VALUE #( op_id = is_op-op_id seq = lv_seq kind = c_kind-plan tool = /reg/cl_ams_tools=>c_tool-propose_plan
                      args = is_outcome-plan_json created_by = is_op-consultant created_at = iv_now ) TO rt_rows.
      lv_seq += 1.
    ENDIF.
    IF is_outcome-status = /reg/cl_ams_op=>c_status-done.
      APPEND VALUE #( op_id = is_op-op_id seq = lv_seq kind = c_kind-report tool = /reg/cl_ams_tools=>c_tool-report
                      result_text = is_outcome-result_text created_by = is_op-consultant created_at = iv_now ) TO rt_rows.
    ENDIF.
  ENDMETHOD.

  METHOD action_result.
    DATA lv_now TYPE timestampl.

    SELECT SINGLE * FROM /reg/ams_step WHERE step_id = @iv_step_id INTO @DATA(ls_step).
    IF sy-subrc <> 0 OR ls_step-kind <> c_kind-action.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Azione { iv_step_id } non trovata| ).
    ENDIF.
    IF ls_step-status <> c_step-sent AND ls_step-status <> c_step-queued.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Esito dell'azione { iv_step_id } gia' ricevuto| ).
    ENDIF.

    GET TIME STAMP FIELD lv_now.
    ls_step-status     = c_step-done.
    ls_step-done_at    = lv_now.
    ls_step-is_error   = iv_is_error.
    ls_step-result_text = iv_result.
    ls_step-outcome    = iv_summary.
    ls_step-screenshot = iv_screenshot.

    IF iv_login_required = abap_true.
      " La pagina di login non arriva al modello: solo l'esito, e l'operazione aspetta il consulente.
      ls_step-is_error    = abap_true.
      ls_step-outcome     = c_login_outcome.
      ls_step-result_text = `Il portale ha chiesto il login: l'azione non e' stata eseguita. Attendi l'accesso del consulente.`.
      ls_step-screenshot  = VALUE #( ).
      UPDATE /reg/ams_step FROM @ls_step.
      /reg/cl_ams_op=>set_status( iv_op_id    = ls_step-op_id
                                  iv_status   = /reg/cl_ams_op=>c_status-login_wait
                                  iv_progress = `Accedi al portale nel browser del runner, poi premi "Ho fatto l'accesso"` ).
      RETURN.
    ENDIF.

    UPDATE /reg/ams_step FROM @ls_step.
    UPDATE /reg/ams_op SET changed_at = @lv_now WHERE op_id = @ls_step-op_id.

    SELECT COUNT(*) FROM /reg/ams_step
      WHERE op_id = @ls_step-op_id AND kind = @c_kind-action
        AND ( status = @c_step-queued OR status = @c_step-sent ).
    IF sy-dbcnt = 0.
      /reg/cl_ams_op=>schedule_step( ls_step-op_id ).
    ENDIF.
  ENDMETHOD.

  METHOD login_done.
    DATA lv_now TYPE timestampl.

    DATA(ls_op) = /reg/cl_ams_op=>get( iv_op_id ).
    check_owner( ls_op ).
    IF ls_op-status <> /reg/cl_ams_op=>c_status-login_wait.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |L'operazione non e' in attesa di login (stato { ls_op-status })| ).
    ENDIF.

    " Il modello riceve che l'accesso e' fatto e ripete l'azione rimasta in sospeso.
    UPDATE /reg/ams_step SET result_text = `Il consulente ha fatto l'accesso al portale: ripeti l'azione.`
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND status = @c_step-done AND outcome = @c_login_outcome.

    GET TIME STAMP FIELD lv_now.
    log_step( VALUE #( op_id = iv_op_id seq = next_seq( iv_op_id ) kind = c_kind-control outcome = `Accesso al portale fatto`
                       created_by = sy-uname created_at = lv_now ) ).
    /reg/cl_ams_op=>set_status( iv_op_id    = iv_op_id
                                iv_status   = COND #( WHEN ls_op-phase = /reg/cl_ams_op=>c_phase-execute
                                                      THEN /reg/cl_ams_op=>c_status-executing
                                                      ELSE /reg/cl_ams_op=>c_status-reading )
                                iv_progress = `Accesso fatto: riprendo` ).

    SELECT COUNT(*) FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND ( status = @c_step-queued OR status = @c_step-sent ).
    IF sy-dbcnt = 0.
      /reg/cl_ams_op=>schedule_step( iv_op_id ).
    ENDIF.
  ENDMETHOD.

  METHOD stop.
    DATA lv_now TYPE timestampl.

    DATA(ls_op) = /reg/cl_ams_op=>get( iv_op_id ).
    check_owner( ls_op ).
    IF /reg/cl_ams_op=>is_final( ls_op-status ) = abap_true.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD lv_now.
    log_step( VALUE #( op_id = iv_op_id seq = next_seq( iv_op_id ) kind = c_kind-control outcome = `Interruzione chiesta`
                       created_by = sy-uname created_at = lv_now ) ).

    " Le azioni non ancora consegnate al runner non partono piu'.
    UPDATE /reg/ams_step SET status = @c_step-rejected, is_error = @abap_true, outcome = 'Non eseguita: operazione interrotta'
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND status = @c_step-queued.

    IF ls_op-status = /reg/cl_ams_op=>c_status-plan_wait OR ls_op-status = /reg/cl_ams_op=>c_status-login_wait.
      " In attesa del consulente non c'e' nessuna azione in corso: si chiude subito.
      /reg/cl_ams_op=>set_status( iv_op_id    = iv_op_id
                                  iv_status   = /reg/cl_ams_op=>c_status-cancelled
                                  iv_progress = `Operazione interrotta`
                                  iv_result   = `Operazione interrotta dal consulente` ).
      RETURN.
    ENDIF.

    /reg/cl_ams_op=>request_stop( iv_op_id ).
    " Se nessuna azione e' in corso nel runner, il passo che legge l'interruzione parte subito;
    " altrimenti parte all'arrivo dell'esito dell'azione in corso.
    SELECT COUNT(*) FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND kind = @c_kind-action AND status = @c_step-sent.
    IF sy-dbcnt = 0.
      /reg/cl_ams_op=>schedule_step( iv_op_id ).
    ENDIF.
  ENDMETHOD.

  METHOD runner_online.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    DATA(lv_since) = cl_abap_tstmp=>subtractsecs( tstmp = lv_now secs = c_runner_grace_seconds ).

    IF to_upper( iv_runner_kind ) = `CENTRAL`.
      SELECT SINGLE @abap_true FROM /reg/ams_run
        WHERE owner = @space AND revoked = @abap_false AND last_seen >= @lv_since
        INTO @rv_online.
    ELSE.
      SELECT SINGLE @abap_true FROM /reg/ams_run
        WHERE owner = @iv_consultant AND revoked = @abap_false AND last_seen >= @lv_since
        INTO @rv_online.
    ENDIF.
  ENDMETHOD.

  METHOD by_model.
    rv_model = VALUE #( is_cfg-llms[ llm = iv_llm ]-model OPTIONAL ).
  ENDMETHOD.

  METHOD check_owner.
    IF is_op-consultant <> sy-uname.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Solo il consulente che ha avviato l'operazione puo' intervenire su di essa` ).
    ENDIF.
  ENDMETHOD.

  METHOD progress_text.
    rv_text = SWITCH #( is_action-call-name
      WHEN /reg/cl_ams_tools=>c_tool-navigate THEN `Apro una pagina del portale`
      WHEN /reg/cl_ams_tools=>c_tool-snapshot THEN `Leggo la pagina`
      WHEN /reg/cl_ams_tools=>c_tool-click    THEN |Clic su "{ is_action-decision-elem_name }"|
      WHEN /reg/cl_ams_tools=>c_tool-type     THEN |Scrivo in "{ is_action-decision-elem_name }"|
      WHEN /reg/cl_ams_tools=>c_tool-select_option THEN |Scelgo un valore in "{ is_action-decision-elem_name }"|
      ELSE `Lavoro sul portale` ).
  ENDMETHOD.

  METHOD log_step.
    DATA(ls_step) = is_step.
    TRY.
        ls_step-step_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        " Senza id non si puo' scrivere la riga: improbabile, e il passo resta comunque nella conversazione.
        RETURN.
    ENDTRY.
    INSERT /reg/ams_step FROM @ls_step.
  ENDMETHOD.

  METHOD next_seq.
    SELECT MAX( seq ) FROM /reg/ams_step WHERE op_id = @iv_op_id INTO @rv_seq.
    rv_seq += 1.
  ENDMETHOD.

ENDCLASS.
