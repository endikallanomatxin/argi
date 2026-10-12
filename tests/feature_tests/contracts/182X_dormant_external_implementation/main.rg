api ::= import("./api")
implement#(.T: Type) api.Readable#(api.Box#(T)) (
    .read = (.source: api.Box#(T)) -> (.result: Int32) { result = 0 }
)
main := () -> () {}
