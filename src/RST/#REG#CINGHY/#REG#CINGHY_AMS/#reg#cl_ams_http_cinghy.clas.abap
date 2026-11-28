"! Servizio HTTP dell'agente AMS per Cinghy (handler del nodo SICF, design 7). JSON in e out.
"!   POST /operations                          {instruction, portal?}      avvia un'operazione
"!   GET  /operations/{id}                                                 stato (controlla anche i timeout)
"!   POST /operations/{id}/decision            {decision, note?}           confirm | cancel | modify
"!   POST /operations/{id}/stop                                            interrompe
"!   POST /operations/{id}/login-done                                      "Ho fatto l'accesso"
"!   GET  /operations/{id}/screenshot                                      ultimo screenshot (PNG), 404 se nessuno
"!   POST /runners/pairing-code                                            codice di associazione del runner
"!   GET  /runners/me                                                      runner del consulente collegato?
"!   POST /runners/revoke                                                  revoca tutti i runner del consulente
"! Le POST richiedono l'header X-Requested-With: un sito di terzi non puo' inviarlo senza CORS (CSRF).
CLASS /reg/cl_ams_http_cinghy DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

    CONSTANTS:
      BEGIN OF c_endpoint,
        start      TYPE string VALUE `START`,
        status     TYPE string VALUE `STATUS`,
        decision   TYPE string VALUE `DECISION`,
        stop       TYPE string VALUE `STOP`,
        login_done TYPE string VALUE `LOGIN_DONE`,
        screenshot TYPE string VALUE `SCREENSHOT`,
        pairing    TYPE string VALUE `PAIRING`,
        runner     TYPE string VALUE `RUNNER`,
        revoke     TYPE string VALUE `REVOKE`,
      END OF c_endpoint.

    TYPES:
      BEGIN OF ty_route,
        endpoint TYPE string,
        op_id    TYPE sysuuid_x16,
      END OF ty_route,
      BEGIN OF ty_portal_choice,
        portal TYPE string,
        "! Messaggio per il consulente se il portale non e' unico; vuoto se trovato.
        error  TYPE string,
      END OF ty_portal_choice.

    "! Endpoint e operazione da metodo e percorso; endpoint vuoto se il percorso non esiste.
    CLASS-METHODS route
      IMPORTING iv_method       TYPE string
                iv_path         TYPE string
      RETURNING VALUE(rs_route) TYPE ty_route.

    "! Portale dell'istruzione: quello indicato, oppure l'unico portale attivo citato nel testo
    "! (codice o nome del cliente). Se nessuno o piu' d'uno, il messaggio chiede di indicarlo.
    CLASS-METHODS resolve_portal
      IMPORTING is_cfg           TYPE /reg/cl_ams_cfg=>ty_app_config
                iv_instruction   TYPE string
                iv_portal        TYPE string OPTIONAL
      RETURNING VALUE(rs_choice) TYPE ty_portal_choice.

    "! Stato dell'operazione per il pannello.
    CLASS-METHODS status_json
      IMPORTING is_op          TYPE /reg/ams_op
      RETURNING VALUE(rv_json) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS start
      IMPORTING iv_body        TYPE string
      RETURNING VALUE(rv_json) TYPE string
      RAISING   cx_static_check.

    CLASS-METHODS status
      IMPORTING iv_op_id       TYPE sysuuid_x16
      RETURNING VALUE(rv_json) TYPE string
      RAISING   cx_static_check.

    CLASS-METHODS decision
      IMPORTING iv_op_id       TYPE sysuuid_x16
                iv_body        TYPE string
      RETURNING VALUE(rv_json) TYPE string
      RAISING   cx_static_check.

    CLASS-METHODS own_op
      IMPORTING iv_op_id     TYPE sysuuid_x16
      RETURNING VALUE(rs_op) TYPE /reg/ams_op
      RAISING   /reg/cx_ams.

    CLASS-METHODS check_portal
      IMPORTING iv_portal TYPE string
      RAISING   /reg/cx_ams.

    "! @raising /reg/cx_ams | 404 se l'operazione non ha screenshot
    CLASS-METHODS last_screenshot
      IMPORTING iv_op_id      TYPE sysuuid_x16
      RETURNING VALUE(rv_png) TYPE xstring
      RAISING   /reg/cx_ams.

    CLASS-METHODS reply
      IMPORTING io_server TYPE REF TO if_http_server
                iv_status TYPE i
                iv_json   TYPE string.

    CLASS-METHODS error_json
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_json) TYPE string.
ENDCLASS.


