"! Servizio HTTP dell'agente AMS per i runner (handler di un nodo SICF proprio, design 4 e 5).
"! Il runner non usa credenziali SAP: il nodo SICF ha un utente di servizio tecnico e ogni richiesta
"! si autentica con il token del runner nell'header X-AMS-Token (non Authorization, che l'ICF usa
"! per il proprio logon). JSON in e out.
"!   POST /pair                     {code, name?}                         -> {token}  (una sola volta)
"!   GET  /actions                  long polling fino a c_poll_seconds   -> [{stepId, opId, tool, args, allowedDomains, loginDomains}]
"!   POST /actions/{stepId}/result  {result, isError, summary?, loginRequired?, screenshot? (base64 PNG)}
CLASS /reg/cl_ams_http_runner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.

    CONSTANTS c_poll_seconds TYPE i VALUE 30.
    CONSTANTS c_poll_interval TYPE i VALUE 2.
    CONSTANTS:
      BEGIN OF c_endpoint,
        pair    TYPE string VALUE `PAIR`,
        actions TYPE string VALUE `ACTIONS`,
        result  TYPE string VALUE `RESULT`,
      END OF c_endpoint.

    TYPES:
      BEGIN OF ty_route,
        endpoint TYPE string,
        step_id  TYPE sysuuid_x16,
      END OF ty_route.

    CLASS-METHODS route
      IMPORTING iv_method       TYPE string
                iv_path         TYPE string
      RETURNING VALUE(rs_route) TYPE ty_route.

    CLASS-METHODS actions_json
      IMPORTING it_actions     TYPE /reg/cl_ams_runner=>ty_actions
      RETURNING VALUE(rv_json) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS reply
      IMPORTING io_server TYPE REF TO if_http_server
                iv_status TYPE i
                iv_json   TYPE string.
ENDCLASS.


