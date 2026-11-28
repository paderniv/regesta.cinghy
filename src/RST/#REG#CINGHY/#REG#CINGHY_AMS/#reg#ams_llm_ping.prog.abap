*&---------------------------------------------------------------------*
*& Agente AMS: prova di collegamento a un modello linguistico.
*& 1) prova di testo: il modello deve rispondere OK;
*& 2) prova di strumento: il modello chiama get_ticket, riceve un
*&    risultato finto e risponde con il testo finale.
*& Usa la chiave di /REG/AMS_KEY per il codice modello P_LLM e non
*& legge TuneCraft: modello e destinazione sono parametri.
*&---------------------------------------------------------------------*
REPORT /reg/ams_llm_ping LINE-SIZE 1023.

PARAMETERS: p_llm  TYPE c LENGTH 20 DEFAULT 'OPENAI' OBLIGATORY,
            p_prov TYPE c LENGTH 20 DEFAULT 'OPENAI' OBLIGATORY,
            p_model TYPE c LENGTH 60 DEFAULT 'gpt-6.2-sol' LOWER CASE OBLIGATORY,
            p_dest TYPE rfcdest DEFAULT 'CINGHY_OPENAI' OBLIGATORY.

START-OF-SELECTION.
  DATA go_client TYPE REF TO /reg/if_ams_llm.

  TRY.
      go_client = /reg/cl_ams_llm_factory=>create( VALUE #( llm         = condense( p_llm )
                                                            provider    = condense( p_prov )
                                                            model       = condense( p_model )
                                                            destination = condense( p_dest ) ) ).

      " 1) Prova di testo.
      DATA(gs_text) = go_client->complete(
        is_conversation = VALUE #( system   = `Rispondi solo con la parola OK.`
                                   messages = VALUE #( ( role = /reg/if_ams_llm=>c_role-user text = `Prova di collegamento` ) ) )
        it_tools        = VALUE #( ) ).
      WRITE: / '1) Prova di testo', / '   fine:', gs_text-stop_reason,
             / '   token input/output:', gs_text-input_tokens, gs_text-output_tokens,
             / '   risposta:', gs_text-text.
      ULINE.

      " 2) Prova di strumento: chiamata, risultato, risposta finale.
      DATA(gt_tools) = VALUE /reg/if_ams_llm=>ty_tools(
        ( name        = `get_ticket`
          description = `Legge un ticket del portale per numero e ne restituisce stato e titolo.`
          parameters  = `{"type":"object","properties":{"ticket_id":{"type":"string","description":"Numero del ticket"}},"required":["ticket_id"]}` ) ).
      DATA(gs_conversation) = VALUE /reg/if_ams_llm=>ty_conversation(
        system   = `Sei un agente di prova. Usa gli strumenti per leggere i ticket e poi rispondi in una frase.`
        messages = VALUE #( ( role = /reg/if_ams_llm=>c_role-user text = `Qual e' lo stato del ticket 42?` ) ) ).

      DATA(gs_call) = go_client->complete( is_conversation = gs_conversation it_tools = gt_tools ).
      WRITE: / '2a) Chiamata allo strumento', / '   fine:', gs_call-stop_reason,
             / '   token input/output:', gs_call-input_tokens, gs_call-output_tokens.
      LOOP AT gs_call-tool_calls INTO DATA(gs_tool_call).
        WRITE: / '   strumento:', gs_tool_call-name, gs_tool_call-arguments.
      ENDLOOP.

      IF gs_call-tool_calls IS INITIAL.
        WRITE: / '   ATTENZIONE: il modello non ha chiamato lo strumento. Risposta:', gs_call-text.
        RETURN.
      ENDIF.

      APPEND VALUE #( role          = /reg/if_ams_llm=>c_role-assistant
                      text          = gs_call-text
                      tool_calls    = gs_call-tool_calls
                      provider_data = gs_call-provider_data ) TO gs_conversation-messages.
      LOOP AT gs_call-tool_calls INTO gs_tool_call.
        APPEND VALUE #( role         = /reg/if_ams_llm=>c_role-tool
                        tool_call_id = gs_tool_call-id
                        tool_name    = gs_tool_call-name
                        text         = `{"ticket_id":"42","stato":"In lavorazione","titolo":"Stampa fatture bloccata"}` )
               TO gs_conversation-messages.
      ENDLOOP.

      DATA(gs_final) = go_client->complete( is_conversation = gs_conversation it_tools = gt_tools ).
      WRITE: / '2b) Risposta dopo il risultato', / '   fine:', gs_final-stop_reason,
             / '   token input/output:', gs_final-input_tokens, gs_final-output_tokens,
             / '   risposta:', gs_final-text.

    CATCH /reg/cx_ams INTO DATA(gx_error).
      WRITE: / 'ERRORE:', gx_error->get_text( ).
      IF gx_error->http_status IS NOT INITIAL.
        WRITE: / 'Stato HTTP:', gx_error->http_status, 'retry-after:', gx_error->retry_after.
      ENDIF.
  ENDTRY.