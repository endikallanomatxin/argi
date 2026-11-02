source := import ("./definitions")
Box := source.Box
Alias := Box
Again := Alias
identity := source.identity
copied_identity := identity

read := (.value: Again#(Int32)) -> (.result: Int32) {
    result = value.value
}

main := () -> (.status_code: Int32 = 0) {
    box: Alias#(Int32) = (.value = 42)
    same: source.Box#(Int32) = box
    imported: source.ExportedBox#(Int32) = same
    value: Int32 = copied_identity#(Int32)(.value = imported.value).result
    if value != read(.value = box).result { abort }
    inferred: Int32 = source.ExportedIdentity(.value = value).result
    if inferred != 42 { abort }
    constructed := Again#(Int32)(.value = inferred)
    if constructed.value != 42 { abort }
    evaluated: Int32 = #run () -> (.result: Int32) {
        box := source.ExportedBox#(Int32)(.value = 42)
        result = copied_identity#(Int32)(.value = box.value).result
    }
    if evaluated != constructed.value { abort }
    if source.measure#(Int32)(.value = evaluated).result != size_of(.type = Int32) { abort }
}
