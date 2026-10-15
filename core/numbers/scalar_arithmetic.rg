-- Primitive representation facts are private to bundled core. Public numeric
-- markers cannot grant permission to use the compiler's representation hooks.
_BuiltinArithmetic#(.Value: Type): Contract = ()

implement _BuiltinArithmetic#(Int8) ()

implement _BuiltinArithmetic#(Int16) ()

implement _BuiltinArithmetic#(Int32) ()

implement _BuiltinArithmetic#(Int64) ()

implement _BuiltinArithmetic#(UInt8) ()

implement _BuiltinArithmetic#(UInt16) ()

implement _BuiltinArithmetic#(UInt32) ()

implement _BuiltinArithmetic#(UInt64) ()

implement _BuiltinArithmetic#(UIntNative) ()

implement _BuiltinArithmetic#(Float16) ()

implement _BuiltinArithmetic#(Float32) ()

implement _BuiltinArithmetic#(Float64) ()

implement#(.Value: Type: _BuiltinArithmetic) Add#(Value, Value, (.left: Value, .right: Value)) (
        .Result : Type = Value
        .add    = (
                .args : (.left: Value, .right: Value)
            ) -> (
                .result : Result
            ) {
            result = __scalar_add(.left = args.left, .right = args.right)
        }
    )

implement#(.Value: Type: _BuiltinArithmetic) Subtract#(Value, Value, (.left: Value, .right: Value)) (
        .Result   : Type = Value
        .subtract = (
                .args : (.left: Value, .right: Value)
            ) -> (
                .result : Result
            ) {
            result = __scalar_subtract(.left = args.left, .right = args.right)
        }
    )

implement#(.Value: Type: _BuiltinArithmetic) Multiply#(Value, Value, (.left: Value, .right: Value)) (
        .Result   : Type = Value
        .multiply = (
                .args : (.left: Value, .right: Value)
            ) -> (
                .result : Result
            ) {
            result = __scalar_multiply(.left = args.left, .right = args.right)
        }
    )

implement#(.Value: Type: _BuiltinArithmetic) Divide#(Value, Value, (.left: Value, .right: Value)) (
        .Result : Type = Value
        .divide = (
                .args : (.left: Value, .right: Value)
            ) -> (
                .result : Result
            ) {
            result = __scalar_divide(.left = args.left, .right = args.right)
        }
    )

implement#(.Value: Type: _BuiltinArithmetic) Remainder#(
    Value,
    Value,
    (.left: Value, .right: Value)
) (
        .Result    : Type = Value
        .remainder = (
                .args : (.left: Value, .right: Value)
            ) -> (
                .result : Result
            ) {
            result = __scalar_remainder(.left = args.left, .right = args.right)
        }
    )

_BuiltinEquality#(.Value: Type): Contract = ()

implement _BuiltinEquality#(Int8) ()

implement _BuiltinEquality#(Int16) ()

implement _BuiltinEquality#(Int32) ()

implement _BuiltinEquality#(Int64) ()

implement _BuiltinEquality#(UInt8) ()

implement _BuiltinEquality#(UInt16) ()

implement _BuiltinEquality#(UInt32) ()

implement _BuiltinEquality#(UInt64) ()

implement _BuiltinEquality#(UIntNative) ()

implement _BuiltinEquality#(Float16) ()

implement _BuiltinEquality#(Float32) ()

implement _BuiltinEquality#(Float64) ()

implement _BuiltinEquality#(Bool) ()

implement _BuiltinEquality#(Char) ()

implement _BuiltinEquality#(RawPointer) ()

implement#(.Value: Type: _BuiltinEquality) Equal#(Value, Value, (.left: Value, .right: Value)) (
        .equal = (
                .args : (.left: Value, .right: Value)
            ) -> (
                .ok : Bool
            ) {
            ok = __scalar_equal(.left = args.left, .right = args.right)
        }
    )
