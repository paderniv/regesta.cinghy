CLASS ltc_agent DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS c_plan TYPE string VALUE
      `{"steps":[{"number":1,"change":"Priorita P2"},{"number":2,"change":"Risposta","reply_text":"Stiamo verificando"}]}`.
    DATA ms_context TYPE /reg/cl_ams_agent=>ty_context.
    METHODS setup.
    METHODS waiting_conversation
      RETURNING VALUE(rs_conversation) TYPE /reg/if_ams_llm=>ty_conversation.
    METHODS plan_stops_and_waits FOR TESTING.
    METHODS actions_queued_or_refused FOR TESTING.
    METHODS confirm_starts_execution FOR TESTING RAISING cx_static_check.
    METHODS cancel_closes_without_changes FOR TESTING RAISING cx_static_check.
    METHODS modify_asks_new_plan FOR TESTING RAISING cx_static_check.
    METHODS no_pending_plan_raises FOR TESTING.
    METHODS plan_answered_twice_raises FOR TESTING RAISING cx_static_check.
    METHODS counts_plan_steps FOR TESTING.
    METHODS report
      IMPORTING iv_args            TYPE string
                iv_phase           TYPE /reg/ams_op-phase
                iv_screenshot      TYPE abap_bool
      RETURNING VALUE(rs_outcome) TYPE /reg/cl_ams_agent=>ty_outcome.
    METHODS report_partial_execution FOR TESTING.
    METHODS report_missing_step_refused FOR TESTING.
    METHODS report_needs_screenshot FOR TESTING.
    METHODS report_after_reading_only FOR TESTING.
    METHODS log_has_consultant_and_cost FOR TESTING.
ENDCLASS.


