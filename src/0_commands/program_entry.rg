-- Resource ownership belongs to this checked scope. The host adapter only
-- records process arguments and calls this function. Resource initialization,
-- the user call, and cleanup pass through semantizing and safety together;
-- codegen supplies the host ABI adapter rather than an unchecked entry lifetime.
__argi_entry() -> __ARGI_OUTPUT__ := {
    __ARGI_TRACER_SETUP__
    __ARGI_SYSTEM_SCOPE__
    __ARGI_REPORT_SETUP__
    __ARGI_CALL__
}
