"! Sceglie il modello di un portale e crea l'adattatore del suo fornitore.
CLASS /reg/cl_ams_llm_factory DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Modello del portale se indicato, altrimenti il predefinito.
    "! @raising /reg/cx_ams | Portale o modello non configurati in TuneCraft
    CLASS-METHODS resolve
      IMPORTING is_cfg        TYPE /reg/cl_ams_cfg=>ty_app_config
                iv_portal     TYPE string
      RETURNING VALUE(rs_llm) TYPE /reg/cl_ams_cfg=>ty_llm
      RAISING   /reg/cx_ams.

    "! Modello con il codice registrato nell'operazione: resta lo stesso fino alla fine.
    "! @raising /reg/cx_ams | Modello non piu' configurato in TuneCraft
    CLASS-METHODS by_code
      IMPORTING is_cfg        TYPE /reg/cl_ams_cfg=>ty_app_config
                iv_llm        TYPE string
      RETURNING VALUE(rs_llm) TYPE /reg/cl_ams_cfg=>ty_llm
      RAISING   /reg/cx_ams.

    "! Adattatore del fornitore del modello. Ogni adattatore ha un costruttore con is_llm.
    "! @raising /reg/cx_ams | Fornitore sconosciuto o adattatore non ancora disponibile
    CLASS-METHODS create
      IMPORTING is_llm           TYPE /reg/cl_ams_cfg=>ty_llm
      RETURNING VALUE(ro_client) TYPE REF TO /reg/if_ams_llm
      RAISING   /reg/cx_ams.

    "! Classe dell'adattatore per un tipo di fornitore; vuoto se il fornitore e' sconosciuto.
    CLASS-METHODS adapter_class
      IMPORTING iv_provider     TYPE string
      RETURNING VALUE(rv_class) TYPE seoclsname.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /reg/cl_ams_llm_factory IMPLEMENTATION.

  METHOD resolve.
    IF NOT line_exists( is_cfg-portals[ portal = iv_portal ] ).
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Portale { iv_portal } non configurato in TuneCraft (CINGHY_AMS)| ).
    ENDIF.
    DATA(lv_llm) = is_cfg-portals[ portal = iv_portal ]-llm.
    rs_llm = by_code( is_cfg = is_cfg
                      iv_llm = COND #( WHEN lv_llm IS NOT INITIAL THEN lv_llm ELSE is_cfg-default_llm ) ).
  ENDMETHOD.

  METHOD by_code.
    rs_llm = VALUE #( is_cfg-llms[ llm = iv_llm ] OPTIONAL ).
    IF rs_llm IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Modello "{ iv_llm }" non presente in LLMS di TuneCraft (CINGHY_AMS)| ).
    ENDIF.
  ENDMETHOD.

  METHOD create.
    DATA(lv_class) = adapter_class( is_llm-provider ).
    IF lv_class IS INITIAL.
      RAISE EXCEPTION NEW /reg/cx_ams( text = |Fornitore "{ is_llm-provider }" del modello { is_llm-llm } sconosciuto| ).
    ENDIF.
    " Creazione dinamica: un adattatore si aggiunge senza toccare il resto del codice.
    TRY.
        CREATE OBJECT ro_client TYPE (lv_class) EXPORTING is_llm = is_llm.
      CATCH cx_sy_create_object_error INTO DATA(lx_create).
        RAISE EXCEPTION NEW /reg/cx_ams( text     = |Adattatore { lv_class } non disponibile|
                                         previous = lx_create ).
    ENDTRY.
  ENDMETHOD.

  METHOD adapter_class.
    rv_class = SWITCH #( to_upper( iv_provider )
                         WHEN `OPENAI`    THEN '/REG/CL_AMS_LLM_OPENAI'
                         WHEN `GEMINI`    THEN '/REG/CL_AMS_LLM_GEMINI'
                         WHEN `ANTHROPIC` THEN '/REG/CL_AMS_LLM_ANTHROPIC' ).
  ENDMETHOD.

ENDCLASS.
