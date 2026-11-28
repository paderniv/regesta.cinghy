CLASS ltc_factory DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    DATA ms_cfg TYPE /reg/cl_ams_cfg=>ty_app_config.
    METHODS setup.
    METHODS portal_uses_default_llm FOR TESTING RAISING cx_static_check.
    METHODS portal_with_own_llm FOR TESTING RAISING cx_static_check.
    METHODS unknown_portal_raises FOR TESTING.
    METHODS unknown_llm_raises FOR TESTING.
    METHODS unknown_provider_raises FOR TESTING.
    METHODS adapter_per_provider FOR TESTING.
ENDCLASS.


CLASS ltc_factory IMPLEMENTATION.

  METHOD setup.
    ms_cfg = VALUE #( default_llm = `OPENAI`
                      llms        = VALUE #( ( llm = `OPENAI` provider = `OPENAI` model = `m1` destination = `D1` )
                                             ( llm = `GEMINI` provider = `GEMINI` model = `m2` destination = `D2` )
                                             ( llm = `ODD`    provider = `NOBODY` model = `m3` destination = `D3` ) )
                      portals     = VALUE #( ( portal = `PITTINI` )
                                             ( portal = `ALTRO` llm = `GEMINI` )
                                             ( portal = `ROTTO` llm = `MANCA` ) ) ).
  ENDMETHOD.

  METHOD portal_uses_default_llm.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_llm_factory=>resolve( is_cfg = ms_cfg iv_portal = `PITTINI` )-llm
                                        exp = `OPENAI` ).
  ENDMETHOD.

  METHOD portal_with_own_llm.
    DATA(ls_llm) = /reg/cl_ams_llm_factory=>resolve( is_cfg = ms_cfg iv_portal = `ALTRO` ).
    cl_abap_unit_assert=>assert_equals( act = ls_llm-llm exp = `GEMINI` ).
    cl_abap_unit_assert=>assert_equals( act = ls_llm-destination exp = `D2` ).
  ENDMETHOD.

  METHOD unknown_portal_raises.
    TRY.
        /reg/cl_ams_llm_factory=>resolve( is_cfg = ms_cfg iv_portal = `NESSUNO` ).
        cl_abap_unit_assert=>fail( `atteso errore per portale non configurato` ).
      CATCH /reg/cx_ams INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( ) exp = `*NESSUNO*` ).
    ENDTRY.
  ENDMETHOD.

  METHOD unknown_llm_raises.
    TRY.
        /reg/cl_ams_llm_factory=>resolve( is_cfg = ms_cfg iv_portal = `ROTTO` ).
        cl_abap_unit_assert=>fail( `atteso errore per modello non in LLMS` ).
      CATCH /reg/cx_ams INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( ) exp = `*MANCA*` ).
    ENDTRY.
  ENDMETHOD.

  METHOD unknown_provider_raises.
    TRY.
        /reg/cl_ams_llm_factory=>create( ms_cfg-llms[ llm = `ODD` ] ).
        cl_abap_unit_assert=>fail( `atteso errore per fornitore sconosciuto` ).
      CATCH /reg/cx_ams INTO DATA(lx).
        cl_abap_unit_assert=>assert_char_cp( act = lx->get_text( ) exp = `*NOBODY*` ).
    ENDTRY.
  ENDMETHOD.

  METHOD adapter_per_provider.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_llm_factory=>adapter_class( `openai` )
                                        exp = '/REG/CL_AMS_LLM_OPENAI' ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_llm_factory=>adapter_class( `GEMINI` )
                                        exp = '/REG/CL_AMS_LLM_GEMINI' ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_llm_factory=>adapter_class( `ANTHROPIC` )
                                        exp = '/REG/CL_AMS_LLM_ANTHROPIC' ).
    cl_abap_unit_assert=>assert_initial( /reg/cl_ams_llm_factory=>adapter_class( `NOBODY` ) ).
  ENDMETHOD.

ENDCLASS.