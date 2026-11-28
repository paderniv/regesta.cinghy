"! Adattatore Google Gemini (Gemini Developer API, generateContent v1beta) per l'agente AMS.
"! Destinazione SM59 di tipo G verso generativelanguage.googleapis.com, porta 443, SSL attivo,
"! nessun prefisso di percorso. Chiave API nell'header x-goog-api-key.
"! Regole del fornitore rispettate qui:
"! - il turno del modello si rimanda tale e quale (provider_data), con le thoughtSignature;
"! - i risultati degli strumenti vanno in un solo turno user, nell'ordine delle chiamate, con id e name;
"! - non si mandano thinkingBudget, temperature e penalita' (rifiutati o ignorati dai modelli recenti).
CLASS /reg/cl_ams_llm_gemini DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES /reg/if_ams_llm.

    METHODS constructor
      IMPORTING is_llm TYPE /reg/cl_ams_cfg=>ty_llm.

    "! Corpo JSON della richiesta generateContent.
    METHODS build_request
      IMPORTING is_conversation TYPE /reg/if_ams_llm=>ty_conversation
                it_tools        TYPE /reg/if_ams_llm=>ty_tools
      RETURNING VALUE(rv_json)  TYPE string.

    "! Risposta di generateContent nel formato neutro.
    "! @raising /reg/cx_ams | Chiamata a strumento malformata o motivo di fine non gestibile
    METHODS parse_response
      IMPORTING iv_json            TYPE string
      RETURNING VALUE(rs_response) TYPE /reg/if_ams_llm=>ty_response
      RAISING   /reg/cx_ams.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! Limite di output di una chiamata REST non in streaming.
    CONSTANTS c_max_output_tokens TYPE i VALUE 32768.

    TYPES:
      BEGIN OF ty_function_call,
        id   TYPE string,
        name TYPE string,
        args TYPE /ui2/cl_json=>json,
      END OF ty_function_call,
      BEGIN OF ty_function_response,
        id       TYPE string,
        name     TYPE string,
        response TYPE /ui2/cl_json=>json,
      END OF ty_function_response,
      BEGIN OF ty_part,
        text              TYPE string,
        function_call     TYPE ty_function_call,
        function_response TYPE ty_function_response,
      END OF ty_part,
      ty_parts TYPE STANDARD TABLE OF ty_part WITH EMPTY KEY,
      BEGIN OF ty_content,
        role  TYPE string,
        parts TYPE /ui2/cl_json=>json,
      END OF ty_content,
      ty_contents TYPE STANDARD TABLE OF ty_content WITH EMPTY KEY,
      BEGIN OF ty_text_part,
        text TYPE string,
      END OF ty_text_part,
      BEGIN OF ty_system_instruction,
        parts TYPE STANDARD TABLE OF ty_text_part WITH EMPTY KEY,
      END OF ty_system_instruction,
      BEGIN OF ty_declaration,
        name                   TYPE string,
        description            TYPE string,
        parameters_json_schema TYPE /ui2/cl_json=>json,
      END OF ty_declaration,
      BEGIN OF ty_tool,
        function_declarations TYPE STANDARD TABLE OF ty_declaration WITH EMPTY KEY,
      END OF ty_tool,
      BEGIN OF ty_generation_config,
        max_output_tokens TYPE i,
      END OF ty_generation_config,
      BEGIN OF ty_request,
        system_instruction TYPE ty_system_instruction,
        contents           TYPE ty_contents,
        tools              TYPE STANDARD TABLE OF ty_tool WITH EMPTY KEY,
        generation_config  TYPE ty_generation_config,
      END OF ty_request,

      BEGIN OF ty_response_part,
        text          TYPE string,
        thought       TYPE abap_bool,
        function_call TYPE ty_function_call,
      END OF ty_response_part,
      ty_response_parts TYPE STANDARD TABLE OF ty_response_part WITH EMPTY KEY,
      BEGIN OF ty_candidate,
        BEGIN OF content,
          role  TYPE string,
          parts TYPE /ui2/cl_json=>json,
        END OF content,
        finish_reason  TYPE string,
        finish_message TYPE string,
      END OF ty_candidate,
      BEGIN OF ty_usage,
        prompt_token_count     TYPE i,
        candidates_token_count TYPE i,
        thoughts_token_count   TYPE i,
      END OF ty_usage,
      BEGIN OF ty_prompt_feedback,
        block_reason TYPE string,
      END OF ty_prompt_feedback,
      BEGIN OF ty_api_response,
        candidates      TYPE STANDARD TABLE OF ty_candidate WITH EMPTY KEY,
        usage_metadata  TYPE ty_usage,
        prompt_feedback TYPE ty_prompt_feedback,
      END OF ty_api_response,
      BEGIN OF ty_tool_output,
        content TYPE string,
        error   TYPE string,
      END OF ty_tool_output.

    DATA ms_llm TYPE /reg/cl_ams_cfg=>ty_llm.

    CLASS-METHODS to_json
      IMPORTING ig_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