CLASS /reg/cl_ams_http_runner IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    TYPES: BEGIN OF ty_pair,
             code TYPE string,
             name TYPE string,
           END OF ty_pair,
           BEGIN OF ty_result,
             result         TYPE string,
             is_error       TYPE abap_bool,
             summary        TYPE string,
             login_required TYPE abap_bool,
             screenshot     TYPE string,
           END OF ty_result.
    DATA ls_pair TYPE ty_pair.
    DATA ls_result TYPE ty_result.

    DATA(lv_method) = to_upper( server->request->get_header_field( '~request_method' ) ).
    DATA(ls_route)  = route( iv_method = lv_method iv_path = server->request->get_header_field( '~path_info' ) ).

    TRY.
        CASE ls_route-endpoint.
          WHEN c_endpoint-pair.
            /ui2/cl_json=>deserialize( EXPORTING json = server->request->get_cdata( ) CHANGING data = ls_pair ).
            DATA(lv_token) = /reg/cl_ams_runner=>pair( iv_code = ls_pair-code iv_name = ls_pair-name ).
            COMMIT WORK.
            reply( io_server = server iv_status = 200
                   iv_json   = |\{"token":{ /ui2/cl_json=>serialize( data = lv_token ) }\}| ).

          WHEN c_endpoint-actions.
            DATA(ls_runner) = /reg/cl_ams_runner=>authenticate( condense( server->request->get_header_field( 'x-ams-token' ) ) ).
            COMMIT WORK.
            DATA(ls_cfg) = NEW /reg/cl_ams_cfg( )->app_cfg_par.
            " Long polling: la richiesta resta aperta finche' non c'e' un'azione o finche' scade il tempo.
            DATA(lv_waited) = 0.
            DO.
              DATA(lt_actions) = /reg/cl_ams_runner=>take_actions( is_runner = ls_runner is_cfg = ls_cfg ).
              IF lt_actions IS NOT INITIAL OR lv_waited >= c_poll_seconds.
                COMMIT WORK.
                EXIT.
              ENDIF.
              WAIT UP TO c_poll_interval SECONDS.
              lv_waited += c_poll_interval.
            ENDDO.
            reply( io_server = server iv_status = 200 iv_json = actions_json( lt_actions ) ).

          WHEN c_endpoint-result.
            ls_runner = /reg/cl_ams_runner=>authenticate( condense( server->request->get_header_field( 'x-ams-token' ) ) ).
            /ui2/cl_json=>deserialize( EXPORTING json        = server->request->get_cdata( )
                                                 pretty_name = /ui2/cl_json=>pretty_mode-camel_case
                                       CHANGING  data        = ls_result ).
            /reg/cl_ams_runner=>report_result(
              is_runner         = ls_runner
              iv_step_id        = ls_route-step_id
              iv_result         = ls_result-result
              iv_is_error       = ls_result-is_error
              iv_summary        = ls_result-summary
              iv_login_required = ls_result-login_required
              iv_screenshot     = COND #( WHEN ls_result-screenshot IS NOT INITIAL
                                          THEN cl_http_utility=>decode_x_base64( ls_result-screenshot ) ) ).
            COMMIT WORK.
            reply( io_server = server iv_status = 200 iv_json = `{"ok":true}` ).

          WHEN OTHERS.
            RAISE EXCEPTION NEW /reg/cx_ams( text = |Percorso { lv_method } non previsto| http_status = 404 ).
        ENDCASE.

      CATCH /reg/cx_ams INTO DATA(lx_ams).
        ROLLBACK WORK.
        reply( io_server = server
               iv_status = COND #( WHEN lx_ams->http_status BETWEEN 400 AND 499 THEN lx_ams->http_status ELSE 400 )
               iv_json   = |\{"error":{ /ui2/cl_json=>serialize( data = lx_ams->get_text( ) ) }\}| ).
      CATCH cx_static_check INTO DATA(lx_error).
        ROLLBACK WORK.
        reply( io_server = server iv_status = 500
               iv_json   = |\{"error":{ /ui2/cl_json=>serialize( data = lx_error->get_text( ) ) }\}| ).
    ENDTRY.
  ENDMETHOD.

  METHOD route.
    SPLIT iv_path AT `/` INTO TABLE DATA(lt_parts).
    DELETE lt_parts WHERE table_line IS INITIAL.

    CASE lines( lt_parts ).
      WHEN 1.
        rs_route-endpoint = COND #( WHEN iv_method = `POST` AND lt_parts[ 1 ] = `pair`    THEN c_endpoint-pair
                                    WHEN iv_method = `GET`  AND lt_parts[ 1 ] = `actions` THEN c_endpoint-actions ).
      WHEN 3.
        DATA(lv_id) = to_upper( lt_parts[ 2 ] ).
        IF iv_method = `POST` AND lt_parts[ 1 ] = `actions` AND lt_parts[ 3 ] = `result`
           AND strlen( lv_id ) = 32 AND lv_id CO '0123456789ABCDEF'.
          rs_route-endpoint = c_endpoint-result.
          rs_route-step_id  = lv_id.
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD actions_json.
    TYPES: BEGIN OF ty_out,
             step_id         TYPE string,
             op_id           TYPE string,
             tool            TYPE string,
             args            TYPE /ui2/cl_json=>json,
             allowed_domains TYPE string_table,
             login_domains   TYPE string_table,
           END OF ty_out,
           ty_outs TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    rv_json = /ui2/cl_json=>serialize(
      data        = VALUE ty_outs( FOR a IN it_actions
                                   ( step_id         = |{ a-step_id }|
                                     op_id           = |{ a-op_id }|
                                     tool            = a-tool
                                     args            = COND #( WHEN a-args IS INITIAL THEN `{}` ELSE a-args )
                                     allowed_domains = a-allowed_domains
                                     login_domains   = a-login_domains ) )
      pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
  ENDMETHOD.

  METHOD reply.
    io_server->response->set_status( code = iv_status reason = COND #( WHEN iv_status = 200 THEN `OK` ELSE `Error` ) ).
    io_server->response->set_header_field( name = 'Content-Type' value = 'application/json; charset=utf-8' ).
    io_server->response->set_header_field( name = 'Cache-Control' value = 'no-store' ).
    io_server->response->set_cdata( iv_json ).
  ENDMETHOD.

ENDCLASS.
