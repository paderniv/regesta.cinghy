"! Runner dell'agente AMS: associazione con codice monouso e token (design 5).
"! Su RST si conservano solo gli hash SHA-256 di codice e token, mai i valori.
CLASS /reg/cl_ams_runner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Caratteri del codice: niente 0/O, 1/I/L, cosi' si detta e si copia senza errori.
    CONSTANTS c_alphabet TYPE string VALUE `ABCDEFGHJKMNPQRSTUVWXYZ23456789`.
    CONSTANTS c_code_length TYPE i VALUE 8.
    CONSTANTS c_pairing_minutes TYPE i VALUE 10.

    "! Hash SHA-256 in esadecimale.
    "! @raising /reg/cx_ams | Algoritmo non disponibile
    CLASS-METHODS hash
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_hash) TYPE string
      RAISING   /reg/cx_ams.

    "! Codice di c_code_length caratteri di c_alphabet ricavato da byte casuali.
    CLASS-METHODS code_from_bytes
      IMPORTING iv_bytes       TYPE xstring
      RETURNING VALUE(rv_code) TYPE string.

    "! Nuovo runner del consulente in attesa di associazione; restituisce il codice monouso
    "! da inserire nel runner entro c_pairing_minutes minuti (senza COMMIT).
    "! @raising /reg/cx_ams | Generatore casuale o hash non disponibili
    CLASS-METHODS create_pairing_code
      IMPORTING iv_owner       TYPE syuname
      RETURNING VALUE(rv_code) TYPE string
      RAISING   /reg/cx_ams.

    TYPES:
      BEGIN OF ty_action,
        step_id         TYPE sysuuid_x16,
        op_id           TYPE sysuuid_x16,
        tool            TYPE string,
        args            TYPE string,
        allowed_domains TYPE string_table,
        login_domains   TYPE string_table,
      END OF ty_action,
      ty_actions TYPE STANDARD TABLE OF ty_action WITH EMPTY KEY.

    "! Riga in attesa di associazione, codice non scaduto e mai usato.
    CLASS-METHODS is_pairable
      IMPORTING is_runner    TYPE /reg/ams_run
                iv_now       TYPE timestampl
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    "! Un'azione e' per questo runner: runner locale -> solo operazioni del suo consulente su portali
    "! con runner locale; runner centrale (senza proprietario) -> solo portali con runner centrale.
    CLASS-METHODS is_for_runner
      IMPORTING iv_runner_owner TYPE syuname
                iv_consultant   TYPE syuname
                iv_runner_kind  TYPE string
      RETURNING VALUE(rv_ok)    TYPE abap_bool.

    "! Scambia il codice monouso con un token, restituito solo qui; su RST resta il suo hash (senza COMMIT).
    "! @raising /reg/cx_ams | Codice sbagliato, scaduto o gia' usato (401)
    CLASS-METHODS pair
      IMPORTING iv_code         TYPE string
                iv_name         TYPE string OPTIONAL
      RETURNING VALUE(rv_token) TYPE string
      RAISING   /reg/cx_ams.

    "! Runner del token, non revocato; aggiorna l'ultimo contatto (senza COMMIT).
    "! @raising /reg/cx_ams | Token mancante, sconosciuto o revocato (401)
    CLASS-METHODS authenticate
      IMPORTING iv_token         TYPE string
      RETURNING VALUE(rs_runner) TYPE /reg/ams_run
      RAISING   /reg/cx_ams.

    "! Azioni in coda per il runner, segnate come consegnate (senza COMMIT).
    CLASS-METHODS take_actions
      IMPORTING is_runner         TYPE /reg/ams_run
                is_cfg            TYPE /reg/cl_ams_cfg=>ty_app_config
      RETURNING VALUE(rt_actions) TYPE ty_actions.

    "! Esito di un'azione consegnata a questo runner (senza COMMIT).
    "! @raising /reg/cx_ams | Azione non consegnata a questo runner (404) o esito non accettato
    CLASS-METHODS report_result
      IMPORTING is_runner         TYPE /reg/ams_run
                iv_step_id        TYPE sysuuid_x16
                iv_result         TYPE string
                iv_is_error       TYPE abap_bool
                iv_summary        TYPE string OPTIONAL
                iv_login_required TYPE abap_bool OPTIONAL
                iv_screenshot     TYPE xstring OPTIONAL
      RAISING   /reg/cx_ams.

    "! Revoca tutti i runner del consulente: i loro token non valgono piu' (senza COMMIT).
    CLASS-METHODS revoke_all
      IMPORTING iv_owner        TYPE syuname
      RETURNING VALUE(rv_count) TYPE i.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS random_bytes
      IMPORTING iv_length       TYPE i
      RETURNING VALUE(rv_bytes) TYPE xstring
      RAISING   /reg/cx_ams.
