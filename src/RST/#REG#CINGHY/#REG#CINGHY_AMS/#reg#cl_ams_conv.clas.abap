"! Conversazione dell'agente AMS in formato neutro: salvataggio nell'operazione, ripresa
"! e riduzione delle descrizioni di pagina piu' vecchie per contenere i token.
CLASS /reg/cl_ams_conv DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Soglia oltre la quale ridurre, in token stimati. Sotto la soglia la conversazione cresce
    "! solo in fondo, cosi' il caching del prefisso dei fornitori resta valido.
    CONSTANTS c_reduce_threshold TYPE i VALUE 30000.

    CLASS-METHODS to_json
      IMPORTING is_conversation TYPE /reg/if_ams_llm=>ty_conversation
      RETURNING VALUE(rv_json)  TYPE string.

    CLASS-METHODS from_json
      IMPORTING iv_json                TYPE string
      RETURNING VALUE(rs_conversation) TYPE /reg/if_ams_llm=>ty_conversation.

    "! Salva la conversazione nell'operazione (senza COMMIT: lo decide il chiamante).
    "! @raising /reg/cx_ams | Operazione inesistente: la conversazione andrebbe persa
    CLASS-METHODS save
      IMPORTING iv_op_id        TYPE sysuuid_x16
                is_conversation TYPE /reg/if_ams_llm=>ty_conversation
      RAISING   /reg/cx_ams.

    CLASS-METHODS load
      IMPORTING iv_op_id               TYPE sysuuid_x16
      RETURNING VALUE(rs_conversation) TYPE /reg/if_ams_llm=>ty_conversation.

    "! Stima grossolana: circa 4 caratteri per token. Basta per decidere quando ridurre.
    CLASS-METHODS estimate_tokens
      IMPORTING is_conversation  TYPE /reg/if_ams_llm=>ty_conversation
      RETURNING VALUE(rv_tokens) TYPE i.

    "! Sopra la soglia sostituisce il testo di ogni risultato riducibile con il suo summary,
    "! tranne l'ultimo, che resta completo. Sotto la soglia non cambia nulla.
    CLASS-METHODS reduce
      IMPORTING is_conversation        TYPE /reg/if_ams_llm=>ty_conversation
                iv_threshold           TYPE i DEFAULT c_reduce_threshold
      RETURNING VALUE(rs_conversation) TYPE /reg/if_ams_llm=>ty_conversation.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /reg/cl_ams_conv IMPLEMENTATION.

  METHOD to_json.
    rv_json = /ui2/cl_json=>serialize( data = is_conversation ).
  ENDMETHOD.

  METHOD from_json.
    /ui2/cl_json=>deserialize( EXPORTING json = iv_json
                               CHANGING  data = rs_conversation ).
  ENDMETHOD.

  METHOD save.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    UPDATE /reg/ams_op SET conversation = @( to_json( is_conversation ) ),
                           changed_at   = @lv_now
                       WHERE op_id = @iv_op_id.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Operazione { iv_op_id } non trovata: conversazione non salvata| ).
    ENDIF.
  ENDMETHOD.

  METHOD load.
    SELECT SINGLE conversation FROM /reg/ams_op WHERE op_id = @iv_op_id INTO @DATA(lv_json).
    IF sy-subrc = 0.
      rs_conversation = from_json( lv_json ).
    ENDIF.
  ENDMETHOD.

  METHOD estimate_tokens.
    DATA(lv_chars) = strlen( is_conversation-system ).
    LOOP AT is_conversation-messages INTO DATA(ls_message).
      lv_chars = lv_chars + strlen( ls_message-text ).
      LOOP AT ls_message-tool_calls INTO DATA(ls_call).
        lv_chars = lv_chars + strlen( ls_call-arguments ).
      ENDLOOP.
    ENDLOOP.
    rv_tokens = lv_chars DIV 4.
  ENDMETHOD.

  METHOD reduce.
    rs_conversation = is_conversation.
    IF estimate_tokens( is_conversation ) <= iv_threshold.
      RETURN.
    ENDIF.

    DATA(lv_last) = 0.
    LOOP AT rs_conversation-messages TRANSPORTING NO FIELDS WHERE reducible = abap_true.
      lv_last = sy-tabix.
    ENDLOOP.

    LOOP AT rs_conversation-messages ASSIGNING FIELD-SYMBOL(<ls_message>)
         WHERE reducible = abap_true.
      IF sy-tabix = lv_last.
        CONTINUE.
      ENDIF.
      <ls_message>-text      = <ls_message>-summary.
      <ls_message>-reducible = abap_false.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
