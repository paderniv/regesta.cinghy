"! POST JSON verso l'API di un fornitore di modelli, tramite destinazione SM59 di tipo G.
"! Nessun nuovo tentativo qui: un 429 o un 5xx risale come /REG/CX_AMS con lo stato HTTP e
"! retry_after, e il ciclo dell'agente decide se rimandare l'operazione.
CLASS /reg/cl_ams_http DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_header,
        name  TYPE string,
        value TYPE string,
      END OF ty_header,
      ty_headers TYPE STANDARD TABLE OF ty_header WITH EMPTY KEY.

    "! @parameter iv_path | Percorso dopo quello della destinazione, per esempio /v1/responses
    "! @raising /reg/cx_ams | Errore di comunicazione o stato HTTP diverso da 2xx
    CLASS-METHODS post_json
      IMPORTING iv_destination TYPE string
                iv_path        TYPE string
                it_headers     TYPE ty_headers OPTIONAL
                iv_body        TYPE string
      RETURNING VALUE(rv_body) TYPE string
      RAISING   /reg/cx_ams.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /reg/cl_ams_http IMPLEMENTATION.

  METHOD post_json.
    DATA lo_client TYPE REF TO if_http_client.
    DATA lv_destination TYPE rfcdest.

    lv_destination = iv_destination.
    cl_http_client=>create_by_destination( EXPORTING  destination              = lv_destination
                                           IMPORTING  client                   = lo_client
                                           EXCEPTIONS argument_not_found       = 1
                                                      destination_not_found    = 2
                                                      destination_no_authority = 3
                                                      plugin_not_active        = 4
                                                      internal_error           = 5
                                                      OTHERS                   = 6 ).
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Destinazione SM59 { iv_destination } non utilizzabile (errore { sy-subrc })| ).
    ENDIF.

    lo_client->request->set_method( if_http_request=>co_request_method_post ).
    cl_http_utility=>set_request_uri( request = lo_client->request uri = iv_path ).
    lo_client->request->set_header_field( name = 'Content-Type' value = 'application/json' ).
    LOOP AT it_headers INTO DATA(ls_header).
      lo_client->request->set_header_field( name = ls_header-name value = ls_header-value ).
    ENDLOOP.
    lo_client->request->set_cdata( iv_body ).

    lo_client->send( EXCEPTIONS http_communication_failure = 1
                                http_invalid_state         = 2
                                http_processing_failed     = 3
                                http_invalid_timeout       = 4
                                OTHERS                     = 5 ).
    IF sy-subrc = 0.
      lo_client->receive( EXCEPTIONS http_communication_failure = 1
                                     http_invalid_state         = 2
                                     http_processing_failed     = 3
                                     OTHERS                     = 4 ).
    ENDIF.
    IF sy-subrc <> 0.
      lo_client->get_last_error( IMPORTING message = DATA(lv_message) ).
      lo_client->close( ).
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Chiamata a { iv_destination } fallita: { lv_message }| ).
    ENDIF.

    lo_client->response->get_status( IMPORTING code = DATA(lv_status) ).
    rv_body = lo_client->response->get_cdata( ).
    DATA(lv_retry_after) = lo_client->response->get_header_field( 'retry-after' ).
    lo_client->close( ).

    IF lv_status < 200 OR lv_status >= 300.
      " Il corpo dell'errore non contiene la chiave: i fornitori non la ripetono nelle risposte.
      RAISE EXCEPTION NEW /reg/cx_ams( text        = |{ iv_destination }: HTTP { lv_status } { substring( val = rv_body len = nmin( val1 = 500 val2 = strlen( rv_body ) ) ) }|
                                       http_status = lv_status
                                       retry_after = COND #( WHEN lv_retry_after CO '0123456789' AND lv_retry_after IS NOT INITIAL
                                                             THEN CONV i( lv_retry_after ) ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
