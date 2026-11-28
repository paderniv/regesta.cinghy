CLASS ltc_op DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS ok
      IMPORTING iv_from TYPE /reg/ams_op-status
                iv_to   TYPE /reg/ams_op-status.
    METHODS ko
      IMPORTING iv_from TYPE /reg/ams_op-status
                iv_to   TYPE /reg/ams_op-status.
    METHODS reading_transitions FOR TESTING.
    METHODS plan_wait_transitions FOR TESTING.
    METHODS executing_transitions FOR TESTING.
    METHODS login_returns_to_phase FOR TESTING.
    METHODS final_states_are_closed FOR TESTING.
    METHODS step_limit FOR TESTING.
    METHODS timeout_per_status FOR TESTING.
    METHODS final_never_times_out FOR TESTING.
ENDCLASS.


CLASS ltc_op IMPLEMENTATION.

  METHOD ok.
    cl_abap_unit_assert=>assert_true( act = /reg/cl_ams_op=>can_transition( iv_from = iv_from iv_to = iv_to )
                                      msg = |{ iv_from } -> { iv_to } deve essere ammesso| ).
  ENDMETHOD.

  METHOD ko.
    cl_abap_unit_assert=>assert_false( act = /reg/cl_ams_op=>can_transition( iv_from = iv_from iv_to = iv_to )
                                       msg = |{ iv_from } -> { iv_to } non deve essere ammesso| ).
  ENDMETHOD.

  METHOD reading_transitions.
    ok( iv_from = /reg/cl_ams_op=>c_status-reading iv_to = /reg/cl_ams_op=>c_status-plan_wait ).
    ok( iv_from = /reg/cl_ams_op=>c_status-reading iv_to = /reg/cl_ams_op=>c_status-done ).
    ok( iv_from = /reg/cl_ams_op=>c_status-reading iv_to = /reg/cl_ams_op=>c_status-login_wait ).
    " In lettura non si passa mai direttamente all'esecuzione: serve la conferma del piano.
    ko( iv_from = /reg/cl_ams_op=>c_status-reading iv_to = /reg/cl_ams_op=>c_status-executing ).
  ENDMETHOD.

  METHOD plan_wait_transitions.
    ok( iv_from = /reg/cl_ams_op=>c_status-plan_wait iv_to = /reg/cl_ams_op=>c_status-executing ).
    ok( iv_from = /reg/cl_ams_op=>c_status-plan_wait iv_to = /reg/cl_ams_op=>c_status-reading ).
    ok( iv_from = /reg/cl_ams_op=>c_status-plan_wait iv_to = /reg/cl_ams_op=>c_status-cancelled ).
    ko( iv_from = /reg/cl_ams_op=>c_status-plan_wait iv_to = /reg/cl_ams_op=>c_status-done ).
  ENDMETHOD.

  METHOD executing_transitions.
    ok( iv_from = /reg/cl_ams_op=>c_status-executing iv_to = /reg/cl_ams_op=>c_status-plan_wait ).
    ok( iv_from = /reg/cl_ams_op=>c_status-executing iv_to = /reg/cl_ams_op=>c_status-done ).
    ko( iv_from = /reg/cl_ams_op=>c_status-executing iv_to = /reg/cl_ams_op=>c_status-reading ).
  ENDMETHOD.

  METHOD login_returns_to_phase.
    ok( iv_from = /reg/cl_ams_op=>c_status-login_wait iv_to = /reg/cl_ams_op=>c_status-reading ).
    ok( iv_from = /reg/cl_ams_op=>c_status-login_wait iv_to = /reg/cl_ams_op=>c_status-executing ).
    ko( iv_from = /reg/cl_ams_op=>c_status-login_wait iv_to = /reg/cl_ams_op=>c_status-done ).
  ENDMETHOD.

  METHOD final_states_are_closed.
    DATA(lt_final) = VALUE string_table( ( `DONE` ) ( `CANCELLED` ) ( `ERROR` ) ).
    LOOP AT lt_final INTO DATA(lv_final).
      cl_abap_unit_assert=>assert_true( /reg/cl_ams_op=>is_final( CONV #( lv_final ) ) ).
      ko( iv_from = CONV #( lv_final ) iv_to = /reg/cl_ams_op=>c_status-reading ).
      ko( iv_from = CONV #( lv_final ) iv_to = /reg/cl_ams_op=>c_status-error ).
    ENDLOOP.
  ENDMETHOD.

  METHOD step_limit.
    DATA lv_now TYPE timestampl VALUE '20261126120000'.
    DATA(ls_op) = VALUE /reg/ams_op( status = /reg/cl_ams_op=>c_status-reading steps = 39 changed_at = lv_now ).
    cl_abap_unit_assert=>assert_initial(
      /reg/cl_ams_op=>check_limits( is_op = ls_op iv_max_steps = 40 iv_timeout_minutes = 15 iv_now = lv_now ) ).
    ls_op-steps = 40.
    cl_abap_unit_assert=>assert_char_cp(
      act = /reg/cl_ams_op=>check_limits( is_op = ls_op iv_max_steps = 40 iv_timeout_minutes = 15 iv_now = lv_now )
      exp = `*40 passi*` ).
  ENDMETHOD.

  METHOD timeout_per_status.
    DATA lv_changed TYPE timestampl VALUE '20261126120000'.
    DATA lv_14_min  TYPE timestampl VALUE '20261126121400'.
    DATA lv_16_min  TYPE timestampl VALUE '20261126121600'.
    DATA(ls_op) = VALUE /reg/ams_op( status = /reg/cl_ams_op=>c_status-executing changed_at = lv_changed ).

    cl_abap_unit_assert=>assert_initial(
      /reg/cl_ams_op=>check_limits( is_op = ls_op iv_max_steps = 40 iv_timeout_minutes = 15 iv_now = lv_14_min ) ).
    cl_abap_unit_assert=>assert_char_cp(
      act = /reg/cl_ams_op=>check_limits( is_op = ls_op iv_max_steps = 40 iv_timeout_minutes = 15 iv_now = lv_16_min )
      exp = `*runner*` ).

    ls_op-status = /reg/cl_ams_op=>c_status-plan_wait.
    cl_abap_unit_assert=>assert_char_cp(
      act = /reg/cl_ams_op=>check_limits( is_op = ls_op iv_max_steps = 40 iv_timeout_minutes = 15 iv_now = lv_16_min )
      exp = `*Piano non confermato*` ).

    ls_op-status = /reg/cl_ams_op=>c_status-login_wait.
    cl_abap_unit_assert=>assert_char_cp(
      act = /reg/cl_ams_op=>check_limits( is_op = ls_op iv_max_steps = 40 iv_timeout_minutes = 15 iv_now = lv_16_min )
      exp = `*Accesso*` ).
  ENDMETHOD.

  METHOD final_never_times_out.
    DATA lv_changed TYPE timestampl VALUE '20261126120000'.
    DATA lv_later   TYPE timestampl VALUE '20261127120000'.
    cl_abap_unit_assert=>assert_initial(
      /reg/cl_ams_op=>check_limits( is_op              = VALUE #( status = /reg/cl_ams_op=>c_status-done steps = 99 changed_at = lv_changed )
                                    iv_max_steps       = 40
                                    iv_timeout_minutes = 15
                                    iv_now             = lv_later ) ).
  ENDMETHOD.

ENDCLASS.