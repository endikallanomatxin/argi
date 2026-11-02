SeededPolicy := (.seed: UIntNative)

implement Deinit#(SeededPolicy) (
    .deinit = (.self: $&SeededPolicy) -> () {}
)

implement FalliblyCopyable#(SeededPolicy) (
    .reasons : Type = (..out_of_memory)
    .copy = (.self: &SeededPolicy, .allocator: Virtual#(Allocator)) -> (
        .result: Errable#(SeededPolicy, (..out_of_memory))
    ) {
        result = ..ok SeededPolicy(.seed = self&.seed + 1)
    }
)

implement HashPolicy#(SeededPolicy, Int32) (
    .Query : Type = Int32
    .query = (.self: &SeededPolicy, .key: &Int32) -> (.query: Int32) { query = key& }
    .hash = (.self: &SeededPolicy, .key: Int32) -> (.hash: UIntNative) {
        hash = self&.seed
    }
    .equal = (.self: &SeededPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) {
        ok = left == right
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator

    empty ::= HashMap#(.key: Int32, .value: Int32)(.capacity = 8)!!!
    empty_copy ::= copy(&empty, .allocator = allocator)!!!
    if length(&empty_copy).count != 0 { abort }
    if capacity(&empty_copy).count != capacity(&empty).count { abort }

    scalars ::= HashMap#(.key: Int32, .value: Int32)(.policy = SeededPolicy(.seed = 1))!!!
    put($&scalars, .key = 1, .value = 10)!!!
    put($&scalars, .key = 2, .value = 20)!!!
    put($&scalars, .key = 3, .value = 30)!!!
    if remove($&scalars, .key = 2).removed == false { abort }
    scalar_copy ::= copy(&scalars, .allocator = allocator)!!!
    if length(&scalar_copy).count != 2 { abort }
    if capacity(&scalar_copy).count != capacity(&scalars).count { abort }
    if contains(&scalar_copy, .key = 2).ok { abort }
    match get(&scalar_copy, .key = 3).result {
        ..none { abort }
        ..some found { if found.value != 30 { abort } }
    }
    deinit($&scalars)
    match get(&scalar_copy, .key = 1).result {
        ..none { abort }
        ..some found { if found.value != 10 { abort } }
    }

    strings ::= HashMap#(.key: String, .value: String)()!!!
    key ::= format(.value = "key")!!!
    value ::= format(.value = "value")!!!
    put($&strings, .key = ~key, .value = ~value)!!!
    strings_copy ::= copy(&strings, .allocator = allocator)!!!
    match get_mutable_reference($&strings_copy, .key = "key").result {
        ..none { abort }
        ..some found { set_ascii(found.value, .index = 0, .byte = 86)!!! }
    }
    match get_reference(&strings, .key = "key").result {
        ..none { abort }
        ..some found { if view(found.value) != "value" { abort } }
    }
    deinit($&strings)
    match get_reference(&strings_copy, .key = "key").result {
        ..none { abort }
        ..some found { if view(found.value) != "Value" { abort } }
    }

    nested ::= HashMap#(.key: Int32, .value: DynamicArray#(Int32))()!!!
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)!!!
    push($&array, .value = 42)!!!
    put($&nested, .key = 7, .value = ~array)!!!
    nested_copy ::= copy(&nested, .allocator = allocator)!!!
    deinit($&nested)
    match get_reference(&nested_copy, .key = &7).result {
        ..none { abort }
        ..some found { if get(found.value, .index = 0)!!! != 42 { abort } }
    }
}
