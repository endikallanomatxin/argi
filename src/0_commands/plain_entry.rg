-- Calls without process capabilities still pass defaults through semantizing
-- and safety before reaching the host ABI adapter.
__argi_entry() -> __ARGI_OUTPUT__ := {
    assume error_tracer ::= $&noop_error_tracer
    __ARGI_RESULT__ = __ARGI_TARGET__()
}
