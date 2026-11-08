Depth#(.T: Type): Contract = (.get: () -> (.value: Int32))

implement#(.T: Type) Depth#(T) (.get = () -> (.value: Int32 = 0) {})

implement#(.T: Type) Depth#(?T) (.get = () -> (.value: Int32 = 1) {})

implement#(.T: Type) Depth#(??T) (.get = () -> (.value: Int32 = 2) {})

Related#(.Left: Type, .Right: Type): Contract = (.get: () -> (.value: Int32))

implement#(.Left: Type, .Right: Type) Related#(Left, Right) (
    .get = () -> (.value: Int32 = 0) {}
)

implement#(.T: Type) Related#(?T, T) (.get = () -> (.value: Int32 = 1) {})

Maybe: Type = ?Int32

Reversed: Type = (..some(.value: Int32), ..none)

Nominal := (..none, ..some(.value: Int32))

main := () -> () {
    if Depth#(Int32).get() != 0 { abort }
    if Depth#(?Int32).get() != 1 { abort }
    if Depth#(Maybe).get() != 1 { abort }
    if Depth#(??Int32).get() != 2 { abort }
    if Depth#(Nominal).get() != 0 { abort }
    if Depth#(Reversed).get() != 0 { abort }
    if Related#(?Int32, Int32).get() != 1 { abort }
    if Related#(?Int32, UInt8).get() != 0 { abort }
}
