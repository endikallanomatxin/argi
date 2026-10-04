-- Calls without process capabilities still pass defaults through semantizing
-- and safety before reaching the host ABI adapter.
__argi_entry() -> __ARGI_OUTPUT__ := {
    __ARGI_TRACER_SETUP__
    __ARGI_CALL__
}
