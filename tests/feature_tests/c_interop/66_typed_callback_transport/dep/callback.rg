Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
Entry : CStruct = (.callback: Comparator, .bias: CInt)
Entry implements ImplicitlyCopyable

difference(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := {
    result = left - right
}
