CLASS ltc_tools DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS c_read TYPE /reg/ams_op-phase VALUE 'R'.
    CONSTANTS c_exec TYPE /reg/ams_op-phase VALUE 'E'.
    DATA mt_domains TYPE string_table.
    DATA mt_forbidden TYPE string_table.
    DATA mt_safe TYPE string_table.
    DATA mv_snapshot TYPE string.
    METHODS setup.
    METHODS run
      IMPORTING iv_tool            TYPE string
                iv_args            TYPE string
                iv_phase           TYPE /reg/ams_op-phase
                iv_plan_steps      TYPE i DEFAULT 0
      RETURNING VALUE(rs_decision) TYPE /reg/cl_ams_tools=>ty_decision.
    METHODS reading_tools_always_allowed FOR TESTING.
    METHODS navigate_only_profile_domains FOR TESTING.
    METHODS read_click_link_and_safe_btn FOR TESTING.
    METHODS read_click_unsafe_btn_refused FOR TESTING.
    METHODS read_type_only_in_search FOR TESTING.
    METHODS model_cannot_rename_element FOR TESTING.
    METHODS unknown_ref_refused FOR TESTING.
    METHODS exec_needs_valid_plan_step FOR TESTING.
    METHODS exec_read_actions_free FOR TESTING.
    METHODS unknown_tool_refused FOR TESTING.
    METHODS forbidden_refused_any_phase FOR TESTING.
    METHODS definitions_are_valid_json FOR TESTING.
ENDCLASS.