ENDCLASS.


CLASS /reg/cl_ams_runner IMPLEMENTATION.

  METHOD hash.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_char( EXPORTING if_algorithm  = `SHA256`
                                                                   if_data       = iv_text
                                                         IMPORTING ef_hashstring = rv_hash ).
        rv_hash = to_lower( rv_hash ).
      CATCH cx_abap_message_digest INTO DATA(lx_digest).
        RAISE EXCEPTION NEW /reg/cx_ams( text = `Hash SHA-256 non disponibile` previous = lx_digest ).
    ENDTRY.
  ENDMETHOD.

  METHOD code_from_bytes.
    DATA lv_byte TYPE x LENGTH 1.
    DATA(lv_size) = strlen( c_alphabet ).
    DO nmin( val1 = c_code_length val2 = xstrlen( iv_bytes ) ) TIMES.
      DATA(lv_offset) = sy-index - 1.
      lv_byte = iv_bytes+lv_offset(1).
      DATA(lv_index) = CONV i( lv_byte ) MOD lv_size.
      rv_code = rv_code && substring( val = c_alphabet off = lv_index len = 1 ).
    ENDDO.
  ENDMETHOD.

  METHOD create_pairing_code.
    DATA lv_now TYPE timestampl.

    rv_code = code_from_bytes( random_bytes( 16 ) ).

    GET TIME STAMP FIELD lv_now.
    TRY.
        DATA(ls_runner) = VALUE /reg/ams_run( runner_id  = cl_system_uuid=>create_uuid_x16_static( )
                                              owner      = iv_owner
                                              pair_hash  = hash( rv_code )
                                              pair_until = cl_abap_tstmp=>add( tstmp = lv_now secs = c_pairing_minutes * 60 )
                                              created_at = lv_now ).
      CATCH cx_uuid_error INTO DATA(lx_uuid).
        RAISE EXCEPTION NEW /reg/cx_ams( text = `Id del runner non generato` previous = lx_uuid ).
    ENDTRY.
    INSERT /reg/ams_run FROM @ls_runner.
  ENDMETHOD.

  METHOD is_pairable.
    rv_ok = xsdbool( is_runner-pair_hash IS NOT INITIAL
                     AND is_runner-token_hash IS INITIAL
                     AND is_runner-revoked = abap_false
                     AND is_runner-pair_until >= iv_now ).
  ENDMETHOD.

  METHOD is_for_runner.
    IF iv_runner_owner IS INITIAL.
      rv_ok = xsdbool( to_upper( iv_runner_kind ) = `CENTRAL` ).
    ELSE.
      rv_ok = xsdbool( iv_consultant = iv_runner_owner AND to_upper( iv_runner_kind ) <> `CENTRAL` ).
    ENDIF.
  ENDMETHOD.

  METHOD pair.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    DATA(lv_code_hash) = hash( to_upper( condense( iv_code ) ) ).
    SELECT SINGLE * FROM /reg/ams_run WHERE pair_hash = @lv_code_hash INTO @DATA(ls_runner).
    IF sy-subrc <> 0 OR is_pairable( is_runner = ls_runner iv_now = lv_now ) = abap_false.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Codice di associazione sbagliato, scaduto o gia' usato: generane uno nuovo da Cinghy`
                                       http_status = 401 ).
    ENDIF.

    " Token di 32 byte casuali in esadecimale: sul runner resta il token, su RST solo il suo hash.
    rv_token = to_lower( CONV string( random_bytes( 32 ) ) ).
    ls_runner-token_hash = hash( rv_token ).
    ls_runner-pair_hash  = ``.
    ls_runner-name       = iv_name.
    ls_runner-last_seen  = lv_now.
    UPDATE /reg/ams_run FROM @ls_runner.
  ENDMETHOD.

  METHOD authenticate.
    DATA lv_now TYPE timestampl.

    IF iv_token IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Token del runner mancante` http_status = 401 ).
    ENDIF.
    DATA(lv_token_hash) = hash( iv_token ).
    SELECT SINGLE * FROM /reg/ams_run WHERE token_hash = @lv_token_hash INTO @rs_runner.
    IF sy-subrc <> 0 OR rs_runner-revoked = abap_true.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Token del runner sconosciuto o revocato: associa di nuovo il runner` http_status = 401 ).
    ENDIF.

    GET TIME STAMP FIELD lv_now.
    rs_runner-last_seen = lv_now.
    UPDATE /reg/ams_run SET last_seen = @lv_now WHERE runner_id = @rs_runner-runner_id.
  ENDMETHOD.

  METHOD take_actions.
    DATA lv_now TYPE timestampl.

    SELECT s~step_id, s~op_id, s~tool, s~args, o~portal, o~consultant
      FROM /reg/ams_step AS s
      INNER JOIN /reg/ams_op AS o ON o~op_id = s~op_id
      WHERE s~kind = 'ACTION' AND s~status = 'Q'
        AND o~stop_requested = @abap_false
        AND ( o~status = 'READING' OR o~status = 'EXECUTING' )
      ORDER BY o~op_id, s~seq
      INTO TABLE @DATA(lt_queued).

    GET TIME STAMP FIELD lv_now.
    LOOP AT lt_queued INTO DATA(ls_queued).
      DATA(lv_kind) = VALUE string( is_cfg-portals[ portal = ls_queued-portal ]-runner_kind OPTIONAL ).
      IF is_for_runner( iv_runner_owner = is_runner-owner iv_consultant = ls_queued-consultant iv_runner_kind = lv_kind ) = abap_false.
        CONTINUE.
      ENDIF.
      " Segnata consegnata solo se nessun altro runner l'ha presa nel frattempo.
      UPDATE /reg/ams_step SET status = 'S', delivered_at = @lv_now
        WHERE step_id = @ls_queued-step_id AND status = 'Q'.
      IF sy-dbcnt = 0.
        CONTINUE.
      ENDIF.
      APPEND VALUE #(
        step_id         = ls_queued-step_id
        op_id           = ls_queued-op_id
        tool            = ls_queued-tool
        args            = ls_queued-args
        allowed_domains = VALUE #( FOR d IN is_cfg-portal_domains WHERE ( portal = ls_queued-portal ) ( to_lower( d-domain ) ) )
        login_domains   = VALUE #( FOR d IN is_cfg-portal_domains WHERE ( portal = ls_queued-portal AND is_login = abap_true )
                                   ( to_lower( d-domain ) ) ) ) TO rt_actions.
    ENDLOOP.
  ENDMETHOD.

  METHOD report_result.
    SELECT SINGLE s~status, o~consultant, o~portal
      FROM /reg/ams_step AS s
      INNER JOIN /reg/ams_op AS o ON o~op_id = s~op_id
      WHERE s~step_id = @iv_step_id
      INTO @DATA(ls_step).
    " Un runner locale manda esiti solo per le operazioni del suo consulente.
    IF sy-subrc <> 0 OR ls_step-status <> 'S'
       OR ( is_runner-owner IS NOT INITIAL AND ls_step-consultant <> is_runner-owner ).
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Azione { iv_step_id } non consegnata a questo runner| http_status = 404 ).
    ENDIF.
    /reg/cl_ams_agent=>action_result( iv_step_id        = iv_step_id
                                      iv_result         = iv_result
                                      iv_is_error       = iv_is_error
                                      iv_summary        = iv_summary
                                      iv_login_required = iv_login_required
                                      iv_screenshot     = iv_screenshot ).
  ENDMETHOD.

  METHOD revoke_all.
    UPDATE /reg/ams_run SET revoked = @abap_true, pair_hash = @space
      WHERE owner = @iv_owner AND revoked = @abap_false.
    rv_count = sy-dbcnt.
  ENDMETHOD.

  METHOD random_bytes.
    CALL FUNCTION 'GENERATE_SEC_RANDOM'
      EXPORTING
        length         = iv_length
      IMPORTING
        random         = rv_bytes
      EXCEPTIONS
        invalid_length = 1
        no_memory      = 2
        internal_error = 3
        OTHERS         = 4.
    IF sy-subrc <> 0 OR xstrlen( rv_bytes ) < iv_length.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Generatore casuale sicuro non disponibile` ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
