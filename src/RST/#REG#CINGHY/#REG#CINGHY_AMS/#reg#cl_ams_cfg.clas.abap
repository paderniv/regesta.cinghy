"! Configurazione dell'agente AMS letta da TuneCraft (app CINGHY_AMS, variante blank):
"! impostazioni dell'agente e profili dei portali clienti. Nessun segreto qui dentro.
CLASS /reg/cl_ams_cfg DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Nome dell'app in TuneCraft. Dichiarato solo qui: il reader distingue maiuscole e minuscole.
    CONSTANTS c_app_name TYPE /reg/e_tc_app VALUE 'CINGHY_AMS' ##NO_TEXT.

    TYPES:
      BEGIN OF ty_portal,
        portal       TYPE string,
        customer     TYPE string,
        entry_url    TYPE string,
        runner_kind  TYPE string,
        login_mode   TYPE string,
        active       TYPE abap_bool,
        instructions TYPE string,
        llm          TYPE string,
      END OF ty_portal,
      BEGIN OF ty_llm,
        llm               TYPE string,
        provider          TYPE string,
        model             TYPE string,
        destination       TYPE string,
        max_output_tokens TYPE i,
      END OF ty_llm,
      BEGIN OF ty_domain,
        portal   TYPE string,
        domain   TYPE string,
        is_login TYPE abap_bool,
      END OF ty_domain,
      BEGIN OF ty_button,
        portal TYPE string,
        label  TYPE string,
      END OF ty_button,
      BEGIN OF ty_value,
        portal       TYPE string,
        field        TYPE string,
        requested    TYPE string,
        portal_value TYPE string,
      END OF ty_value,
      BEGIN OF ty_app_config,
        default_llm     TYPE string,
        llms            TYPE STANDARD TABLE OF ty_llm WITH EMPTY KEY,
        max_steps       TYPE i,
        timeout_minutes TYPE i,
        portals         TYPE STANDARD TABLE OF ty_portal WITH EMPTY KEY,
        portal_domains  TYPE STANDARD TABLE OF ty_domain WITH EMPTY KEY,
        safe_buttons    TYPE STANDARD TABLE OF ty_button WITH EMPTY KEY,
        forbidden_elements TYPE STANDARD TABLE OF ty_button WITH EMPTY KEY,
        value_map      TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY,
      END OF ty_app_config.

    DATA app_cfg_par TYPE ty_app_config READ-ONLY.

    "! @parameter iv_json | Configurazione JSON gia' letta (test); vuoto = lettura da TuneCraft
    "! @raising cx_static_check | /REG/CX_CONFIG_NOT_FOUND se CINGHY_AMS non e' configurata in TuneCraft Run
    METHODS constructor
      IMPORTING iv_json TYPE string OPTIONAL
      RAISING   cx_static_check.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! Valori dei parametri nuovi non ancora presenti nello schema TuneCraft del sistema.
    "! Lo schema si aggiorna all'archive della change; da allora vale il valore di TuneCraft.
    METHODS set_defaults.
ENDCLASS.


CLASS /reg/cl_ams_cfg IMPLEMENTATION.

  METHOD constructor.
    DATA(lv_json) = iv_json.
    IF lv_json IS INITIAL.
      TRY.
          lv_json = /reg/cl_tunecraft_cfg_reader=>get_instance( )->get_configuration( iv_appname = c_app_name ).
        CATCH cx_static_check INTO DATA(lx_reader).
          " Il testo dell'eccezione del reader non dice cosa manca: lo diciamo noi.
          RAISE EXCEPTION NEW /reg/cx_ams(
            text     = |Configurazione TuneCraft { c_app_name } non trovata: importare schema in TuneCraft Build e configurazione in TuneCraft Run|
            previous = lx_reader ).
      ENDTRY.
    ENDIF.
    /ui2/cl_json=>deserialize( EXPORTING json = lv_json
                               CHANGING  data = app_cfg_par ).
    set_defaults( ).
  ENDMETHOD.

  METHOD set_defaults.
    " FORBIDDEN_ELEMENTS (add-ams-portal-agent): il link Timer di Pittini avvia il conteggio del tempo.
    IF app_cfg_par-forbidden_elements IS INITIAL.
      app_cfg_par-forbidden_elements = VALUE #( ( portal = `PITTINI` label = `Timer` ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
