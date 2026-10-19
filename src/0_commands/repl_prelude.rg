_repl_trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()
_repl_tracer ::= FixedSizeErrorTracer(.buffer = view($&_repl_trace_buffer))
_repl_trace_handle ::= to_virtual#(.contract: ErrorTracer)(.value = $&_repl_tracer)
assume error_tracer ::= $&_repl_trace_handle
assume ffi ::= $&ForeignFunctionInterface()
_repl_terminal ::= Terminal()
assume writer ::= $&_repl_terminal.stdout
