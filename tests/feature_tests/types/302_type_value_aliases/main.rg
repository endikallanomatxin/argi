source := import ("./definitions")
Imported := source.Packet
ImportedAgain := source.PacketAlias

Point := (.x: Int32, .y: Int32 = 2)

Alias := Point
Again := Alias
Integer := Int32
AnnotatedPoint: Type = Point
AnnotatedInteger: Type = Int32
AnnotatedImported: Type = source.Packet

Box := #(.T: Type) (.value: T)

IntBox := Box#(Int32)

read := (.point: Again) -> (.result: Integer) {
    result = point.x + point.y
}

main := () -> (.status_code: Int32 = 0) {
    point: Alias = (.x = 40)
    annotated: AnnotatedPoint = point
    same: Point = annotated
    integer: AnnotatedInteger = 42
    if integer != 42 { abort }
    boxed: IntBox = (.value = read(.point = same).result)
    other := Again(.x = 40)
    if other.x + other.y != boxed.value { abort }
    known: Integer = #run () -> (.result: Integer) {
        point: Again = (.x = 40)
        result = read(.point = point).result
    }
    imported: Imported = (.value = known)
    annotated_import: AnnotatedImported = imported
    same_import: source.Packet = annotated_import
    imported_again := ImportedAgain(.value = same_import.value)
    if imported_again.value != 42 { abort }
    if known != 42 { abort }
}
