python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    json ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "json")).result
    loads ::= unwrap_or_abort(.value = python.attribute(.self = &json, .name = "loads")).result
    text ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "{\"count\":42}")).result
    args: [1]&python.Object = (&text)
    parsed ::= unwrap_or_abort(.value = python.call(.self = &loads,
            .arguments = view(.array = &args))).result
    key ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "count")).result
    count ::= unwrap_or_abort(.value = python.get_item(.self = &parsed, .key = &key)).result
    if unwrap_or_abort(.value = python.to_int64(.self = &count)).result != 42 { abort }
}
