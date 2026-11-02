-- Closing preserves each resource's result protocol and native handle effects.
Closeable#(.Resource: Type): Contract = (
    .Result         : Type
    .close_resource : (.self: $&Resource) -> (.result: Result)
)

OpenState#(.Resource: Type): Contract = (
    .check_open : (.self: &Resource) -> (.ok: Bool)
)

close := #(.Resource: Type: Closeable#(Resource)) (.self: $&Resource) -> (
    .result : Closeable#(Resource).Result
) {

    result = ~Closeable#(Resource).close_resource(.self = self)
}

is_open := #(.Resource: Type: OpenState#(Resource)) (.self: &Resource) -> (.ok: Bool) {
    ok = OpenState#(Resource).check_open(.self = self)
}
