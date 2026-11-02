Box := #(.t: Type) (.value: ?t)

Pair := (.number: Int32, .flag: Bool)

set_value := #(.t: Type) (.self: $&Box#(t), .value: t) -> () {
    self&.value = ..some(.value = value)
}

clear := #(.t: Type) (.self: $&Box#(t)) -> () {
    self&.value = ..none
}

main := () -> (.status_code: Int32 = 0) {
    box :: Box#(Int32) = (.value = ..none)
    set_value(.self = $&box, .value = 42)
    match box.value {
        ..none { abort }
        ..some item { if item.value != 42 { abort } }
    }
    clear(.self = $&box)
    if is(.value = box.value, .variant = ..none) == false { abort }
    pair :: Box#(Pair) = (.value = ..none)
    set_value(.self = $&pair, .value = (.number = 7, .flag = true))
    match pair.value {
        ..none { abort }
        ..some item { if item.value.number != 7 or item.value.flag == false { abort } }
    }
}
