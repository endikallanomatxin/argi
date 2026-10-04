Fixed#(.n: UIntNative): Abstract = ()

Box: Type = (.value: Int32)

Box implements Fixed#(.n = 1)

main() -> () := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: Fixed#(.n = 2))(.value = &box)
}
