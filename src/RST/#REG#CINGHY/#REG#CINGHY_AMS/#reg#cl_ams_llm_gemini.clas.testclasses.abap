CLASS ltc_gemini DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO /reg/cl_ams_llm_gemini.
    METHODS setup.
    METHODS assert_contains
      IMPORTING iv_json TYPE string
                iv_part TYPE string.
    METHODS request_replays_signature FOR TESTING.
    METHODS request_groups_tool_results FOR TESTING.
    METHODS request_tools_and_limits FOR TESTING.
    METHODS response_tool_call FOR TESTING RAISING cx_static_check.
    METHODS response_text_skips_thoughts FOR TESTING RAISING cx_static_check.
    METHODS response_max_tokens FOR TESTING RAISING cx_static_check.
    METHODS response_blocked_prompt FOR TESTING RAISING cx_static_check.
    METHODS response_malformed_raises FOR TESTING.
    METHODS conversation
      RETURNING VALUE(rs_conversation) TYPE /reg/if_ams_llm=>ty_conversation.
ENDCLASS.


CLASS ltc_gemini IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( VALUE #( llm = `GEMINI` provider = `GEMINI` model = `gemini-4-carbon`
                             destination = `CINGHY_GEMINI` max_output_tokens = 16000 ) ).
  ENDMETHOD.

  METHOD assert_contains.
    cl_abap_unit_assert=>assert_true( act = xsdbool( find( val = iv_json sub = iv_part ) >= 0 )
                                      msg = |Manca { iv_part } in { iv_json }| ).
  ENDMETHOD.

  METHOD conversation.
    rs_conversation = VALUE #(
      system   = `regole`
      messages = VALUE #(
        ( role = /reg/if_ams_llm=>c_role-user text = `leggi il ticket` )
        ( role = /reg/if_ams_llm=>c_role-assistant
          provider_data = `[{"functionCall":{"id":"c1","name":"browser_navigate","args":{"url":"u"}},"thoughtSignature":"SIG1"},` &&
                          `{"functionCall":{"id":"c2","name":"browser_click","args":{"element":"x"}}}]`
          tool_calls = VALUE #( ( id = `c1` name = `browser_navigate` arguments = `{"url":"u"}` )
                                ( id = `c2` name = `browser_click` arguments = `{"element":"x"}` ) ) )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `c1` tool_name = `browser_navigate` text = `pagina` )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `c2` tool_name = `browser_click` text = `boom` is_error = abap_true )
        ( role = /reg/if_ams_llm=>c_role-assistant
          tool_calls = VALUE #( ( id = `c3` name = `report` ) ) ) ) ).
  ENDMETHOD.

  METHOD request_replays_signature.
    DATA(lv_json) = mo_cut->build_request( is_conversation = conversation( ) it_tools = VALUE #( ) ).
    assert_contains( iv_json = lv_json iv_part = `"systemInstruction":{"parts":[{"text":"regole"}]}` ).
    assert_contains( iv_json = lv_json iv_part = `{"role":"user","parts":[{"text":"leggi il ticket"}]}` ).
    " Turno del modello rimandato tale e quale, con la firma.
    assert_contains( iv_json = lv_json
                     iv_part = `{"role":"model","parts":[{"functionCall":{"id":"c1","name":"browser_navigate","args":{"url":"u"}},"thoughtSignature":"SIG1"},` ).
    " Senza provider_data il turno si ricostruisce, con argomenti vuoti come oggetto.
    assert_contains( iv_json = lv_json
                     iv_part = `{"role":"model","parts":[{"functionCall":{"id":"c3","name":"report","args":{}}}]}` ).
  ENDMETHOD.

  METHOD request_groups_tool_results.
    DATA(lv_json) = mo_cut->build_request( is_conversation = conversation( ) it_tools = VALUE #( ) ).
    assert_contains( iv_json = lv_json
                     iv_part = `{"role":"user","parts":[` &&
                               `{"functionResponse":{"id":"c1","name":"browser_navigate","response":{"content":"pagina"}}},` &&
                               `{"functionResponse":{"id":"c2","name":"browser_click","response":{"error":"boom"}}}]}` ).
  ENDMETHOD.

  METHOD request_tools_and_limits.
    DATA(lv_json) = mo_cut->build_request(
      is_conversation = VALUE #( messages = VALUE #( ( role = /reg/if_ams_llm=>c_role-user text = `ciao` ) ) )
      it_tools        = VALUE #( ( name = `browser_navigate` description = `Apre un indirizzo`
                                   parameters = `{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}` ) ) ).
    assert_contains( iv_json = lv_json
                     iv_part = `"tools":[{"functionDeclarations":[{"name":"browser_navigate","description":"Apre un indirizzo",` &&
                               `"parametersJsonSchema":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}}]}]` ).
    assert_contains( iv_json = lv_json iv_part = `"generationConfig":{"maxOutputTokens":16000}` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_json sub = `temperature` ) exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_json sub = `thinkingBudget` ) exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = lv_json sub = `systemInstruction` ) exp = -1 ).
  ENDMETHOD.

  METHOD response_tool_call.
    DATA(ls_response) = mo_cut->parse_response(
      `{"candidates":[{"content":{"role":"model","parts":[` &&
      `{"functionCall":{"id":"c9","name":"browser_click","args":{"element":"Cerca"}},"thoughtSignature":"SIG9"}]},` &&
      `"finishReason":"STOP","index":0}],` &&
      `"usageMetadata":{"promptTokenCount":120,"candidatesTokenCount":18,"thoughtsTokenCount":95,"totalTokenCount":233},` &&
      `"modelVersion":"gemini-4-carbon"}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-tool_use ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_response-tool_calls ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-tool_calls[ 1 ]-id exp = `c9` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-tool_calls[ 1 ]-name exp = `browser_click` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-tool_calls[ 1 ]-arguments exp = `{"element":"Cerca"}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-input_tokens exp = 120 ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-output_tokens exp = 113 ).
    assert_contains( iv_json = ls_response-provider_data iv_part = `"thoughtSignature":"SIG9"` ).
  ENDMETHOD.

  METHOD response_text_skips_thoughts.
    DATA(ls_response) = mo_cut->parse_response(
      `{"candidates":[{"content":{"role":"model","parts":[{"text":"sto pensando","thought":true},` &&
      `{"text":"Ticket 42 aperto.","thoughtSignature":"S"}]},"finishReason":"STOP"}],` &&
      `"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-end_turn ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-text exp = `Ticket 42 aperto.` ).
    cl_abap_unit_assert=>assert_initial( ls_response-tool_calls ).
  ENDMETHOD.

  METHOD response_max_tokens.
    DATA(ls_response) = mo_cut->parse_response(
      `{"candidates":[{"content":{"role":"model","parts":[{"text":"tronc"}]},"finishReason":"MAX_TOKENS"}]}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-max_tokens ).
  ENDMETHOD.

  METHOD response_blocked_prompt.
    DATA(ls_response) = mo_cut->parse_response( `{"promptFeedback":{"blockReason":"SAFETY"}}` ).
    cl_abap_unit_assert=>assert_equals( act = ls_response-stop_reason exp = /reg/if_ams_llm=>c_stop-refused ).
  ENDMETHOD.

  METHOD response_malformed_raises.
    TRY.
        mo_cut->parse_response(
          `{"candidates":[{"content":{"role":"model","parts":[]},"finishReason":"MALFORMED_FUNCTION_CALL"}]}` ).
        cl_abap_unit_assert=>fail( `atteso errore per MALFORMED_FUNCTION_CALL` ).
      CATCH /reg/cx_ams INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( ) exp = `*MALFORMED_FUNCTION_CALL*` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
