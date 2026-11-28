CLASS ltc_openai DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO /reg/cl_ams_llm_openai.
    METHODS setup.
    METHODS assert_contains
      IMPORTING iv_json TYPE string
                iv_part TYPE string.
    METHODS request_replays_items FOR TESTING.
    METHODS request_rebuilds_calls FOR TESTING.
    METHODS request_tools_and_settings FOR TESTING.
    METHODS response_tool_call FOR TESTING RAISING cx_static_check.
    METHODS response_text FOR TESTING RAISING cx_static_check.
    METHODS response_incomplete FOR TESTING RAISING cx_static_check.
    METHODS response_refusal FOR TESTING RAISING cx_static_check.
    METHODS response_failed_raises FOR TESTING.
ENDCLASS.


CLASS ltc_openai IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( VALUE #( llm = `OPENAI` provider = `OPENAI` model = `gpt-6.2-sol` destination = `CINGHY_OPENAI` ) ).
  ENDMETHOD.

  METHOD assert_contains.
    cl_abap_unit_assert=>assert_true( act = xsdbool( find( val = iv_json sub = iv_part ) >= 0 )
                                      msg = |Manca { iv_part } in { iv_json }| ).
  ENDMETHOD.

  METHOD request_replays_items.
    DATA(lv_json) = mo_cut->build_request(
      is_conversation = VALUE #(
        system   = `regole`
        messages = VALUE #(
          ( role = /reg/if_ams_llm=>c_role-user text = `leggi il ticket` )
          ( role = /reg/if_ams_llm=>c_role-assistant
            provider_data = `[{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"ENC"},` &&
                            `{"type":"function_call","id":"fc_1","call_id":"call_1","name":"browser_navigate","arguments":"{\"url\":\"u\"}","status":"completed"}]` )
          ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `call_1` tool_name = `browser_navigate` text = `pagina` ) ) )
      it_tools        = VALUE #( ) ).
    assert_contains( iv_json = lv_json iv_part = `"input":[{"role":"developer","content":"regole"},{"role":"user","content":"leggi il ticket"},` ).
    " Item del modello rimandati tali e quali e nello stesso ordine, ragionamento cifrato compreso.
    assert_contains( iv_json = lv_json
                     iv_part = `{"type":"reasoning","id":"rs_1","summary":[],"encrypted_content":"ENC"},{"type":"function_call","id":"fc_1",` ).
    assert_contains( iv_json = lv_json iv_part = `{"type":"function_call_output","call_id":"call_1","output":"pagina"}]` ).
  ENDMETHOD.

  METHOD request_rebuilds_calls.
    DATA(lv_json) = mo_cut->build_request(
      is_conversation = VALUE #( messages = VALUE #(
        ( role = /reg/if_ams_llm=>c_role-assistant
          tool_calls = VALUE #( ( id = `call_7` name = `browser_click` arguments = `{"element":"Cerca"}` ) ) )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `call_7` text = `non trovato` is_error = abap_true ) ) )
      it_tools        = VALUE #( ) ).
    assert_contains( iv_json = lv_json
                     iv_part = `{"type":"function_call","call_id":"call_7","name":"browser_click","arguments":"{\"element\":\"Cerca\"}"}` ).
    assert_contains( iv_json = lv_json iv_part = `"output":"ERRORE: non trovato"` ).
  ENDMETHOD.

  METHOD request_tools_and_settings.
    DATA(lv_json) = mo_cut->build_request(
      is_conversation = VALUE #( messages = VALUE #( ( role = /reg/if_ams_llm=>c_role-user text = `ciao` ) ) )
      it_tools        = VALUE #( ( name = `browser_navigate` description = `Apre un indirizzo`
                                   parameters = `{"type":"object","properties":{"name":{"type":"string"}}}` ) ) ).
    assert_contains( iv_json = lv_json iv_part = `{"model":"gpt-6.2-sol","store":false,"include":["reasoning.encrypted_content"],"max_output_tokens":32000,` ).
    assert_contains( iv_json = lv_json
                     iv_part = `"tools":[{"type":"function","name":"browser_navigate","description":"Apre un indirizzo",` &&
                               `"parameters":{"type":"object","properties":{"name":{"type":"string"}}},"strict":false}]` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_json sub = `temperature` ) exp = -1 ).
  ENDMETHOD.

  METHOD response_tool_call.
    DATA(ls_response) = mo_cut->parse_response(
      `{"id":"resp_1","object":"response","status":"completed","model":"gpt-6.2-sol","output":[` &&
      `{"type":"reasoning","id":"rs_abc","summary":[],"encrypted_content":"gAAAA"},` &&
      `{"type":"function_call","id":"fc_123","call_id":"call_123","name":"browser_click","arguments":"{\"element\":\"Cerca\"}","status":"completed"}],` &&
      `"usage":{"input_tokens":812,"input_tokens_details":{"cached_tokens":0},"output_tokens":95,` &&
      `"output_tokens_details":{"reasoning_tokens":64},"total_tokens":907}}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-tool_use ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-tool_calls[ 1 ]-id exp = `call_123` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-tool_calls[ 1 ]-name exp = `browser_click` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-tool_calls[ 1 ]-arguments exp = `{"element":"Cerca"}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-input_tokens exp = 812 ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-output_tokens exp = 95 ).
    assert_contains( iv_json = ls_response-provider_data iv_part = `"encrypted_content":"gAAAA"` ).
  ENDMETHOD.

  METHOD response_text.
    DATA(ls_response) = mo_cut->parse_response(
      `{"id":"resp_2","status":"completed","output":[{"type":"reasoning","id":"rs_def","summary":[],"encrypted_content":"x"},` &&
      `{"type":"message","id":"msg_1","role":"assistant","status":"completed",` &&
      `"content":[{"type":"output_text","text":"Ticket 42 aperto.","annotations":[]}]}],` &&
      `"usage":{"input_tokens":10,"output_tokens":5}}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-end_turn ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-text exp = `Ticket 42 aperto.` ).
  ENDMETHOD.

  METHOD response_incomplete.
    DATA(ls_response) = mo_cut->parse_response(
      `{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-max_tokens ).
  ENDMETHOD.

  METHOD response_refusal.
    DATA(ls_response) = mo_cut->parse_response(
      `{"status":"completed","output":[{"type":"message","role":"assistant",` &&
      `"content":[{"type":"refusal","refusal":"Non posso aiutare."}]}]}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-refused ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-text exp = `Non posso aiutare.` ).
  ENDMETHOD.

  METHOD response_failed_raises.
    TRY.
        mo_cut->parse_response( `{"status":"failed","error":{"code":"server_error","message":"guasto"},"output":[]}` ).
        cl_abap_unit_assert=>fail( `atteso errore per status failed` ).
      CATCH /reg/cx_ams INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( ) exp = `*guasto*` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
