CLASS ltc_cfg DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS maps_config_json FOR TESTING RAISING cx_static_check.
ENDCLASS.


CLASS ltc_cfg IMPLEMENTATION.

  METHOD maps_config_json.
    " Stessa forma di Tunecraft--CINGHY_AMS--config.json.
    DATA(lv_json) =
      `{"DEFAULT_LLM":"OPENAI","LLMS":[` &&
      `{"LLM":"OPENAI","PROVIDER":"OPENAI","MODEL":"m1","DESTINATION":"CINGHY_OPENAI","MAX_OUTPUT_TOKENS":8000},` &&
      `{"LLM":"GEMINI","PROVIDER":"GEMINI","MODEL":"m2","DESTINATION":"CINGHY_GEMINI"}],` &&
      `"MAX_STEPS":40,"TIMEOUT_MINUTES":15,` &&
      `"PORTALS":[{"PORTAL":"PITTINI","CUSTOMER":"Pittini","ENTRY_URL":"https://hdserver.pittini.it/",` &&
      `"RUNNER_KIND":"LOCAL","LOGIN_MODE":"SHARED_ACCOUNT","ACTIVE":true,"INSTRUCTIONS":"x","LLM":"GEMINI"}],` &&
      `"PORTAL_DOMAINS":[{"PORTAL":"PITTINI","DOMAIN":"hdserver.pittini.it","IS_LOGIN":false},` &&
      `{"PORTAL":"PITTINI","DOMAIN":"login.microsoftonline.com","IS_LOGIN":true}],` &&
      `"SAFE_BUTTONS":[{"PORTAL":"PITTINI","LABEL":"Cerca"}],` &&
      `"VALUE_MAP":[{"PORTAL":"PITTINI","FIELD":"PRIORITA","REQUESTED":"alta","PORTAL_VALUE":"P2"}]}`.

    DATA(ls_cfg) = NEW /reg/cl_ams_cfg( lv_json )->app_cfg_par.

    cl_abap_unit_assert=>assert_equals( act = ls_cfg-default_llm exp = `OPENAI` ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-llms[ llm = `GEMINI` ]-provider exp = `GEMINI` ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-llms[ llm = `OPENAI` ]-max_output_tokens exp = 8000 ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-portals[ 1 ]-llm exp = `GEMINI` ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-max_steps exp = 40 ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-portals[ 1 ]-entry_url exp = `https://hdserver.pittini.it/` ).
    cl_abap_unit_assert=>assert_true( ls_cfg-portals[ 1 ]-active ).
    cl_abap_unit_assert=>assert_true( ls_cfg-portal_domains[ domain = `login.microsoftonline.com` ]-is_login ).
    cl_abap_unit_assert=>assert_false( ls_cfg-portal_domains[ domain = `hdserver.pittini.it` ]-is_login ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-safe_buttons[ 1 ]-label exp = `Cerca` ).
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-value_map[ 1 ]-portal_value exp = `P2` ).
    " Parametro nuovo assente dal JSON: vale il default di set_defaults.
    cl_abap_unit_assert=>assert_equals( act = ls_cfg-forbidden_elements[ 1 ]-label exp = `Timer` ).
  ENDMETHOD.

ENDCLASS.