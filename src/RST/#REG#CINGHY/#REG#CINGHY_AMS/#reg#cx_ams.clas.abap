"! Errore dell'agente AMS: chiamata al modello, configurazione, dati dell'operazione.
CLASS /reg/cx_ams DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Testo per il consulente e per il registro.
    DATA text TYPE string READ-ONLY.
    "! Stato HTTP della risposta del fornitore del modello; 0 se l'errore non viene da li'.
    DATA http_status TYPE i READ-ONLY.
    "! Secondi di attesa suggeriti dal fornitore (header retry-after); 0 se non indicati.
    DATA retry_after TYPE i READ-ONLY.

    METHODS constructor
      IMPORTING textid      LIKE textid OPTIONAL
                previous    LIKE previous OPTIONAL
                text        TYPE string OPTIONAL
                http_status TYPE i OPTIONAL
                retry_after TYPE i OPTIONAL.

    METHODS get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /reg/cx_ams IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( textid = textid previous = previous ).
    me->text = text.
    me->http_status = http_status.
    me->retry_after = retry_after.
  ENDMETHOD.

  METHOD get_text.
    result = text.
  ENDMETHOD.

ENDCLASS.
