Pair : CStruct = (.left: CDouble, .right: CDouble)
Pair implements ImplicitlyCopyable
Transformer(.value: Pair) -> (.result: Pair) : CFunctionPointer
_make() -> (.result: Pair) : CFunction(.symbol = "argi_cross_make")
_apply(.value: Pair, .callback: Transformer) -> (.result: Pair) : CFunction(.symbol = "argi_cross_apply")

swap(.value: Pair) -> (.result: Pair) : CFunction := {
    result = (.left = value.right, .right = value.left)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    original := _make()
    callback := Transformer(.function = swap)
    direct := callback(original)
    through_c := _apply(original, callback)
    if direct.left != original.right or direct.right != original.left { status_code = 1 }
    if through_c.left != original.right or through_c.right != original.left { status_code = 2 }
}