CLASS /reg/cl_ams_http_cinghy IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    DATA(lv_method) = to_upper( server->request->get_header_field( '~request_method' ) ).
    DATA(lv_json) = ``.
    DATA lv_png TYPE xstring.

    TRY.
        IF lv_method <> `GET` AND server->request->get_header_field( 'x-requested-with' ) IS INITIAL.
          RAISE EXCEPTION NEW /reg/cx_ams( text = `Richiesta senza header X-Requested-With: rifiutata` http_status = 403 ).
        ENDIF.

        DATA(ls_route) = route( iv_method = lv_method iv_path = server->request->get_header_field( '~path_info' ) ).
        DATA(lv_body)  = server->request->get_cdata( ).

        CASE ls_route-endpoint.
          WHEN c_endpoint-start.
            lv_json = start( lv_body ).
          WHEN c_endpoint-status.
            lv_json = status( ls_route-op_id ).
          WHEN c_endpoint-decision.
            lv_json = decision( iv_op_id = ls_route-op_id iv_body = lv_body ).
          WHEN c_endpoint-stop.
            own_op( ls_route-op_id ).
            /reg/cl_ams_agent=>stop( ls_route-op_id ).
            lv_json = status_json( /reg/cl_ams_op=>get( ls_route-op_id ) ).
          WHEN c_endpoint-login_done.
            own_op( ls_route-op_id ).
            /reg/cl_ams_agent=>login_done( ls_route-op_id ).
            lv_json = status_json( /reg/cl_ams_op=>get( ls_route-op_id ) ).
          WHEN c_endpoint-screenshot.
            own_op( ls_route-op_id ).
            lv_png = last_screenshot( ls_route-op_id ).
          WHEN c_endpoint-pairing.
            check_portal( `` ).
            lv_json = |\{"code":"{ /reg/cl_ams_runner=>create_pairing_code( sy-uname ) }",| &&
                      |"validMinutes":{ /reg/cl_ams_runner=>c_pairing_minutes }\}|.
          WHEN c_endpoint-revoke.
            lv_json = |\{"revoked":{ /reg/cl_ams_runner=>revoke_all( sy-uname ) }\}|.
          WHEN c_endpoint-runner.
            lv_json = |\{"online":{ COND string( WHEN /reg/cl_ams_agent=>runner_online( iv_consultant  = sy-uname
                                                                                         iv_runner_kind = `LOCAL` ) = abap_true
                                                 THEN `true` ELSE `false` ) }\}|.
          WHEN OTHERS.
            RAISE EXCEPTION NEW /reg/cx_ams( text = |Percorso { lv_method } non previsto| http_status = 404 ).
        ENDCASE.

        COMMIT WORK.
        IF lv_png IS NOT INITIAL.
          server->response->set_status( code = 200 reason = `OK` ).
          server->response->set_header_field( name = 'Content-Type' value = 'image/png' ).
          server->response->set_header_field( name = 'Cache-Control' value = 'private, no-store' ).
          server->response->set_data( lv_png ).
        ELSE.
          reply( io_server = server iv_status = 200 iv_json = lv_json ).
        ENDIF.

      CATCH /reg/cx_ams INTO DATA(lx_ams).
        ROLLBACK WORK.
        reply( io_server = server
               iv_status = COND #( WHEN lx_ams->http_status BETWEEN 400 AND 499 THEN lx_ams->http_status ELSE 400 )
               iv_json   = error_json( lx_ams->get_text( ) ) ).
      CATCH cx_static_check INTO DATA(lx_error).
        ROLLBACK WORK.
        reply( io_server = server iv_status = 500 iv_json = error_json( lx_error->get_text( ) ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD route.
    SPLIT iv_path AT `/` INTO TABLE DATA(lt_parts).
    DELETE lt_parts WHERE table_line IS INITIAL.

    DATA(lv_id) = to_upper( VALUE string( lt_parts[ 2 ] OPTIONAL ) ).
    DATA(lv_valid_id) = xsdbool( strlen( lv_id ) = 32 AND lv_id CO '0123456789ABCDEF' ).
    DATA(lv_first) = VALUE string( lt_parts[ 1 ] OPTIONAL ).
    DATA(lv_last)  = VALUE string( lt_parts[ 3 ] OPTIONAL ).

    IF lv_first = `runners` AND lines( lt_parts ) = 2.
      rs_route-endpoint = COND #( WHEN iv_method = `POST` AND lt_parts[ 2 ] = `pairing-code` THEN c_endpoint-pairing
                                  WHEN iv_method = `GET`  AND lt_parts[ 2 ] = `me`           THEN c_endpoint-runner
                                  WHEN iv_method = `POST` AND lt_parts[ 2 ] = `revoke`       THEN c_endpoint-revoke ).
      RETURN.
    ENDIF.

    IF lv_first <> `operations`.
      RETURN.
    ENDIF.
    IF lines( lt_parts ) = 1.
      rs_route-endpoint = COND #( WHEN iv_method = `POST` THEN c_endpoint-start ).
      RETURN.
    ENDIF.
    IF lv_valid_id = abap_false OR lines( lt_parts ) > 3.
      RETURN.
    ENDIF.

    rs_route-op_id = lv_id.
    rs_route-endpoint = COND #(
      WHEN iv_method = `GET`  AND lines( lt_parts ) = 2  THEN c_endpoint-status
      WHEN iv_method = `POST` AND lv_last = `decision`   THEN c_endpoint-decision
      WHEN iv_method = `POST` AND lv_last = `stop`       THEN c_endpoint-stop
      WHEN iv_method = `POST` AND lv_last = `login-done` THEN c_endpoint-login_done
      WHEN iv_method = `GET`  AND lv_last = `screenshot` THEN c_endpoint-screenshot ).
    IF rs_route-endpoint IS INITIAL.
      CLEAR rs_route-op_id.
    ENDIF.
  ENDMETHOD.

  METHOD resolve_portal.
    DATA lt_found TYPE string_table.

    DATA(lt_active) = VALUE string_table( FOR p IN is_cfg-portals WHERE ( active = abap_true ) ( p-portal ) ).
    DATA(lv_list) = concat_lines_of( table = lt_active sep = `, ` ).

    IF iv_portal IS NOT INITIAL.
      IF line_exists( lt_active[ table_line = to_upper( iv_portal ) ] ).
        rs_choice-portal = to_upper( iv_portal ).
      ELSE.
        rs_choice-error = |Il portale { iv_portal } non e' configurato o non e' attivo. Portali disponibili: { lv_list }|.
      ENDIF.
      RETURN.
    ENDIF.

    DATA(lv_text) = to_upper( iv_instruction ).
    LOOP AT is_cfg-portals INTO DATA(ls_portal) WHERE active = abap_true.
      IF find( val = lv_text sub = to_upper( ls_portal-portal ) ) >= 0
         OR ( ls_portal-customer IS NOT INITIAL AND find( val = lv_text sub = to_upper( ls_portal-customer ) ) >= 0 ).
        APPEND ls_portal-portal TO lt_found.
      ENDIF.
    ENDLOOP.

    CASE lines( lt_found ).
      WHEN 1.
        rs_choice-portal = lt_found[ 1 ].
      WHEN 0.
        rs_choice-error = |Non riconosco il portale del cliente nell'istruzione, o il cliente non ha un portale configurato. | &&
                          |Indica uno dei portali disponibili: { lv_list }|.
      WHEN OTHERS.
        rs_choice-error = |Su quale portale lavoro? L'istruzione ne cita piu' d'uno: { concat_lines_of( table = lt_found sep = `, ` ) }|.
    ENDCASE.
  ENDMETHOD.

  METHOD status_json.
    TYPES: BEGIN OF ty_status,
             op_id         TYPE string,
             status        TYPE string,
             phase         TYPE string,
             final         TYPE abap_bool,
             portal        TYPE string,
             llm           TYPE string,
             progress      TYPE string,
             plan          TYPE /ui2/cl_json=>json,
             result        TYPE string,
             steps         TYPE i,
             input_tokens  TYPE i,
             output_tokens TYPE i,
           END OF ty_status.

    rv_json = /ui2/cl_json=>serialize(
      data        = VALUE ty_status( op_id         = |{ is_op-op_id }|
                                     status        = is_op-status
                                     phase         = is_op-phase
                                     final         = /reg/cl_ams_op=>is_final( is_op-status )
                                     portal        = is_op-portal
                                     llm           = is_op-llm
                                     progress      = is_op-progress
                                     plan          = is_op-plan_json
                                     result        = is_op-result_text
                                     steps         = is_op-steps
                                     input_tokens  = is_op-input_tokens
                                     output_tokens = is_op-output_tokens )
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
  ENDMETHOD.

  METHOD start.
    TYPES: BEGIN OF ty_in,
             instruction TYPE string,
             portal      TYPE string,
           END OF ty_in.
    DATA ls_in TYPE ty_in.

    /ui2/cl_json=>deserialize( EXPORTING json = iv_body pretty_name = /ui2/cl_json=>pretty_mode-camel_case CHANGING data = ls_in ).
    IF condense( ls_in-instruction ) = ``.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Istruzione vuota` http_status = 400 ).
    ENDIF.

    DATA(ls_cfg) = NEW /reg/cl_ams_cfg( )->app_cfg_par.
    DATA(ls_choice) = resolve_portal( is_cfg = ls_cfg iv_instruction = ls_in-instruction iv_portal = ls_in-portal ).
    IF ls_choice-error IS NOT INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = ls_choice-error http_status = 422 ).
    ENDIF.
    check_portal( ls_choice-portal ).

    " Runner spento: lo si dice subito, senza creare l'operazione ne' chiamare il modello.
    IF /reg/cl_ams_agent=>runner_online( iv_consultant  = sy-uname
                                         iv_runner_kind = VALUE #( ls_cfg-portals[ portal = ls_choice-portal ]-runner_kind OPTIONAL ) ) = abap_false.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Il tuo runner non e' collegato: avvialo sul tuo PC (npm start nella cartella runner). ` &&
                                              `Se non l'hai ancora associato, genera il codice di associazione da Cinghy.`
                                       http_status = 409 ).
    ENDIF.

    DATA(lv_op_id) = /reg/cl_ams_op=>create( iv_portal      = ls_choice-portal
                                             iv_llm         = /reg/cl_ams_llm_factory=>resolve( is_cfg = ls_cfg iv_portal = ls_choice-portal )-llm
                                             iv_instruction = ls_in-instruction ).
    /reg/cl_ams_op=>schedule_step( lv_op_id ).
    rv_json = status_json( /reg/cl_ams_op=>get( lv_op_id ) ).
  ENDMETHOD.

  METHOD status.
    own_op( iv_op_id ).
    DATA(ls_cfg) = NEW /reg/cl_ams_cfg( )->app_cfg_par.
    /reg/cl_ams_op=>expire_if_stale( iv_op_id           = iv_op_id
                                     iv_max_steps       = ls_cfg-max_steps
                                     iv_timeout_minutes = ls_cfg-timeout_minutes ).
    rv_json = status_json( /reg/cl_ams_op=>get( iv_op_id ) ).
  ENDMETHOD.

  METHOD decision.
    TYPES: BEGIN OF ty_in,
             decision TYPE string,
             note     TYPE string,
           END OF ty_in.
    DATA ls_in TYPE ty_in.

    own_op( iv_op_id ).
    /ui2/cl_json=>deserialize( EXPORTING json = iv_body pretty_name = /ui2/cl_json=>pretty_mode-camel_case CHANGING data = ls_in ).
    DATA(lv_decision) = SWITCH char1( to_lower( ls_in-decision )
                                      WHEN `confirm` THEN /reg/cl_ams_agent=>c_decision-confirm
                                      WHEN `cancel`  THEN /reg/cl_ams_agent=>c_decision-cancel
                                      WHEN `modify`  THEN /reg/cl_ams_agent=>c_decision-modify ).
    IF lv_decision IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Decisione non valida: usa confirm, cancel o modify` http_status = 400 ).
    ENDIF.
    IF lv_decision = /reg/cl_ams_agent=>c_decision-modify AND condense( ls_in-note ) = ``.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Per modificare il piano scrivi cosa cambiare` http_status = 400 ).
    ENDIF.

    /reg/cl_ams_agent=>decide( iv_op_id = iv_op_id iv_decision = lv_decision iv_note = ls_in-note ).
    rv_json = status_json( /reg/cl_ams_op=>get( iv_op_id ) ).
  ENDMETHOD.

  METHOD own_op.
    TRY.
        rs_op = /reg/cl_ams_op=>get( iv_op_id ).
      CATCH /reg/cx_ams.
        CLEAR rs_op.
    ENDTRY.
    " Le operazioni degli altri consulenti non si vedono: stesso errore di un'operazione inesistente.
    IF rs_op IS INITIAL OR rs_op-consultant <> sy-uname.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Operazione non trovata` http_status = 404 ).
    ENDIF.
    check_portal( CONV #( rs_op-portal ) ).
  ENDMETHOD.

  METHOD check_portal.
    DATA lv_portal TYPE /reg/ams_portal.
    lv_portal = iv_portal.
    IF iv_portal IS INITIAL.
      AUTHORITY-CHECK OBJECT '/REG/AMS'
        ID '/REG/PORT' DUMMY
        ID 'ACTVT' FIELD '16'.
    ELSE.
      AUTHORITY-CHECK OBJECT '/REG/AMS'
        ID '/REG/PORT' FIELD lv_portal
        ID 'ACTVT' FIELD '16'.
    ENDIF.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW /reg/cx_ams( text = COND #( WHEN iv_portal IS INITIAL THEN `Non sei autorizzato all'agente AMS`
                                                      ELSE |Non sei autorizzato all'agente AMS sul portale { iv_portal }| )
                                       http_status = 403 ).
    ENDIF.
  ENDMETHOD.

  METHOD last_screenshot.
    SELECT screenshot FROM /reg/ams_step
      WHERE op_id = @iv_op_id AND tool = @/reg/cl_ams_tools=>c_tool-screenshot AND is_error = @abap_false
      ORDER BY seq DESCENDING
      INTO @rv_png
      UP TO 1 ROWS.
    ENDSELECT.
    IF rv_png IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = `Nessuno screenshot per questa operazione` http_status = 404 ).
    ENDIF.
  ENDMETHOD.

  METHOD reply.
    io_server->response->set_status( code = iv_status reason = COND #( WHEN iv_status = 200 THEN `OK` ELSE `Error` ) ).
    io_server->response->set_header_field( name = 'Content-Type' value = 'application/json; charset=utf-8' ).
    io_server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    io_server->response->set_cdata( iv_json ).
  ENDMETHOD.

  METHOD error_json.
    rv_json = |\{"error":{ /ui2/cl_json=>serialize( data = iv_text ) }\}|.
  ENDMETHOD.

ENDCLASS.
