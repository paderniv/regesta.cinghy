*&---------------------------------------------------------------------*
*& Agente AMS: inserisce o sostituisce la chiave API di un modello.
*& Il codice modello e' quello di LLMS in TuneCraft (CINGHY_AMS).
*& La chiave non viene mai mostrata: il campo e' nascosto con asterischi.
*&---------------------------------------------------------------------*
REPORT /reg/ams_set_key.

PARAMETERS: p_llm TYPE c LENGTH 20 OBLIGATORY,
            p_key TYPE c LENGTH 512 LOWER CASE OBLIGATORY.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-name = 'P_KEY'.
      screen-invisible = 1.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

START-OF-SELECTION.
  TRY.
      /reg/cl_ams_key=>set( iv_llm = CONV #( p_llm ) iv_key = CONV #( p_key ) ).
      COMMIT WORK.
      MESSAGE |Chiave API salvata per il modello { to_upper( p_llm ) }| TYPE 'S'.
    CATCH /reg/cx_ams INTO DATA(lx_error).
      MESSAGE lx_error->get_text( ) TYPE 'E'.
  ENDTRY.
  CLEAR p_key.
