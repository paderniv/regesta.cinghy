CLASS ltc_http_runner DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    CONSTANTS c_id TYPE string VALUE `0123456789ABCDEF0123456789abcdef`.
    METHODS routes FOR TESTING.
    METHODS rejects_unknown_paths FOR TESTING.
    METHODS actions_payload FOR TESTING.
    METHODS no_actions_is_empty_array FOR TESTING.
ENDCLASS.


CLASS ltc_http_runner IMPLEMENTATION.

  METHOD routes.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_runner=>route( iv_method = `POST` iv_path = `/pair` )-endpoint
                                        exp = /reg/cl_ams_http_runner=>c_endpoint-pair ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_runner=>route( iv_method = `GET` iv_path = `/actions` )-endpoint
                                        exp = /reg/cl_ams_http_runner=>c_endpoint-actions ).
    DATA(ls_result) = /reg/cl_ams_http_runner=>route( iv_method = `POST` iv_path = |/actions/{ c_id }/result| ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-endpoint exp = /reg/cl_ams_http_runner=>c_endpoint-result ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-step_id exp = CONV sysuuid_x16( to_upper( c_id ) ) ).
  ENDMETHOD.

  METHOD rejects_unknown_paths.
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_runner=>route( iv_method = `GET` iv_path = `/pair` )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_runner=>route( iv_method = `POST` iv_path = `/actions` )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_runner=>route( iv_method = `POST` iv_path = `/actions/123/result` )-endpoint ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_http_runner=>route( iv_method = `GET` iv_path = |/actions/{ c_id }/result| )-endpoint ).
  ENDMETHOD.

  METHOD actions_payload.
    DATA(lv_json) = /reg/cl_ams_http_runner=>actions_json( VALUE #(
      ( step_id = CONV sysuuid_x16( to_upper( c_id ) ) op_id = CONV sysuuid_x16( to_upper( c_id ) )
        tool = `browser_click` args = `{"element":"Cerca","ref":"e4"}`
        allowed_domains = VALUE #( ( `hdserver.pittini.it` ) ( `login.microsoftonline.com` ) )
        login_domains   = VALUE #( ( `login.microsoftonline.com` ) ) ) ) ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = |*"stepId":"{ to_upper( c_id ) }"*| ).
    " Gli argomenti arrivano al runner come oggetto JSON, pronti per Playwright MCP.
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = `*"args":{"element":"Cerca","ref":"e4"}*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = `*"allowedDomains":["hdserver.pittini.it","login.microsoftonline.com"]*` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_json exp = `*"loginDomains":["login.microsoftonline.com"]*` ).
  ENDMETHOD.

  METHOD no_actions_is_empty_array.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_http_runner=>actions_json( VALUE #( ) ) exp = `[]` ).
  ENDMETHOD.

ENDCLASS.