CLASS ltc_tools IMPLEMENTATION.

  METHOD setup.
    mt_domains = VALUE #( ( `hdserver.pittini.it` ) ( `login.microsoftonline.com` ) ).
    mt_safe    = VALUE #( ( `Cerca` ) ).
    mt_forbidden = VALUE #( ( `Timer` ) ).
    " Snapshot di accessibilita' nel formato di Playwright.
    mv_snapshot = |- heading "Ticket 12345" [level=1] [ref=e1]\n| &&
                  |- link "Torna alla lista" [ref=e2] [cursor=pointer]\n| &&
                  |- textbox "Cerca ticket" [ref=e3]\n| &&
                  |- button "Cerca" [ref=e4]\n| &&
                  |- button "Salva" [ref=e5]\n| &&
                  |- textbox "Commento" [ref=e6]\n| &&
                  |- combobox "Priorita" [ref=e7]\n| &&
                  |- row "12345 Stampa bloccata" [ref=e8]\n| &&
                  |- searchbox [ref=e9]\n| &&
                  |- link "Timer" [ref=e10] [cursor=pointer]|.
  ENDMETHOD.

  METHOD run.
    rs_decision = /reg/cl_ams_tools=>check( is_call       = VALUE #( id = `c1` name = iv_tool arguments = iv_args )
                                            iv_phase      = iv_phase
                                            it_domains    = mt_domains
                                            it_safe       = mt_safe
                                            it_forbidden  = mt_forbidden
                                            iv_snapshot   = mv_snapshot
                                            iv_plan_steps = iv_plan_steps ).
  ENDMETHOD.

  METHOD reading_tools_always_allowed.
    cl_abap_unit_assert=>assert_true( run( iv_tool = `browser_snapshot` iv_args = `{}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_true( run( iv_tool = `browser_take_screenshot` iv_args = `{}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_true( run( iv_tool = `browser_navigate_back` iv_args = `{}` iv_phase = c_read )-allowed ).
  ENDMETHOD.

  METHOD navigate_only_profile_domains.
    cl_abap_unit_assert=>assert_true(
      run( iv_tool = `browser_navigate` iv_args = `{"url":"https://HDSERVER.pittini.it/ticket/12345"}` iv_phase = c_read )-allowed ).
    DATA(ls_out) = run( iv_tool = `browser_navigate` iv_args = `{"url":"https://evil.example/steal"}` iv_phase = c_read ).
    cl_abap_unit_assert=>assert_false( ls_out-allowed ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_out-reason exp = `*fuori dai domini*` ).
    " Un dominio consentito messo nel percorso non inganna il controllo.
    cl_abap_unit_assert=>assert_false(
      run( iv_tool = `browser_navigate` iv_args = `{"url":"https://evil.example/hdserver.pittini.it"}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_false(
      run( iv_tool = `browser_navigate` iv_args = `{"url":"javascript:alert(1)"}` iv_phase = c_read )-allowed ).
  ENDMETHOD.

  METHOD read_click_link_and_safe_btn.
    cl_abap_unit_assert=>assert_true( run( iv_tool = `browser_click` iv_args = `{"element":"lista","ref":"e2"}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_true( run( iv_tool = `browser_click` iv_args = `{"element":"riga","ref":"e8"}` iv_phase = c_read )-allowed ).
    DATA(ls_out) = run( iv_tool = `browser_click` iv_args = `{"element":"Cerca","ref":"e4"}` iv_phase = c_read ).
    cl_abap_unit_assert=>assert_true( ls_out-allowed ).
    cl_abap_unit_assert=>assert_equals( act = ls_out-elem_role exp = `button` ).
    cl_abap_unit_assert=>assert_equals( act = ls_out-elem_name exp = `Cerca` ).
  ENDMETHOD.

  METHOD read_click_unsafe_btn_refused.
    DATA(ls_out) = run( iv_tool = `browser_click` iv_args = `{"element":"Salva","ref":"e5"}` iv_phase = c_read ).
    cl_abap_unit_assert=>assert_false( ls_out-allowed ).
    cl_abap_unit_assert=>assert_false( ls_out-needs_confirmation ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_out-reason exp = `*proponi un piano*` ).
  ENDMETHOD.

  METHOD read_type_only_in_search.
    cl_abap_unit_assert=>assert_true(
      run( iv_tool = `browser_type` iv_args = `{"element":"cerca","ref":"e3","text":"12345"}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_true(
      run( iv_tool = `browser_type` iv_args = `{"element":"ricerca","ref":"e9","text":"12345"}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_false(
      run( iv_tool = `browser_type` iv_args = `{"element":"commento","ref":"e6","text":"ciao"}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_false(
      run( iv_tool = `browser_select_option` iv_args = `{"element":"priorita","ref":"e7","values":["P2"]}` iv_phase = c_read )-allowed ).
    cl_abap_unit_assert=>assert_false( run( iv_tool = `browser_press_key` iv_args = `{"key":"Enter"}` iv_phase = c_read )-allowed ).
  ENDMETHOD.

  METHOD model_cannot_rename_element.
    " Il modello chiama "Cerca" il pulsante Salva: conta il nome nella pagina, non la descrizione.
    DATA(ls_out) = run( iv_tool = `browser_click` iv_args = `{"element":"Cerca","ref":"e5"}` iv_phase = c_read ).
    cl_abap_unit_assert=>assert_false( ls_out-allowed ).
    cl_abap_unit_assert=>assert_equals( act = ls_out-elem_name exp = `Salva` ).
  ENDMETHOD.

  METHOD unknown_ref_refused.
    DATA(ls_out) = run( iv_tool = `browser_click` iv_args = `{"element":"x","ref":"e99"}` iv_phase = c_exec iv_plan_steps = 3 ).
    cl_abap_unit_assert=>assert_false( ls_out-allowed ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_out-reason exp = `*rileggi la pagina*` ).
    " Un ref che prova a iniettare una regex non trova nulla.
    cl_abap_unit_assert=>assert_false(
      run( iv_tool = `browser_click` iv_args = `{"element":"x","ref":"e5]|.*"}` iv_phase = c_exec iv_plan_steps = 3 )-allowed ).
  ENDMETHOD.

  METHOD exec_needs_valid_plan_step.
    DATA(ls_ok) = run( iv_tool = `browser_click` iv_args = `{"element":"Salva","ref":"e5","plan_step":2}` iv_phase = c_exec iv_plan_steps = 3 ).
    cl_abap_unit_assert=>assert_true( ls_ok-allowed ).
    cl_abap_unit_assert=>assert_true( ls_ok-modifies ).
    cl_abap_unit_assert=>assert_equals( act = ls_ok-plan_step exp = 2 ).

    DATA(ls_missing) = run( iv_tool = `browser_click` iv_args = `{"element":"Salva","ref":"e5"}` iv_phase = c_exec iv_plan_steps = 3 ).
    cl_abap_unit_assert=>assert_false( ls_missing-allowed ).
    cl_abap_unit_assert=>assert_true( ls_missing-needs_confirmation ).

    cl_abap_unit_assert=>assert_true(
      run( iv_tool = `browser_click` iv_args = `{"element":"Salva","ref":"e5","plan_step":4}` iv_phase = c_exec iv_plan_steps = 3 )-needs_confirmation ).
    cl_abap_unit_assert=>assert_true(
      run( iv_tool = `browser_select_option` iv_args = `{"element":"p","ref":"e7","values":["P2"],"plan_step":1}` iv_phase = c_exec iv_plan_steps = 3 )-allowed ).
  ENDMETHOD.

  METHOD exec_read_actions_free.
    " La verifica finale legge senza indicare un passo del piano.
    DATA(ls_out) = run( iv_tool = `browser_click` iv_args = `{"element":"lista","ref":"e2"}` iv_phase = c_exec iv_plan_steps = 3 ).
    cl_abap_unit_assert=>assert_true( ls_out-allowed ).
    cl_abap_unit_assert=>assert_false( ls_out-modifies ).
  ENDMETHOD.

  METHOD unknown_tool_refused.
    cl_abap_unit_assert=>assert_false( run( iv_tool = `browser_evaluate` iv_args = `{"function":"x"}` iv_phase = c_exec iv_plan_steps = 3 )-allowed ).
  ENDMETHOD.

  METHOD forbidden_refused_any_phase.
    " Timer e' un link, quindi cliccabile in lettura, ma il profilo lo vieta; anche in esecuzione con passo valido.
    DATA(ls_read) = run( iv_tool = `browser_click` iv_args = `{"element":"Timer","ref":"e10"}` iv_phase = c_read ).
    cl_abap_unit_assert=>assert_false( ls_read-allowed ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_read-reason exp = `*vietato*` ).
    cl_abap_unit_assert=>assert_false(
      run( iv_tool = `browser_click` iv_args = `{"element":"Timer","ref":"e10","plan_step":1}` iv_phase = c_exec iv_plan_steps = 3 )-allowed ).
  ENDMETHOD.

  METHOD definitions_are_valid_json.
    DATA lr_schema TYPE REF TO data.
    LOOP AT /reg/cl_ams_tools=>definitions( ) INTO DATA(ls_tool).
      CLEAR lr_schema.
      lr_schema = /ui2/cl_json=>generate( json = ls_tool-parameters ).
      cl_abap_unit_assert=>assert_bound( act = lr_schema msg = |Schema non valido per { ls_tool-name }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.