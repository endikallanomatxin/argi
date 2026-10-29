Restricted := #(.T: Type: ImplicitlyCopyable#(T)) (.value: T)

accept := #(.Family: #(.T: Type) Type) () -> () {}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    accept#(.Family = Restricted)()
}
