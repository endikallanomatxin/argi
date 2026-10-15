-- Reporting capabilities belong to this checked scope even when user main
-- omits System. The host ABI adapter only observes its integer status.
__argi_entry() -> __ARGI_OUTPUT__ := {
    __ARGI_TRACER_SETUP__
    __ARGI_REPORT_SETUP__
    __ARGI_CALL__
}
