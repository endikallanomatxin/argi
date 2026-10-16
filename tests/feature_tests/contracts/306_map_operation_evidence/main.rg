BytePolicy: Type = ()

implement ImplicitlyCopyable#(BytePolicy) ()

implement HashPolicy#(BytePolicy, UInt8) (
    .Query : Type = &UInt8
    .query = (.self: &BytePolicy, .key: &UInt8) -> (.query: Query) { query = key }

    .hash = (.self: &BytePolicy, .key: &UInt8) -> (.hash: UIntNative) {
        hash = [key&| convert#(.to: UIntNative)(_)]
    }
    .equal = (.self: &BytePolicy, .left: &UInt8, .right: &UInt8) -> (.ok: Bool) {
        ok = left&== right&
    }
)

lookup_byte#(.Map: Type: MapLookupValue#(.Map: Map, .Query: &UInt8, .Value: UInt8)) := (
    .self : &Map
) -> (.result: ?UInt8) {
    query: UInt8 = 250
    result = ~MapLookupValue#(Map).get(.self = self, .key = &query)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    query: UInt8 = 250
    assume allocator := system.page_allocator
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: UInt8, .value: UInt8, .policy: BytePolicy)(
            .policy = BytePolicy(), .capacity = 1
        )
    )
    unwrap_or_abort(.value = put(.self = $&map, .key = 250, .value = 251))
    if contains(.self = &map, .key = &query).ok == false { status_code = 1 }
    match lookup_byte(.self = &map) {
        ..none { status_code = 2 }
        ..some item { if item.value != 251 { status_code = 3 } }
    }
    match get_reference(.self = &map, .key = &query).result {
        ..none { status_code = 4 }
        ..some item { if item.value&!= 251 { status_code = 5 } }
    }
    if remove(.self = $&map, .key = &query).removed == false { status_code = 6 }
    if contains(.self = &map, .key = &query).ok { status_code = 7 }

    string_map ::= unwrap_or_abort(
        .value = HashMap#(.key: StringView, .value: UInt8)(.capacity = 1)
    )
    unwrap_or_abort(.value = put(.self = $&string_map, .key = "key", .value = 250))
    key: StringView = "key"
    match get(.self = &string_map, .key = key).result {
        ..none { status_code = 8 }
        ..some item { if item.value != 250 { status_code = 9 } }
    }
}
