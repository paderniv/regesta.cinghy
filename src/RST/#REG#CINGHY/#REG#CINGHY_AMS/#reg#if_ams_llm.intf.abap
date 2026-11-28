"! Client di un modello linguistico, indipendente dal fornitore.
"! Conversazione e risposta sono nel formato neutro dell'agente AMS: un adattatore per fornitore
"! (OpenAI, Gemini, Anthropic) lo traduce nell'API del fornitore e viceversa.
INTERFACE /reg/if_ams_llm PUBLIC.

  CONSTANTS:
    BEGIN OF c_role,
      user      TYPE string VALUE `user`,
      assistant TYPE string VALUE `assistant`,
      tool      TYPE string VALUE `tool`,
    END OF c_role,
    BEGIN OF c_stop,
      end_turn   TYPE string VALUE `END_TURN`,
      tool_use   TYPE string VALUE `TOOL_USE`,
      max_tokens TYPE string VALUE `MAX_TOKENS`,
      refused    TYPE string VALUE `REFUSED`,
    END OF c_stop.

  TYPES:
    "! Chiamata a uno strumento chiesta dal modello. arguments e' un oggetto JSON.
    BEGIN OF ty_tool_call,
      id        TYPE string,
      name      TYPE string,
      arguments TYPE string,
    END OF ty_tool_call,
    ty_tool_calls TYPE STANDARD TABLE OF ty_tool_call WITH EMPTY KEY,

    "! Un messaggio della conversazione.
    "! user: text. assistant: text e/o tool_calls. tool: risultato della chiamata tool_call_id.
    BEGIN OF ty_message,
      role         TYPE string,
      text         TYPE string,
      tool_calls   TYPE ty_tool_calls,
      tool_call_id TYPE string,
      tool_name    TYPE string,
      is_error     TYPE abap_bool,
      "! Risultato riducibile (descrizione di pagina): text puo' essere sostituito da summary.
      reducible    TYPE abap_bool,
      summary      TYPE string,
      "! Solo assistant: contenuto grezzo del turno nel formato del fornitore (per esempio
      "! firme del ragionamento), rimandato tale e quale allo stesso fornitore. Il resto del
      "! codice non lo legge: l'operazione usa sempre lo stesso modello.
      provider_data TYPE string,
    END OF ty_message,
    ty_messages TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY,

    "! Strumento dichiarato al modello. parameters e' un JSON Schema di tipo object.
    BEGIN OF ty_tool,
      name        TYPE string,
      description TYPE string,
      parameters  TYPE string,
    END OF ty_tool,
    ty_tools TYPE STANDARD TABLE OF ty_tool WITH EMPTY KEY,

    BEGIN OF ty_conversation,
      system   TYPE string,
      messages TYPE ty_messages,
    END OF ty_conversation,

    BEGIN OF ty_response,
      text          TYPE string,
      tool_calls    TYPE ty_tool_calls,
      stop_reason   TYPE string,
      input_tokens  TYPE i,
      output_tokens TYPE i,
      "! Da copiare nel messaggio assistant che registra questa risposta.
      provider_data TYPE string,
    END OF ty_response.

  "! Una chiamata al modello con tutta la conversazione e gli strumenti disponibili.
  "! @raising /reg/cx_ams | Errore HTTP, limite di frequenza, risposta non interpretabile
  METHODS complete
    IMPORTING is_conversation    TYPE ty_conversation
              it_tools           TYPE ty_tools
    RETURNING VALUE(rs_response) TYPE ty_response
    RAISING   /reg/cx_ams.

ENDINTERFACE.