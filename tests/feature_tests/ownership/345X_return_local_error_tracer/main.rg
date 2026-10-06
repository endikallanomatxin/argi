..failure

escape() -> !Void = ..ok Void() := {
    buffer :: [4096]UInt8 = zeroed#([4096]UInt8)()
    tracer ::= FixedSizeErrorTracer(view($&buffer))
    virtual_tracer ::= to_virtual#(ErrorTracer)($&tracer)
    assume error_tracer ::= $&virtual_tracer

    result = ..error(.reason = ..failure)
}

main() -> () := {
    error ::= escape()
}
