Comparator(.left: CInt, .right: CInt) -> (.result: CInt) : CFunctionPointer
Entry : CStruct = (.callback: Comparator, .bias: CInt)
implement ImplicitlyCopyable#(Entry) ()

difference(.left: CInt, .right: CInt) -> (.result: CInt) : CFunction := {
    result = left - right
}
