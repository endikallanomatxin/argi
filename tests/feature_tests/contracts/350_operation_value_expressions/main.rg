identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

alias := identity

ViaAlias#(.T: Type): Contract = (.alias_value: _)

implement ViaAlias#(Int32) (.alias_value = alias#(Int32))

Direct#(.T: Type): Contract = (.direct_value: _)

implement Direct#(Int32) (.direct_value = identity#(Int32))

Box := #(.T: Type) (.value: T)

make_box := #(.T: Type) (.value: T) -> (.result: Box#(T)) { result = (.value = value) }

BoxInitArgs: Type = #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
    .Result : Type = Box#(T)
    .init   = make_box#(T)
)

Wrapped#(.T: Type): Contract = (.wrapped_value: _)

implement#(.T: Type) Wrapped#(Box#(T)) (.wrapped_value = identity#(T))

main := () -> (.status_code: Int32 = 0) {
    value ::= Box(42)
    if value.value != 42 { status_code = 1 }
    if Wrapped#(Box#(Int32)).wrapped_value(7) != 7 { status_code = 2 }
    if direct_value(9) != 9 { status_code = 3 }
    if wrapped_value(true) == false { status_code = 4 }
    known ::= #run () -> (.result: Int32) { result = direct_value(11) }
    if known != 11 { status_code = 5 }
    if alias_value(12) != 12 { status_code = 6 }
}
