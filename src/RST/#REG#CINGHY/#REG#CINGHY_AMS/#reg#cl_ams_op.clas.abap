"! Operazione dell'agente AMS: stati, transizioni ammesse, limiti e avvio del passo successivo.
"! Ogni passo e' un'unita' bgPF breve (/REG/CL_AMS_STEP_JOB) che parte su un evento e termina
"! senza attendere: tra un passo e l'altro lo stato e' solo in /REG/AMS_OP (design 1).
CLASS /reg/cl_ams_op DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS:
      BEGIN OF c_status,
        reading    TYPE /reg/ams_op-status VALUE 'READING',
        plan_wait  TYPE /reg/ams_op-status VALUE 'PLAN_WAIT',
        executing  TYPE /reg/ams_op-status VALUE 'EXECUTING',
        login_wait TYPE /reg/ams_op-status VALUE 'LOGIN_WAIT',
        done       TYPE /reg/ams_op-status VALUE 'DONE',
        cancelled  TYPE /reg/ams_op-status VALUE 'CANCELLED',
        error      TYPE /reg/ams_op-status VALUE 'ERROR',
      END OF c_status,
      BEGIN OF c_phase,
        read    TYPE /reg/ams_op-phase VALUE 'R',
        execute TYPE /reg/ams_op-phase VALUE 'E',
      END OF c_phase.

    "! Transizione ammessa tra due stati. Gli stati finali non hanno uscite.
    CLASS-METHODS can_transition
      IMPORTING iv_from      TYPE /reg/ams_op-status
                iv_to        TYPE /reg/ams_op-status
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    CLASS-METHODS is_final
      IMPORTING iv_status       TYPE /reg/ams_op-status
      RETURNING VALUE(rv_final) TYPE abap_bool.

    "! Limite di passi e timeout. Restituisce il motivo dello stop, vuoto se l'operazione puo' continuare.
    "! Il timeout conta dall'ultimo cambiamento dell'operazione (changed_at).
    CLASS-METHODS check_limits
      IMPORTING is_op              TYPE /reg/ams_op
                iv_max_steps       TYPE i
                iv_timeout_minutes TYPE i
                iv_now             TYPE timestampl
      RETURNING VALUE(rv_reason)   TYPE string.

    "! Nuova operazione del consulente corrente, in fase di lettura (senza COMMIT).
    CLASS-METHODS create
      IMPORTING iv_portal       TYPE string
                iv_llm          TYPE string
                iv_instruction  TYPE string
      RETURNING VALUE(rv_op_id) TYPE sysuuid_x16
      RAISING   /reg/cx_ams.

    "! @raising /reg/cx_ams | Operazione inesistente
    CLASS-METHODS get
      IMPORTING iv_op_id     TYPE sysuuid_x16
      RETURNING VALUE(rs_op) TYPE /reg/ams_op
      RAISING   /reg/cx_ams.

    "! Cambia stato (e fase, per lettura ed esecuzione) se la transizione e' ammessa (senza COMMIT).
    "! @raising /reg/cx_ams | Transizione non ammessa o operazione inesistente
    CLASS-METHODS set_status
      IMPORTING iv_op_id    TYPE sysuuid_x16
                iv_status   TYPE /reg/ams_op-status
                iv_progress TYPE csequence OPTIONAL
                iv_result   TYPE string OPTIONAL
      RAISING   /reg/cx_ams.

    "! Porta l'operazione in errore con il motivo, se non e' gia' finita (senza COMMIT).
    CLASS-METHODS fail
      IMPORTING iv_op_id  TYPE sysuuid_x16
                iv_reason TYPE string.

    "! Chiede l'interruzione: la legge il passo successivo (senza COMMIT).
    CLASS-METHODS request_stop
      IMPORTING iv_op_id TYPE sysuuid_x16
      RAISING   /reg/cx_ams.

    "! Chiude in errore un'operazione oltre i limiti. Da chiamare quando si legge lo stato
    "! (servizi per Cinghy e per il runner) e all'inizio di ogni passo (senza COMMIT).
    "! @parameter rv_expired | abap_true se l'operazione e' stata chiusa ora
    CLASS-METHODS expire_if_stale
      IMPORTING iv_op_id          TYPE sysuuid_x16
                iv_max_steps      TYPE i
                iv_timeout_minutes TYPE i
      RETURNING VALUE(rv_expired) TYPE abap_bool
      RAISING   /reg/cx_ams.

    "! Mette in coda il passo successivo come unita' bgPF. Parte al COMMIT WORK del chiamante.
    "! @raising /reg/cx_ams | bgPF non disponibile o non configurato
    CLASS-METHODS schedule_step
      IMPORTING iv_op_id TYPE sysuuid_x16
      RAISING   /reg/cx_ams.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS now
      RETURNING VALUE(rv_now) TYPE timestampl.
ENDCLASS.


