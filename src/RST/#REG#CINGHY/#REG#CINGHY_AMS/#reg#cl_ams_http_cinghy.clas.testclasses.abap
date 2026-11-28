CLASS ltc_http DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS c_id TYPE string VALUE `0123456789abcdef0123456789ABCDEF`.
    DATA ms_cfg TYPE /reg/cl_ams_cfg=>ty_app_config.
    METHODS setup.
    METHODS routes_operations FOR TESTING.
    METHODS routes_runners FOR TESTING.
    METHODS rejects_unknown_paths FOR TESTING.
    METHODS portal_from_instruction FOR TESTING.
    METHODS portal_not_configured FOR TESTING.
    METHODS portal_ambiguous FOR TESTING.
    METHODS portal_given_explicitly FOR TESTING.
    METHODS status_json_for_panel FOR TESTING.
ENDCLASS.


CLASS ltc_http IMPLEMENTATION.

  METHOD setup.
    ms_cfg = VALUE #( portals = VALUE #( ( portal = `PITTINI` customer = `Pittini` active = abap_true )
                                         ( portal = `ACME` customer = `Acme Spa` active = abap_true )
                                         ( portal = `SPENTO` customer = `Cliente spento` active = abap_false ) ) ).
  ENDMETHOD.

  METHOD routes_operations.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = `/operations` )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-start ).
    DATA(ls_status) = /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = |/operations/{ c_id }| ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-endpoint exp = /reg/cl_ams_http_cinghy=>c_endpoint-status ).
    cl_abap_unit_assert=>assert_equals( act = ls_status-op_id exp = CONV sysuuid_x16( to_upper( c_id ) ) ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = |/operations/{ c_id }/decision| )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-decision ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = |/operations/{ c_id }/stop/| )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-stop ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = |/operations/{ c_id }/login-done| )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-login_done ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = |/operations/{ c_id }/screenshot| )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-screenshot ).
  ENDMETHOD.

  METHOD routes_runners.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = `/runners/pairing-code` )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-pairing ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = `/runners/me` )-endpoint
                                        exp = /reg/cl_ams_http_cinghy=>c_endpoint-runner ).
  ENDMETHOD.

  METHOD rejects_unknown_paths.
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = `/operations` )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = `/operations/12345` )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = |/operations/{ c_id }/stop| )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = |/operations/{ c_id }/delete| )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `POST` iv_path = |/operations/{ c_id }/screenshot| )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = `/runners/pairing-code` )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_cinghy=>route( iv_method = `GET` iv_path = `/` )-endpoint ).
  ENDMETHOD.

  METHOD portal_from_instruction.
    DATA(ls_choice) = /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `pittini: leggi il ticket 12345` ).
    cl_abap_unit_assert=>assert_equals( act = ls_choice-portal exp = `PITTINI` ).
    cl_abap_unit_assert=>assert_initial( ls_choice-error ).
    " Anche con il nome del cliente.
    cl_abap_unit_assert=>assert_equals(
      act = /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `Sul portale di Acme Spa chiudi il 7` )-portal
      exp = `ACME` ).
  ENDMETHOD.

  METHOD portal_not_configured.
    DATA(ls_choice) = /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `Beta: leggi il ticket 9` ).
    cl_abap_unit_assert=>assert_initial( ls_choice-portal ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_choice-error exp = `*PITTINI, ACME*` ).
    " Un portale disattivato non si usa anche se citato.
    cl_abap_unit_assert=>assert_initial(
      /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `Cliente spento: ticket 1` )-portal ).
  ENDMETHOD.

  METHOD portal_ambiguous.
    DATA(ls_choice) = /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `Confronta Pittini e Acme` ).
    cl_abap_unit_assert=>assert_initial( ls_choice-portal ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_choice-error exp = `Su quale portale*` ).
  ENDMETHOD.

  METHOD portal_given_explicitly.
    cl_abap_unit_assert=>assert_equals(
      act = /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `leggi il 12345` iv_portal = `acme` )-portal
      exp = `ACME` ).
    cl_abap_unit_assert=>assert_not_initial(
      /reg/cl_ams_http_cinghy=>resolve_portal( is_cfg = ms_cfg iv_instruction = `x` iv_portal = `SPENTO` )-error ).
  ENDMETHOD.

  METHOD status_json_for_panel.
    DATA(lv_json) = /reg/cl_ams_http_cinghy=>status_json(
      VALUE #( op_id = CONV sysuuid_x16( to_upper( c_id ) ) status = 'PLAN_WAIT' phase = 'R' portal = 'PITTINI' llm = 'GEMINI'
               progress = 'Piano pronto' plan_json = `{"steps":[{"number":1,"change":"P2"}]}` steps = 3
               input_tokens = 900 output_tokens = 70 ) ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = |*"opId":"{ to_upper( c_id ) }"*| ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = `*"status":"PLAN_WAIT"*` ).
    " Il piano arriva come oggetto JSON, non come stringa.
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = `*"plan":{"steps":[{"number":1,"change":"P2"}]}*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = `*"inputTokens":900*` ).
  ENDMETHOD.

ENDCLASS.