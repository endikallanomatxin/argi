Pair : CStruct = (.left: CInt, .right: CInt)
Words : CStruct = (.first: CLongLong, .second: CLongLong)
Large : CStruct = (.first: CLongLong, .second: CLongLong, .third: CLongLong)
Tiny : CStruct = (.first: CUnsignedChar, .second: CUnsignedChar, .third: CUnsignedChar)
Nested : CStruct = (.pair: Pair, .bytes: [3]UInt8)
Wrapper#(.t: Type) : CStruct = (.value: t)
Nested implements ImplicitlyCopyable
Wrapper#(.t: Type) implements ImplicitlyCopyable
Pair implements ImplicitlyCopyable
Words implements ImplicitlyCopyable
Large implements ImplicitlyCopyable
Tiny implements ImplicitlyCopyable
_pair(.value: Pair) -> (.result: Pair) : CFunction(.symbol = "argi_c_pair")
_words(.value: Words) -> (.result: Words) : CFunction(.symbol = "argi_c_words")
_large(.value: Large) -> (.result: Large) : CFunction(.symbol = "argi_c_large")
_tiny(.value: Tiny) -> (.result: Tiny) : CFunction(.symbol = "argi_c_tiny")
_crowded(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .value: Words, .f: CInt) -> (.result: Words) : CFunction(.symbol = "argi_c_crowded")
_filled(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .f: CInt, .value: Pair) -> (.result: Pair) : CFunction(.symbol = "argi_c_filled")
_stack(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .f: CInt, .g: CInt, .h: CInt, .value: Large, .i: CInt) -> (.result: Large) : CFunction(.symbol = "argi_c_stack")
_nested(.value: Nested) -> (.result: Nested) : CFunction(.symbol = "argi_c_nested")
_wrapped(.value: Wrapper#(.t: Pair)) -> (.result: Wrapper#(.t: Pair)) : CFunction(.symbol = "argi_c_wrapped")
_sret_crowded(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .value: Words, .f: CInt) -> (.result: Large) : CFunction(.symbol = "argi_c_sret_crowded")
_probe() -> (.status: CInt) : CFunction(.symbol = "argi_c_record_probe")
_forward(.value: Words) -> (.result: Words) := { result = _words(value) }
argi_c_pair_export(.value: Pair) -> (.result: Pair) : CFunction(.export = true) := {
    result = (.left = value.left + 1, .right = value.right + 2)
}
argi_c_words_export(.value: Words) -> (.result: Words) : CFunction(.export = true) := {
    result = (.first = value.first + 1, .second = value.second + 2)
}
argi_c_large_export(.value: Large) -> (.result: Large) : CFunction(.export = true) := {
    result = (.first = value.first + 1, .second = value.second + 2, .third = value.third + 3)
}
argi_c_tiny_export(.value: Tiny) -> (.result: Tiny) : CFunction(.export = true) := { result = value }
argi_c_crowded_export(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .value: Words, .f: CInt) -> (.result: Words) : CFunction(.export = true) := {
    if a != 1 or b != 2 or c != 3 or d != 4 or e != 5 or f != 6 { abort }
    result = (.first = value.first + 1, .second = value.second + 2)
}
argi_c_sret_crowded_export(.a: CInt, .b: CInt, .c: CInt, .d: CInt, .e: CInt, .value: Words, .f: CInt) -> (.result: Large) : CFunction(.export = true) := {
    if a != 1 or b != 2 or c != 3 or d != 4 or e != 5 or f != 6 { abort }
    result = (.first = value.first + 1, .second = value.second + 2, .third = 37)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    pair :: Pair = (.left = -42, .right = 30)
    paired := _pair(pair)
    if paired.left != -41 or paired.right != 32 { status_code = 1 }
    if pair.left != -42 { status_code = 2 }
    words :: Words = (.first = 100, .second = -200)
    forwarded := _forward(words)
    if forwarded.first != 101 or forwarded.second != -198 { status_code = 3 }
    crowded := _crowded(1, 2, 3, 4, 5, words, 6)
    if crowded.first != 101 or crowded.second != -198 { status_code = 4 }
    filled := _filled(1, 2, 3, 4, 5, 6, pair)
    if filled.left != -41 or filled.right != 32 { status_code = 5 }
    large :: Large = (.first = 100, .second = 200, .third = -300)
    expanded := _large(large)
    if expanded.first != 101 or expanded.second != 202 or expanded.third != -297 { status_code = 6 }
    stacked := _stack(1, 2, 3, 4, 5, 6, 7, 8, large, 9)
    if stacked.first != 101 or stacked.second != 202 or stacked.third != -297 { status_code = 7 }
    tiny :: Tiny = (.first = 240, .second = 128, .third = 37)
    echoed := _tiny(tiny)
    if echoed.first != 240 or echoed.second != 128 or echoed.third != 37 { status_code = 8 }
    if _probe() != 0 { status_code = 9 }
    nested :: Nested = (.pair = pair, .bytes = (240, 128, 37))
    nested_result := _nested(nested)
    if nested_result.pair.left != -41 or nested_result.pair.right != 32 or nested_result.bytes[2] != 9 { status_code = 10 }
    wrapped :: Wrapper#(.t: Pair) = (.value = pair)
    wrapped_result := _wrapped(wrapped)
    if wrapped_result.value.left != -41 or wrapped_result.value.right != 32 { status_code = 11 }
    sret_crowded := _sret_crowded(1, 2, 3, 4, 5, words, 6)
    if sret_crowded.first != 101 or sret_crowded.second != -198 or sret_crowded.third != 37 { status_code = 12 }
    index :: UIntNative = 0
    while index < 2048 {
        loop_result := _words(words)
        if loop_result.first != 101 or loop_result.second != -198 { abort }
        index = index + 1
    }
}