CLASS ltc_agent IMPLEMENTATION.

  METHOD setup.
    ms_context = VALUE #( phase    = /reg/cl_ams_op=>c_phase-read
                          snapshot = |- link "Ticket 12345" [ref=e1]\n- button "Salva" [ref=e2]|
                          domains  = VALUE #( ( `hdserver.pittini.it` ) )
                          safe     = VALUE #( ( `Cerca` ) ) ).
  ENDMETHOD.

  METHOD waiting_conversation.
    rs_conversation = VALUE #(
      system   = `regole`
      messages = VALUE #(
        ( role = /reg/if_ams_llm=>c_role-user text = `Pittini: ticket 12345, priorita alta e rispondi` )
        ( role = /reg/if_ams_llm=>c_role-assistant
          tool_calls = VALUE #( ( id = `p1` name = `propose_plan` arguments = c_plan ) ) ) ) ).
  ENDMETHOD.

  METHOD plan_stops_and_waits.
    DATA(ls_outcome) = /reg/cl_ams_agent=>handle_response(
      is_context  = ms_context
      is_response = VALUE #( stop_reason = /reg/if_ams_llm=>c_stop-tool_use
                             tool_calls  = VALUE #( ( id = `c1` name = `browser_click` arguments = `{"element":"t","ref":"e1"}` )
                                                    ( id = `p1` name = `propose_plan` arguments = c_plan ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-status exp = /reg/cl_ams_op=>c_status-plan_wait ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-plan_json exp = c_plan ).
    " Con un piano in attesa nessuna azione parte: quella insieme al piano riceve un risultato di non esecuzione.
    cl_abap_unit_assert=>assert_initial( ls_outcome-actions ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_outcome-messages ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-messages[ 1 ]-tool_call_id exp = `c1` ).
    cl_abap_unit_assert=>assert_true( ls_outcome-messages[ 1 ]-is_error ).
  ENDMETHOD.

  METHOD actions_queued_or_refused.
    DATA(ls_outcome) = /reg/cl_ams_agent=>handle_response(
      is_context  = ms_context
      is_response = VALUE #( stop_reason = /reg/if_ams_llm=>c_stop-tool_use
                             tool_calls  = VALUE #( ( id = `c1` name = `browser_click` arguments = `{"element":"t","ref":"e1"}` )
                                                    ( id = `c2` name = `browser_click` arguments = `{"element":"s","ref":"e2"}` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( ls_outcome-status ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_outcome-actions ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-actions[ 1 ]-call-id exp = `c1` ).
    " Salva in fase di lettura: rifiutato, registrato, e il modello riceve il motivo.
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-rejected[ 1 ]-call-id exp = `c2` ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-messages[ 1 ]-tool_call_id exp = `c2` ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_outcome-messages[ 1 ]-text exp = `*proponi un piano*` ).
  ENDMETHOD.

  METHOD confirm_starts_execution.
    /reg/cl_ams_agent=>apply_decision( EXPORTING is_conversation = waiting_conversation( )
                                                 iv_decision     = /reg/cl_ams_agent=>c_decision-confirm
                                       IMPORTING es_conversation = DATA(ls_conversation)
                                                 ev_status       = DATA(lv_status) ).
    cl_abap_unit_assert=>assert_equals( act = lv_status exp = /reg/cl_ams_op=>c_status-executing ).
    DATA(ls_last) = ls_conversation-messages[ lines( ls_conversation-messages ) ].
    cl_abap_unit_assert=>assert_equals( act = ls_last-role exp = /reg/if_ams_llm=>c_role-tool ).
    cl_abap_unit_assert=>assert_equals( act = ls_last-tool_call_id exp = `p1` ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_last-text exp = `Piano confermato*plan_step*` ).
  ENDMETHOD.

  METHOD cancel_closes_without_changes.
    /reg/cl_ams_agent=>apply_decision( EXPORTING is_conversation = waiting_conversation( )
                                                 iv_decision     = /reg/cl_ams_agent=>c_decision-cancel
                                       IMPORTING es_conversation = DATA(ls_conversation)
                                                 ev_status       = DATA(lv_status) ).
    cl_abap_unit_assert=>assert_equals( act = lv_status exp = /reg/cl_ams_op=>c_status-cancelled ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_conversation-messages[ lines( ls_conversation-messages ) ]-text
                                         exp = `Piano annullato*nessuna modifica*` ).
  ENDMETHOD.

  METHOD modify_asks_new_plan.
    /reg/cl_ams_agent=>apply_decision( EXPORTING is_conversation = waiting_conversation( )
                                                 iv_decision     = /reg/cl_ams_agent=>c_decision-modify
                                                 iv_note         = `la risposta deve citare il numero di ordine`
                                       IMPORTING es_conversation = DATA(ls_conversation)
                                                 ev_status       = DATA(lv_status) ).
    " Torna in lettura: il nuovo piano va di nuovo confermato prima di modificare.
    cl_abap_unit_assert=>assert_equals( act = lv_status exp = /reg/cl_ams_op=>c_status-reading ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_conversation-messages[ lines( ls_conversation-messages ) ]-text
                                         exp = `*numero di ordine*propose_plan*` ).
  ENDMETHOD.

  METHOD no_pending_plan_raises.
    TRY.
        /reg/cl_ams_agent=>apply_decision(
          is_conversation = VALUE #( messages = VALUE #( ( role = /reg/if_ams_llm=>c_role-user text = `x` ) ) )
          iv_decision     = /reg/cl_ams_agent=>c_decision-confirm ).
        cl_abap_unit_assert=>fail( `atteso errore senza piano in attesa` ).
      CATCH /reg/cx_ams ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD plan_answered_twice_raises.
    /reg/cl_ams_agent=>apply_decision( EXPORTING is_conversation = waiting_conversation( )
                                                 iv_decision     = /reg/cl_ams_agent=>c_decision-confirm
                                       IMPORTING es_conversation = DATA(ls_conversation) ).
    TRY.
        /reg/cl_ams_agent=>apply_decision( is_conversation = ls_conversation
                                           iv_decision     = /reg/cl_ams_agent=>c_decision-confirm ).
        cl_abap_unit_assert=>fail( `una seconda conferma dello stesso piano non deve passare` ).
      CATCH /reg/cx_ams ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.

  METHOD counts_plan_steps.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_agent=>plan_step_count( c_plan ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_agent=>plan_step_count( `` ) exp = 0 ).
  ENDMETHOD.

  METHOD report.
    DATA(ls_context) = ms_context.
    ls_context-phase                    = iv_phase.
    ls_context-plan_steps               = 2.
    ls_context-screenshot_after_changes = iv_screenshot.
    rs_outcome = /reg/cl_ams_agent=>handle_response(
      is_context  = ls_context
      is_response = VALUE #( stop_reason = /reg/if_ams_llm=>c_stop-tool_use
                             tool_calls  = VALUE #( ( id = `r1` name = `report` arguments = iv_args ) ) ) ).
  ENDMETHOD.

  METHOD report_partial_execution.
    DATA(ls_outcome) = report(
      iv_args       = `{"text":"Ticket 12345 aggiornato in parte.","steps":[` &&
                      `{"number":2,"applied":false,"detail":"campo risposta bloccato"},{"number":1,"applied":true}]}`
      iv_phase      = /reg/cl_ams_op=>c_phase-execute
      iv_screenshot = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-status exp = /reg/cl_ams_op=>c_status-done ).
    " Il consulente vede quali modifiche sono riuscite e quali no, in ordine di passo.
    cl_abap_unit_assert=>assert_char_cp( act = ls_outcome-result_text exp = `Ticket 12345 aggiornato in parte.*1 riuscite, 1 non riuscite*` ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_outcome-result_text
                                         exp = |*Passo 1: riuscito*Passo 2: NON riuscito - campo risposta bloccato*| ).
  ENDMETHOD.

  METHOD report_missing_step_refused.
    DATA(ls_outcome) = report( iv_args       = `{"text":"Fatto.","steps":[{"number":1,"applied":true}]}`
                               iv_phase      = /reg/cl_ams_op=>c_phase-execute
                               iv_screenshot = abap_true ).
    cl_abap_unit_assert=>assert_initial( ls_outcome-status ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-messages[ 1 ]-tool_call_id exp = `r1` ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_outcome-messages[ 1 ]-text exp = `*passi 2 del piano*` ).
  ENDMETHOD.

  METHOD report_needs_screenshot.
    DATA(ls_outcome) = report(
      iv_args       = `{"text":"Fatto.","steps":[{"number":1,"applied":true},{"number":2,"applied":true}]}`
      iv_phase      = /reg/cl_ams_op=>c_phase-execute
      iv_screenshot = abap_false ).
    cl_abap_unit_assert=>assert_initial( ls_outcome-status ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_outcome-messages[ 1 ]-text exp = `*screenshot*` ).
  ENDMETHOD.

  METHOD report_after_reading_only.
    " Un'istruzione di sola lettura si chiude senza esiti per passo ne' screenshot.
    DATA(ls_outcome) = report( iv_args       = `{"text":"Il ticket 12345 riguarda la stampa delle fatture."}`
                               iv_phase      = /reg/cl_ams_op=>c_phase-read
                               iv_screenshot = abap_false ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-status exp = /reg/cl_ams_op=>c_status-done ).
    cl_abap_unit_assert=>assert_equals( act = ls_outcome-result_text exp = `Il ticket 12345 riguarda la stampa delle fatture.` ).
  ENDMETHOD.

  METHOD log_has_consultant_and_cost.
    " Esecuzione con un account condiviso sul portale: il registro deve dire quale consulente ha agito.
    DATA lv_now TYPE timestampl VALUE '20261126120000'.
    DATA(ls_context) = ms_context.
    ls_context-phase      = /reg/cl_ams_op=>c_phase-execute.
    ls_context-plan_steps = 2.
    DATA(ls_response) = VALUE /reg/if_ams_llm=>ty_response(
      stop_reason   = /reg/if_ams_llm=>c_stop-tool_use
      input_tokens  = 1200
      output_tokens = 80
      tool_calls    = VALUE #( ( id = `c1` name = `browser_click` arguments = `{"element":"Salva","ref":"e2","plan_step":1}` )
                               ( id = `c2` name = `browser_click` arguments = `{"element":"Salva","ref":"e2"}` ) ) ).
    DATA(ls_outcome) = /reg/cl_ams_agent=>handle_response( is_context = ls_context is_response = ls_response ).

    DATA(lt_rows) = /reg/cl_ams_agent=>log_rows( is_op       = VALUE #( op_id = '0123456789ABCDEF0123456789ABCDEF'
                                                                          consultant = 'MROSSI' llm = 'OPENAI' )
                                                 iv_model    = `gpt-6.2-sol`
                                                 is_response = ls_response
                                                 is_outcome  = ls_outcome
                                                 iv_seq      = 10
                                                 iv_now      = lv_now ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_rows ) exp = 3 ).
    LOOP AT lt_rows INTO DATA(ls_row).
      cl_abap_unit_assert=>assert_equals( act = ls_row-created_by exp = 'MROSSI' msg = |Riga { ls_row-seq } senza consulente| ).
      cl_abap_unit_assert=>assert_equals( act = ls_row-seq exp = 9 + sy-tabix ).
    ENDLOOP.

    " Costo della chiamata al modello.
    DATA(ls_llm) = lt_rows[ kind = /reg/cl_ams_agent=>c_kind-llm ].
    cl_abap_unit_assert=>assert_equals( act = ls_llm-elem_name exp = `gpt-6.2-sol` ).
    cl_abap_unit_assert=>assert_equals( act = ls_llm-input_tokens exp = 1200 ).
    cl_abap_unit_assert=>assert_equals( act = ls_llm-output_tokens exp = 80 ).

    " Modifica in coda: elemento e passo del piano.
    DATA(ls_change) = lt_rows[ call_id = 'c1' ].
    cl_abap_unit_assert=>assert_equals( act = ls_change-status exp = /reg/cl_ams_agent=>c_step-queued ).
    cl_abap_unit_assert=>assert_equals( act = ls_change-elem_name exp = `Salva` ).
    cl_abap_unit_assert=>assert_equals( act = ls_change-plan_step exp = 1 ).

    " Modifica fuori piano: rifiutata, con il motivo nel registro.
    DATA(ls_refused) = lt_rows[ call_id = 'c2' ].
    cl_abap_unit_assert=>assert_equals( act = ls_refused-status exp = /reg/cl_ams_agent=>c_step-rejected ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_refused-outcome exp = `*fuori dal piano*` ).
  ENDMETHOD.

ENDCLASS.