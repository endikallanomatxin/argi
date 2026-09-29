# Error tracing implementation

- [x] Tokenizing and syntaxing retain the existing `!` and `!!` syntax.
- [x] Semantizing creates traces through a reached `$&Virtual#(.abstract: ErrorTracer)`
  capability and preserves the original tracer dependency in error values.
- [x] Codegen lowers propagation to core context calls and emits compact source
  location IDs with executable metadata, without allocating trace storage.
- [x] Core supplies a program-lifetime noop tracer, fallible fixed-buffer
  initialization, copied bounded context, shared retention, reset, and fallible
  reporting without recursive tracing of report failures.
- [x] Validate custom virtual dispatch, success-path laziness, original-tracer
  routing, context ownership and length, reset, bounded loss, initialization
  failure, reporting failure, and tracer lifetime diagnostics, then run the
  compiler suite and inspect generated LLVM IR.
