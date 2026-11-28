CLASS ltc_runner DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS code_uses_safe_alphabet FOR TESTING.
    METHODS code_is_deterministic FOR TESTING.
    METHODS hash_is_sha256_hex FOR TESTING RAISING cx_static_check.
    METHODS pairing_code_rules FOR TESTING.
    METHODS actions_only_for_own_runner FOR TESTING.
ENDCLASS.


CLASS ltc_runner IMPLEMENTATION.

  METHOD code_uses_safe_alphabet.
    DATA(lv_code) = /reg/cl_ams_runner=>code_from_bytes( CONV xstring( '00FF7F801E1F203D3E3F' ) ).
    cl_abap_unit_assert=>assert_equals( act = strlen( lv_code ) exp = /reg/cl_ams_runner=>c_code_length ).
    cl_abap_unit_assert=>assert_true( xsdbool( lv_code CO /reg/cl_ams_runner=>c_alphabet ) ).
  ENDMETHOD.

  METHOD code_is_deterministic.
    " 0 -> A, 1 -> B, 31 (lunghezza dell'alfabeto) torna ad A.
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_runner=>code_from_bytes( CONV xstring( '0001021F00010203' ) )
                                        exp = `ABCAABCD` ).
  ENDMETHOD.

  METHOD hash_is_sha256_hex.
    " SHA-256 di "abc" (vettore di prova standard).
    cl_abap_unit_assert=>assert_equals( act = /reg/cl_ams_runner=>hash( `abc` )
                                        exp = `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` ).
  ENDMETHOD.

  METHOD pairing_code_rules.
    DATA lv_now   TYPE timestampl VALUE '20261126120000'.
    DATA lv_later TYPE timestampl VALUE '20261126121500'.
    DATA(ls_waiting) = VALUE /reg/ams_run( owner = 'MROSSI' pair_hash = 'h' pair_until = '20261126121000' ).
    cl_abap_unit_assert=>assert_true( /reg/cl_ams_runner=>is_pairable( is_runner = ls_waiting iv_now = lv_now ) ).
    " Scaduto.
    cl_abap_unit_assert=>assert_false( /reg/cl_ams_runner=>is_pairable( is_runner = ls_waiting iv_now = lv_later ) ).
    " Gia' usato: ha un token.
    DATA(ls_used) = ls_waiting.
    ls_used-token_hash = 't'.
    cl_abap_unit_assert=>assert_false( /reg/cl_ams_runner=>is_pairable( is_runner = ls_used iv_now = lv_now ) ).
    " Revocato.
    DATA(ls_revoked) = ls_waiting.
    ls_revoked-revoked = abap_true.
    cl_abap_unit_assert=>assert_false( /reg/cl_ams_runner=>is_pairable( is_runner = ls_revoked iv_now = lv_now ) ).
  ENDMETHOD.

  METHOD actions_only_for_own_runner.
    " Runner locale di MROSSI: solo le operazioni di MROSSI su portali con runner locale.
    cl_abap_unit_assert=>assert_true(
      /reg/cl_ams_runner=>is_for_runner( iv_runner_owner = 'MROSSI' iv_consultant = 'MROSSI' iv_runner_kind = `LOCAL` ) ).
    cl_abap_unit_assert=>assert_false(
      /reg/cl_ams_runner=>is_for_runner( iv_runner_owner = 'MROSSI' iv_consultant = 'LBIANCHI' iv_runner_kind = `LOCAL` ) ).
    cl_abap_unit_assert=>assert_false(
      /reg/cl_ams_runner=>is_for_runner( iv_runner_owner = 'MROSSI' iv_consultant = 'MROSSI' iv_runner_kind = `CENTRAL` ) ).
    " Runner centrale (senza proprietario): solo portali con runner centrale, di qualunque consulente.
    cl_abap_unit_assert=>assert_true(
      /reg/cl_ams_runner=>is_for_runner( iv_runner_owner = '' iv_consultant = 'LBIANCHI' iv_runner_kind = `CENTRAL` ) ).
    cl_abap_unit_assert=>assert_false(
      /reg/cl_ams_runner=>is_for_runner( iv_runner_owner = '' iv_consultant = 'LBIANCHI' iv_runner_kind = `LOCAL` ) ).
  ENDMETHOD.

ENDCLASS.