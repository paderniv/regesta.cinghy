"! Adattatore OpenAI (Responses API, POST /v1/responses) per l'agente AMS.
"! Destinazione SM59 di tipo G verso api.openai.com, porta 443, SSL attivo, nessun prefisso di
"! percorso. Chiave API nell'header Authorization: Bearer.
"! Regole del fornitore rispettate qui:
"! - store=false: la conversazione la teniamo noi e la rimandiamo intera a ogni chiamata;
"! - gli item restituiti dal modello (reasoning cifrato, function_call, message) tornano in input
"!   tali e quali e nello stesso ordine (provider_data), poi i function_call_output;
"! - il prompt di sistema e' il primo item, con ruolo developer, perche' resti in cache;
"! - non si mandano temperature e top_p.
CLASS /reg/cl_ams_llm_openai DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES /reg/if_ams_llm.

    METHODS constructor
      IMPORTING is_llm TYPE /reg/cl_ams_cfg=>ty_llm.

    "! Corpo JSON della richiesta a /v1/responses.
    METHODS build_request
      IMPORTING is_conversation TYPE /reg/if_ams_llm=>ty_conversation
                it_tools        TYPE /reg/if_ams_llm=>ty_tools
      RETURNING VALUE(rv_json)  TYPE string.

    "! Risposta di /v1/responses nel formato neutro.
    "! @raising /reg/cx_ams | Risposta fallita o in uno stato non gestibile
    METHODS parse_response
      IMPORTING iv_json            TYPE string
      RETURNING VALUE(rs_response) TYPE /reg/if_ams_llm=>ty_response
      RAISING   /reg/cx_ams.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! OpenAI consiglia di riservare almeno 25.000 token a ragionamento e risposta.
    CONSTANTS c_default_output_tokens TYPE i VALUE 32000.

    TYPES:
      BEGIN OF ty_message_item,
        role    TYPE string,
        content TYPE string,
      END OF ty_message_item,
      BEGIN OF ty_call_item,
        type      TYPE string,
        call_id   TYPE string,
        name      TYPE string,
        arguments TYPE string,
      END OF ty_call_item,
      BEGIN OF ty_output_item,
        type    TYPE string,
        call_id TYPE string,
        output  TYPE string,
      END OF ty_output_item,
      BEGIN OF ty_tool,
        type        TYPE string,
        name        TYPE string,
        description TYPE string,
        parameters  TYPE /ui2/cl_json=>json,
        strict      TYPE abap_bool,
      END OF ty_tool,
      ty_tools TYPE STANDARD TABLE OF ty_tool WITH EMPTY KEY,

      BEGIN OF ty_content_part,
        type    TYPE string,
        text    TYPE string,
        refusal TYPE string,
      END OF ty_content_part,
      BEGIN OF ty_response_item,
        type      TYPE string,
        call_id   TYPE string,
        name      TYPE string,
        arguments TYPE string,
        content   TYPE STANDARD TABLE OF ty_content_part WITH EMPTY KEY,
      END OF ty_response_item,
      ty_response_items TYPE STANDARD TABLE OF ty_response_item WITH EMPTY KEY,
      BEGIN OF ty_api_response,
        status TYPE string,
        BEGIN OF incomplete_details,
          reason TYPE string,
        END OF incomplete_details,
        BEGIN OF error,
          code    TYPE string,
          message TYPE string,
        END OF error,
        output TYPE /ui2/cl_json=>json,
        BEGIN OF usage,
          input_tokens  TYPE i,
          output_tokens TYPE i,
        END OF usage,
      END OF ty_api_response.

    DATA ms_llm TYPE /reg/cl_ams_cfg=>ty_llm.

    CLASS-METHODS to_json
      IMPORTING ig_data        TYPE any
      RETURNING VALUE(rv_json) TYPE string.

    "! Contenuto di un array JSON senza le parentesi quadre esterne; vuoto se l'array e' vuoto.
    CLASS-METHODS array_items
      IMPORTING iv_array        TYPE string
      RETURNING VALUE(rv_items) TYPE string.

ENDCLASS.


