CLASS ltc_conv DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS conversation
      IMPORTING iv_page_chars          TYPE i
      RETURNING VALUE(rs_conversation) TYPE /reg/if_ams_llm=>ty_conversation.
    METHODS below_threshold_unchanged FOR TESTING.
    METHODS above_threshold_keeps_last FOR TESTING.
    METHODS json_roundtrip_identical FOR TESTING.
ENDCLASS.


CLASS ltc_conv IMPLEMENTATION.

  METHOD conversation.
    DATA(lv_page) = repeat( val = `x` occ = iv_page_chars ).
    rs_conversation = VALUE #(
      system   = `regole`
      messages = VALUE #(
        ( role = /reg/if_ams_llm=>c_role-user text = `Pittini: leggi il ticket 12345` )
        ( role = /reg/if_ams_llm=>c_role-assistant
          tool_calls = VALUE #( ( id = `c1` name = `browser_navigate` arguments = `{"url":"https://hdserver.pittini.it/list"}` ) ) )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `c1` tool_name = `browser_navigate`
          text = lv_page reducible = abap_true summary = `pagina "Lista ticket" letta` )
        ( role = /reg/if_ams_llm=>c_role-assistant
          tool_calls = VALUE #( ( id = `c2` name = `browser_click` arguments = `{"element":"12345"}` ) ) )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `c2` tool_name = `browser_click`
          text = lv_page reducible = abap_true summary = `pagina "Ticket 12345" letta` )
        ( role = /reg/if_ams_llm=>c_role-assistant
          tool_calls = VALUE #( ( id = `c3` name = `browser_click` arguments = `{"element":"Commenti"}` ) ) )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `c3` tool_name = `browser_click`
          text = lv_page reducible = abap_true summary = `pagina "Commenti 12345" letta` )
        ( role = /reg/if_ams_llm=>c_role-tool tool_call_id = `c4` tool_name = `browser_type`
          text = `errore: campo non trovato` is_error = abap_true ) ) ).
  ENDMETHOD.

  METHOD below_threshold_unchanged.
    DATA(ls_conversation) = conversation( 1000 ).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_conv=>reduce( ls_conversation )
                                        exp = ls_conversation ).
  ENDMETHOD.

  METHOD above_threshold_keeps_last.
    DATA(ls_conversation) = conversation( 4000 ).

    DATA(ls_reduced) = /reg/cl_ams_conv=>reduce( is_conversation = ls_conversation iv_threshold = 2000 ).

    cl_abap_unit_assert=>assert_equals( act = ls_reduced-messages[ 3 ]-text exp = `pagina "Lista ticket" letta` ).
    cl_abap_unit_assert=>assert_equals( act = ls_reduced-messages[ 5 ]-text exp = `pagina "Ticket 12345" letta` ).
    " L'ultima descrizione di pagina resta completa, il resto non cambia.
    cl_abap_unit_assert=>assert_equals( act = ls_reduced-messages[ 7 ] exp = ls_conversation-messages[ 7 ] ).
    cl_abap_unit_assert=>assert_equals( act = ls_reduced-messages[ 8 ] exp = ls_conversation-messages[ 8 ] ).
    cl_abap_unit_assert=>assert_equals( act = ls_reduced-messages[ 2 ] exp = ls_conversation-messages[ 2 ] ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_reduced-messages ) exp = lines( ls_conversation-messages ) ).
    " Una seconda riduzione non tocca piu' le righe gia' ridotte.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_conv=>reduce( is_conversation = ls_reduced iv_threshold = 0 )
                                        exp = ls_reduced ).
  ENDMETHOD.

  METHOD json_roundtrip_identical.
    DATA(ls_conversation) = conversation( 50 ).
    ls_conversation-messages[ 1 ]-text = |righe\nnuove, "virgolette" e àccenti|.

    DATA(ls_back) = /reg/cl_ams_conv=>from_json( /reg/cl_ams_conv=>to_json( ls_conversation ) ).

    cl_abap_unit_assert=>assert_equals( act = ls_back exp = ls_conversation ).
  ENDMETHOD.

ENDCLASS.