CLASS /reg/cl_ams_op IMPLEMENTATION.

  METHOD can_transition.
    rv_ok = SWITCH #( iv_from
      WHEN c_status-reading THEN xsdbool( iv_to = c_status-plan_wait OR iv_to = c_status-login_wait OR iv_to = c_status-done
                                          OR iv_to = c_status-cancelled OR iv_to = c_status-error )
      " Conferma -> esecuzione; modifica del piano -> di nuovo in lettura per proporne un altro.
      WHEN c_status-plan_wait THEN xsdbool( iv_to = c_status-executing OR iv_to = c_status-reading
                                            OR iv_to = c_status-cancelled OR iv_to = c_status-error )
      " Azione fuori dal piano -> nuova conferma.
      WHEN c_status-executing THEN xsdbool( iv_to = c_status-plan_wait OR iv_to = c_status-login_wait OR iv_to = c_status-done
                                            OR iv_to = c_status-cancelled OR iv_to = c_status-error )
      " Dopo l'accesso si torna alla fase in cui si era.
      WHEN c_status-login_wait THEN xsdbool( iv_to = c_status-reading OR iv_to = c_status-executing
                                             OR iv_to = c_status-cancelled OR iv_to = c_status-error )
      ELSE abap_false ).
  ENDMETHOD.

  METHOD is_final.
    rv_final = xsdbool( iv_status = c_status-done OR iv_status = c_status-cancelled OR iv_status = c_status-error ).
  ENDMETHOD.

  METHOD check_limits.
    IF is_final( is_op-status ) = abap_true.
      RETURN.
    ENDIF.

    IF iv_max_steps > 0 AND is_op-steps >= iv_max_steps.
      rv_reason = |Limite di { iv_max_steps } passi raggiunto: operazione fermata|.
      RETURN.
    ENDIF.

    IF iv_timeout_minutes > 0 AND is_op-changed_at IS NOT INITIAL
       AND cl_abap_tstmp=>subtract( tstmp1 = iv_now tstmp2 = is_op-changed_at ) > iv_timeout_minutes * 60.
      rv_reason = SWITCH #( is_op-status
        WHEN c_status-plan_wait  THEN |Piano non confermato entro { iv_timeout_minutes } minuti|
        WHEN c_status-login_wait THEN |Accesso al portale non fatto entro { iv_timeout_minutes } minuti|
        ELSE |Nessuna risposta dal runner da { iv_timeout_minutes } minuti: il runner e' avviato e collegato?| ).
    ENDIF.
  ENDMETHOD.

  METHOD create.
    TRY.
        rv_op_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error INTO DATA(lx_uuid).
        RAISE EXCEPTION NEW /reg/cx_ams( text = |Id operazione non generato| previous = lx_uuid ).
    ENDTRY.
    DATA(lv_now) = now( ).
    DATA(ls_op) = VALUE /reg/ams_op( op_id       = rv_op_id
                                     consultant  = sy-uname
                                     portal      = iv_portal
                                     llm         = iv_llm
                                     status      = c_status-reading
                                     phase       = c_phase-read
                                     instruction = iv_instruction
                                     created_at  = lv_now
                                     changed_at  = lv_now ).
    INSERT /reg/ams_op FROM @ls_op.
  ENDMETHOD.

  METHOD get.
    SELECT SINGLE * FROM /reg/ams_op WHERE op_id = @iv_op_id INTO @rs_op.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Operazione { iv_op_id } non trovata| ).
    ENDIF.
  ENDMETHOD.

  METHOD set_status.
    DATA(ls_op) = get( iv_op_id ).
    IF can_transition( iv_from = ls_op-status iv_to = iv_status ) = abap_false.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Operazione { iv_op_id }: passaggio da { ls_op-status } a { iv_status } non ammesso| ).
    ENDIF.

    ls_op-status = iv_status.
    ls_op-phase  = SWITCH #( iv_status WHEN c_status-reading   THEN c_phase-read
                                       WHEN c_status-executing THEN c_phase-execute
                                       ELSE ls_op-phase ).
    IF iv_progress IS SUPPLIED.
      ls_op-progress = iv_progress.
    ENDIF.
    IF iv_result IS SUPPLIED.
      ls_op-result_text = iv_result.
    ENDIF.
    ls_op-changed_at = now( ).
    UPDATE /reg/ams_op FROM @ls_op.
  ENDMETHOD.

  METHOD fail.
    TRY.
        DATA(ls_op) = get( iv_op_id ).
        IF is_final( ls_op-status ) = abap_false.
          set_status( iv_op_id = iv_op_id iv_status = c_status-error iv_result = iv_reason ).
        ENDIF.
      CATCH /reg/cx_ams ##NO_HANDLER.
        " Operazione inesistente: non c'e' nulla da chiudere.
    ENDTRY.
  ENDMETHOD.

  METHOD request_stop.
    get( iv_op_id ).
    UPDATE /reg/ams_op SET stop_requested = @abap_true WHERE op_id = @iv_op_id.
  ENDMETHOD.

  METHOD expire_if_stale.
    DATA(lv_reason) = check_limits( is_op              = get( iv_op_id )
                                    iv_max_steps       = iv_max_steps
                                    iv_timeout_minutes = iv_timeout_minutes
                                    iv_now             = now( ) ).
    IF lv_reason IS NOT INITIAL.
      fail( iv_op_id = iv_op_id iv_reason = lv_reason ).
      rv_expired = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD schedule_step.
    TRY.
        DATA(lo_process) = cl_bgmc_process_factory=>get_default( )->create( ).
        lo_process->set_name( |CINGHY_AMS { iv_op_id }| ).
        lo_process->set_operation_tx_uncontrolled( NEW /reg/cl_ams_step_job( iv_op_id ) ).
        lo_process->save_for_execution( ).
      CATCH cx_bgmc INTO DATA(lx_bgmc).
        RAISE EXCEPTION NEW /reg/cx_ams( text     = |Passo in background non avviato: { lx_bgmc->get_text( ) }|
                                         previous = lx_bgmc ).
    ENDTRY.
  ENDMETHOD.

  METHOD now.
    GET TIME STAMP FIELD rv_now.
  ENDMETHOD.

ENDCLASS.