CLASS /reg/cl_ams_llm_openai IMPLEMENTATION.

  METHOD constructor.
    ms_llm = is_llm.
  ENDMETHOD.

  METHOD /reg/if_ams_llm~complete.
    DATA(lv_body) = /reg/cl_ams_http=>post_json(
                      iv_destination = ms_llm-destination
                      iv_path        = `/v1/responses`
                      it_headers     = VALUE #( ( name = `Authorization` value = |Bearer { /reg/cl_ams_key=>get( ms_llm-llm ) }| ) )
                      iv_body        = build_request( is_conversation = is_conversation it_tools = it_tools ) ).
    rs_response = parse_response( lv_body ).
  ENDMETHOD.

  METHOD build_request.
    DATA lt_items TYPE string_table.

    IF is_conversation-system IS NOT INITIAL.
      APPEND to_json( VALUE ty_message_item( role = `developer` content = is_conversation-system ) ) TO lt_items.
    ENDIF.

    LOOP AT is_conversation-messages INTO DATA(ls_message).
      CASE ls_message-role.
        WHEN /reg/if_ams_llm=>c_role-user.
          APPEND to_json( VALUE ty_message_item( role = `user` content = ls_message-text ) ) TO lt_items.

        WHEN /reg/if_ams_llm=>c_role-assistant.
          IF ls_message-provider_data IS NOT INITIAL.
            DATA(lv_replay) = array_items( ls_message-provider_data ).
            IF lv_replay IS NOT INITIAL.
              APPEND lv_replay TO lt_items.
            ENDIF.
          ELSE.
            IF ls_message-text IS NOT INITIAL.
              APPEND to_json( VALUE ty_message_item( role = `assistant` content = ls_message-text ) ) TO lt_items.
            ENDIF.
            LOOP AT ls_message-tool_calls INTO DATA(ls_call).
              APPEND to_json( VALUE ty_call_item( type      = `function_call`
                                                  call_id   = ls_call-id
                                                  name      = ls_call-name
                                                  arguments = COND #( WHEN ls_call-arguments IS INITIAL THEN `{}`
                                                                      ELSE ls_call-arguments ) ) ) TO lt_items.
            ENDLOOP.
          ENDIF.

        WHEN /reg/if_ams_llm=>c_role-tool.
          APPEND to_json( VALUE ty_output_item( type    = `function_call_output`
                                                call_id = ls_message-tool_call_id
                                                output  = COND #( WHEN ls_message-is_error = abap_true
                                                                  THEN |ERRORE: { ls_message-text }|
                                                                  ELSE ls_message-text ) ) ) TO lt_items.
      ENDCASE.
    ENDLOOP.

    DATA(lt_tools) = VALUE ty_tools( FOR ls_tool IN it_tools
                                     ( type        = `function`
                                       name        = ls_tool-name
                                       description = ls_tool-description
                                       parameters  = COND #( WHEN ls_tool-parameters IS INITIAL
                                                             THEN `{"type":"object","properties":{}}`
                                                             ELSE ls_tool-parameters ) ) ).

    DATA(lv_max_tokens) = COND i( WHEN ms_llm-max_output_tokens > 0 THEN ms_llm-max_output_tokens
                                  ELSE c_default_output_tokens ).

    " Strumenti senza compress, cosi' strict=false resta nel JSON: i nostri schemi non
    " dichiarano additionalProperties:false ovunque, come chiederebbe la modalita' strict.
    DATA(lv_tools) = /ui2/cl_json=>serialize( data        = lt_tools
                                              pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
    rv_json = |\{"model":{ to_json( ms_llm-model ) },"store":false,| &&
              |"include":["reasoning.encrypted_content"],| &&
              |"max_output_tokens":{ lv_max_tokens },| &&
              COND #( WHEN lt_tools IS NOT INITIAL THEN |"tools":{ lv_tools },| ) &&
              |"input":[{ concat_lines_of( table = lt_items sep = `,` ) }]\}|.
  ENDMETHOD.

  METHOD parse_response.
    DATA ls_api TYPE ty_api_response.
    DATA lt_items TYPE ty_response_items.

    /ui2/cl_json=>deserialize( EXPORTING json = iv_json
                               CHANGING  data = ls_api ).

    rs_response-input_tokens  = ls_api-usage-input_tokens.
    rs_response-output_tokens = ls_api-usage-output_tokens.

    IF ls_api-status = `failed`.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |OpenAI ({ ms_llm-model }): risposta fallita { ls_api-error-code } { ls_api-error-message }| ).
    ENDIF.

    rs_response-provider_data = ls_api-output.
    /ui2/cl_json=>deserialize( EXPORTING json = ls_api-output
                               CHANGING  data = lt_items ).

    LOOP AT lt_items INTO DATA(ls_item).
      CASE ls_item-type.
        WHEN `function_call`.
          APPEND VALUE #( id        = ls_item-call_id
                          name      = ls_item-name
                          arguments = COND #( WHEN ls_item-arguments IS INITIAL THEN `{}`
                                              ELSE ls_item-arguments ) ) TO rs_response-tool_calls.
        WHEN `message`.
          LOOP AT ls_item-content INTO DATA(ls_content).
            CASE ls_content-type.
              WHEN `output_text`.
                rs_response-text = rs_response-text && ls_content-text.
              WHEN `refusal`.
                rs_response-text        = ls_content-refusal.
                rs_response-stop_reason = /reg/if_ams_llm=>c_stop-refused.
                RETURN.
            ENDCASE.
          ENDLOOP.
      ENDCASE.
    ENDLOOP.

    IF rs_response-tool_calls IS NOT INITIAL.
      rs_response-stop_reason = /reg/if_ams_llm=>c_stop-tool_use.
      RETURN.
    ENDIF.

    rs_response-stop_reason = SWITCH #( ls_api-status
      WHEN `completed`  THEN /reg/if_ams_llm=>c_stop-end_turn
      WHEN `incomplete` THEN SWITCH #( ls_api-incomplete_details-reason
                                       WHEN `max_output_tokens` THEN /reg/if_ams_llm=>c_stop-max_tokens
                                       WHEN `content_filter`    THEN /reg/if_ams_llm=>c_stop-refused ) ).
    IF rs_response-stop_reason IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams(
        text = |OpenAI ({ ms_llm-model }): stato { ls_api-status } { ls_api-incomplete_details-reason } non gestito| ).
    ENDIF.
  ENDMETHOD.

  METHOD to_json.
    rv_json = /ui2/cl_json=>serialize( data        = ig_data
                                       compress    = abap_true
                                       pretty_name = /ui2/cl_json=>pretty_mode-low_case ).
  ENDMETHOD.

  METHOD array_items.
    DATA(lv_array) = condense( iv_array ).
    IF strlen( lv_array ) < 2 OR substring( val = lv_array len = 1 ) <> `[`.
      RETURN.
    ENDIF.
    rv_items = condense( substring( val = lv_array off = 1 len = strlen( lv_array ) - 2 ) ).
  ENDMETHOD.

ENDCLASS.