ENDCLASS.


CLASS /reg/cl_ams_llm_gemini IMPLEMENTATION.

  METHOD constructor.
    ms_llm = is_llm.
  ENDMETHOD.

  METHOD /reg/if_ams_llm~complete.
    DATA(lv_body) = /reg/cl_ams_http=>post_json(
                      iv_destination = ms_llm-destination
                      iv_path        = |/v1beta/models/{ ms_llm-model }:generateContent|
                      it_headers     = VALUE #( ( name = `x-goog-api-key` value = /reg/cl_ams_key=>get( ms_llm-llm ) ) )
                      iv_body        = build_request( is_conversation = is_conversation it_tools = it_tools ) ).
    rs_response = parse_response( lv_body ).
  ENDMETHOD.

  METHOD build_request.
    DATA ls_request TYPE ty_request.
    DATA lt_pending TYPE ty_parts.

    IF is_conversation-system IS NOT INITIAL.
      ls_request-system_instruction-parts = VALUE #( ( text = is_conversation-system ) ).
    ENDIF.

    LOOP AT is_conversation-messages INTO DATA(ls_message).
      " I risultati consecutivi degli strumenti formano un solo turno user.
      IF ls_message-role <> /reg/if_ams_llm=>c_role-tool AND lt_pending IS NOT INITIAL.
        APPEND VALUE #( role = `user` parts = to_json( lt_pending ) ) TO ls_request-contents.
        CLEAR lt_pending.
      ENDIF.

      CASE ls_message-role.
        WHEN /reg/if_ams_llm=>c_role-user.
          APPEND VALUE #( role  = `user`
                          parts = to_json( VALUE ty_parts( ( text = ls_message-text ) ) ) ) TO ls_request-contents.

        WHEN /reg/if_ams_llm=>c_role-assistant.
          IF ls_message-provider_data IS NOT INITIAL.
            APPEND VALUE #( role = `model` parts = ls_message-provider_data ) TO ls_request-contents.
          ELSE.
            DATA(lt_model_parts) = VALUE ty_parts( ).
            IF ls_message-text IS NOT INITIAL.
              APPEND VALUE #( text = ls_message-text ) TO lt_model_parts.
            ENDIF.
            LOOP AT ls_message-tool_calls INTO DATA(ls_call).
              APPEND VALUE #( function_call = VALUE #( id   = ls_call-id
                                                       name = ls_call-name
                                                       args = COND #( WHEN ls_call-arguments IS INITIAL THEN `{}`
                                                                      ELSE ls_call-arguments ) ) ) TO lt_model_parts.
            ENDLOOP.
            APPEND VALUE #( role = `model` parts = to_json( lt_model_parts ) ) TO ls_request-contents.
          ENDIF.

        WHEN /reg/if_ams_llm=>c_role-tool.
          DATA(ls_output) = COND ty_tool_output( WHEN ls_message-is_error = abap_true
                                                 THEN VALUE #( error = ls_message-text )
                                                 ELSE VALUE #( content = ls_message-text ) ).
          APPEND VALUE #( function_response = VALUE #( id       = ls_message-tool_call_id
                                                       name     = ls_message-tool_name
                                                       response = to_json( ls_output ) ) ) TO lt_pending.
      ENDCASE.
    ENDLOOP.
    IF lt_pending IS NOT INITIAL.
      APPEND VALUE #( role = `user` parts = to_json( lt_pending ) ) TO ls_request-contents.
    ENDIF.

    IF it_tools IS NOT INITIAL.
      ls_request-tools = VALUE #( ( function_declarations = VALUE #(
                                      FOR ls_tool IN it_tools
                                      ( name                   = ls_tool-name
                                        description            = ls_tool-description
                                        parameters_json_schema = COND #( WHEN ls_tool-parameters IS INITIAL
                                                                         THEN `{"type":"object","properties":{}}`
                                                                         ELSE ls_tool-parameters ) ) ) ) ).
    ENDIF.

    ls_request-generation_config-max_output_tokens = COND #(
      WHEN ms_llm-max_output_tokens > 0 AND ms_llm-max_output_tokens <= c_max_output_tokens THEN ms_llm-max_output_tokens
      ELSE c_max_output_tokens ).

    rv_json = to_json( ls_request ).
  ENDMETHOD.

  METHOD parse_response.
    DATA ls_api TYPE ty_api_response.
    DATA lt_parts TYPE ty_response_parts.

    /ui2/cl_json=>deserialize( EXPORTING json        = iv_json
                                         pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                               CHANGING  data        = ls_api ).

    rs_response-input_tokens  = ls_api-usage_metadata-prompt_token_count.
    rs_response-output_tokens = ls_api-usage_metadata-candidates_token_count
                              + ls_api-usage_metadata-thoughts_token_count.

    IF ls_api-candidates IS INITIAL.
      " Richiesta bloccata prima della generazione (promptFeedback.blockReason).
      rs_response-stop_reason = /reg/if_ams_llm=>c_stop-refused.
      rs_response-text        = ls_api-prompt_feedback-block_reason.
      RETURN.
    ENDIF.

    DATA(ls_candidate) = ls_api-candidates[ 1 ].
    rs_response-provider_data = ls_candidate-content-parts.
    /ui2/cl_json=>deserialize( EXPORTING json        = ls_candidate-content-parts
                                         pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                               CHANGING  data        = lt_parts ).

    LOOP AT lt_parts INTO DATA(ls_part).
      IF ls_part-function_call-name IS NOT INITIAL.
        APPEND VALUE #( id        = ls_part-function_call-id
                        name      = ls_part-function_call-name
                        arguments = COND #( WHEN ls_part-function_call-args IS INITIAL THEN `{}`
                                            ELSE ls_part-function_call-args ) ) TO rs_response-tool_calls.
      ELSEIF ls_part-thought = abap_false AND ls_part-text IS NOT INITIAL.
        rs_response-text = rs_response-text && ls_part-text.
      ENDIF.
    ENDLOOP.

    IF rs_response-tool_calls IS NOT INITIAL.
      rs_response-stop_reason = /reg/if_ams_llm=>c_stop-tool_use.
      RETURN.
    ENDIF.

    rs_response-stop_reason = SWITCH #( ls_candidate-finish_reason
      WHEN `STOP`       THEN /reg/if_ams_llm=>c_stop-end_turn
      WHEN `MAX_TOKENS` THEN /reg/if_ams_llm=>c_stop-max_tokens
      WHEN `SAFETY` OR `RECITATION` OR `BLOCKLIST` OR `PROHIBITED_CONTENT` OR `SPII` OR `LANGUAGE`
                        THEN /reg/if_ams_llm=>c_stop-refused ).
    IF rs_response-stop_reason IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams(
        text = |Gemini ({ ms_llm-model }): risposta terminata con { ls_candidate-finish_reason } { ls_candidate-finish_message }| ).
    ENDIF.
  ENDMETHOD.

  METHOD to_json.
    rv_json = /ui2/cl_json=>serialize( data        = ig_data
                                       compress    = abap_true
                                       pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
  ENDMETHOD.

ENDCLASS.
