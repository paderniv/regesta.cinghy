"! Chiavi API dei modelli dell'agente AMS, una per codice modello di TuneCraft (LLMS-LLM).
"! La chiave e' in chiaro in /REG/AMS_KEY: la tabella non ha manutenzione e si scrive solo da qui.
CLASS /reg/cl_ams_key DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! @raising /reg/cx_ams | Nessuna chiave per il modello
    CLASS-METHODS get
      IMPORTING iv_llm        TYPE string
      RETURNING VALUE(rv_key) TYPE string
      RAISING   /reg/cx_ams.

    "! Scrive o sostituisce la chiave (senza COMMIT). Richiede S_TABU_NAM 02 su /REG/AMS_KEY.
    "! @raising /reg/cx_ams | Utente non autorizzato o chiave vuota
    CLASS-METHODS set
      IMPORTING iv_llm TYPE string
                iv_key TYPE string
      RAISING   /reg/cx_ams.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /reg/cl_ams_key IMPLEMENTATION.

  METHOD get.
    SELECT SINGLE api_key FROM /reg/ams_key WHERE llm = @( to_upper( iv_llm ) ) INTO @DATA(lv_key).
    IF sy-subrc <> 0 OR lv_key IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Nessuna chiave API per il modello { iv_llm }: inserirla con il report /REG/AMS_SET_KEY| ).
    ENDIF.
    rv_key = condense( lv_key ).
  ENDMETHOD.

  METHOD set.
    AUTHORITY-CHECK OBJECT 'S_TABU_NAM'
      ID 'ACTVT' FIELD '02'
      ID 'TABLE' FIELD '/REG/AMS_KEY'.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Non autorizzato a modificare le chiavi API (S_TABU_NAM 02 /REG/AMS_KEY)| ).
    ENDIF.
    IF condense( iv_key ) = `` OR iv_llm IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Modello e chiave sono obbligatori| ).
    ENDIF.

    DATA(ls_key) = VALUE /reg/ams_key( llm        = to_upper( iv_llm )
                                       api_key    = condense( iv_key )
                                       changed_by = sy-uname ).
    GET TIME STAMP FIELD ls_key-changed_at.
    MODIFY /reg/ams_key FROM @ls_key.
  ENDMETHOD.

ENDCLASS.
