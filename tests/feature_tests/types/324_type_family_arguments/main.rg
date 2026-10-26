Box := <.Item: Type> (.value: Item)

read_flag := <.Family: <.Element: Type> Type> (.value: Family<Bool>) -> (.result: Bool) {
    result = value.value
}

forward_flag := <.Family: <.Element: Type> Type> (.value: Family<Bool>) -> (.result: Bool) {
    result = read_flag<.Family = Family>(.value = value).result
}

with_default := <.Family: <.Element: Type> Type = Box> (
    .value: Bool
) -> (.result: Bool) {
    box: Family<Bool> = (.value = value)
    result = box.value
}

known ::= #run () -> (.result: Bool) {
    box: Box<Bool> = (.value = true)
    result = forward_flag<.Family = Box>(.value = box).result
}

main := () -> () {
    box: Box<Bool> = (.value = true)
    if read_flag<.Family = Box>(.value = box).result {} else { abort }
    if forward_flag<.Family: Box>(.value = box).result {} else { abort }
    if known {} else { abort }
    if with_default(.value = true).result {} else { abort }
}
