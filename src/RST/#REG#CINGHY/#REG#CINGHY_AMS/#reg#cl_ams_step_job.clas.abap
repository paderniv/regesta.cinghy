"! Unita' bgPF di un passo dell'agente AMS: parte su un evento (istruzione, esito del runner,
"! conferma del piano, accesso fatto), esegue un passo e termina senza attendere (design 1).
"! Transazione non controllata: il framework conferma al termine dell'unita'.
CLASS /reg/cl_ams_step_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_bgmc_op_single_tx_uncontr.

    METHODS constructor
      IMPORTING iv_op_id TYPE sysuuid_x16.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA mv_op_id TYPE sysuuid_x16.
ENDCLASS.


CLASS /reg/cl_ams_step_job IMPLEMENTATION.

  METHOD constructor.
    mv_op_id = iv_op_id.
  ENDMETHOD.

  METHOD if_bgmc_op_single_tx_uncontr~execute.
    TRY.
        DATA(ls_op) = /reg/cl_ams_op=>get( mv_op_id ).
        IF /reg/cl_ams_op=>is_final( ls_op-status ) = abap_true.
          RETURN.
        ENDIF.

        " Interruzione: letta all'inizio di ogni passo, quindi l'agente si ferma dopo l'azione in corso.
        IF ls_op-stop_requested = abap_true.
          /reg/cl_ams_op=>set_status( iv_op_id  = mv_op_id
                                      iv_status = /reg/cl_ams_op=>c_status-cancelled
                                      iv_result = `Operazione interrotta dal consulente` ).
          RETURN.
        ENDIF.

        DATA(ls_cfg) = NEW /reg/cl_ams_cfg( )->app_cfg_par.
        IF /reg/cl_ams_op=>expire_if_stale( iv_op_id           = mv_op_id
                                            iv_max_steps       = ls_cfg-max_steps
                                            iv_timeout_minutes = ls_cfg-timeout_minutes ) = abap_true.
          RETURN.
        ENDIF.

        /reg/cl_ams_agent=>step( mv_op_id ).

      CATCH cx_static_check INTO DATA(lx_error).
        " Errore non gestito dal passo: l'operazione si chiude in errore invece di restare in attesa.
        /reg/cl_ams_op=>fail( iv_op_id = mv_op_id iv_reason = lx_error->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
