-- These private classification contracts describe primitive representation
-- facts, without allowing public numeric marker extensions to claim them.
_BuiltinInteger#(.Value: Type): Contract = ()

implement _BuiltinInteger#(Int8) ()

implement _BuiltinInteger#(Int16) ()

implement _BuiltinInteger#(Int32) ()

implement _BuiltinInteger#(Int64) ()

implement _BuiltinInteger#(UInt8) ()

implement _BuiltinInteger#(UInt16) ()

implement _BuiltinInteger#(UInt32) ()

implement _BuiltinInteger#(UInt64) ()

implement _BuiltinInteger#(UIntNative) ()

_IntegerFitsInt16#(.Value: Type): Contract = ()

implement _IntegerFitsInt16#(Int8) ()

implement _IntegerFitsInt16#(UInt8) ()

_IntegerFitsInt32#(.Value: Type): Contract = ()

implement _IntegerFitsInt32#(Int8) ()

implement _IntegerFitsInt32#(Int16) ()

implement _IntegerFitsInt32#(UInt8) ()

implement _IntegerFitsInt32#(UInt16) ()

_IntegerFitsInt64#(.Value: Type): Contract = ()

implement _IntegerFitsInt64#(Int8) ()

implement _IntegerFitsInt64#(Int16) ()

implement _IntegerFitsInt64#(Int32) ()

implement _IntegerFitsInt64#(UInt8) ()

implement _IntegerFitsInt64#(UInt16) ()

implement _IntegerFitsInt64#(UInt32) ()

_IntegerFitsUInt16#(.Value: Type): Contract = ()

implement _IntegerFitsUInt16#(UInt8) ()

_IntegerFitsUInt32#(.Value: Type): Contract = ()

implement _IntegerFitsUInt32#(UInt8) ()

implement _IntegerFitsUInt32#(UInt16) ()

_IntegerFitsUInt64#(.Value: Type): Contract = ()

implement _IntegerFitsUInt64#(UInt8) ()

implement _IntegerFitsUInt64#(UInt16) ()

implement _IntegerFitsUInt64#(UInt32) ()

implement _IntegerFitsUInt64#(UIntNative) ()

_IntegerFitsUIntNative#(.Value: Type): Contract = ()

implement _IntegerFitsUIntNative#(UInt8) ()

implement _IntegerFitsUIntNative#(UInt16) ()

-- Native integer relationships depend on the target ABI, not the build host
-- or an assumption that every architecture uses its default pointer width.
#if target_pointer_bits(64) {
    implement _IntegerFitsUIntNative#(UInt32) ()
    implement _IntegerFitsUIntNative#(UInt64) ()
} #else {
    implement _IntegerFitsInt64#(UIntNative) ()
    implement _IntegerFitsUInt32#(UIntNative) ()
}
#if target_pointer_bits(32) {
    implement _IntegerFitsUIntNative#(UInt32) ()
}
#if target_pointer_bits(16) {
    implement _IntegerFitsInt32#(UIntNative) ()
    implement _IntegerFitsUInt16#(UIntNative) ()
}

_integer_conversion_unchecked := #(.Source: Type, .Target: Type) (.value: Source) -> (
    .result : Target
) {
    result = __integer_conversion#(.to: Target)(.value = value)
}

-- Bounds are constants in the source representation. The comparison always
-- precedes truncation or a signedness change; failure retains the active tracer.
_checked_integer_conversion := #(.Source: Type, .Target: Type) (.value: Source) -> (
    .result : Errable#(Target, (..out_of_range))
) {
    minimum ::= __integer_conversion_lower_bound#(.from: Source, .to: Target)()
    maximum ::= __integer_conversion_upper_bound#(.from: Source, .to: Target)()
    if value < minimum or value > maximum {
        result = ..error(.reason = ..out_of_range)
        return
    }
    result = ..ok _integer_conversion_unchecked#(.Target: Target)(.value = value)
}

implement#(.Value: Type) Convert#(Value, Value) (
    .Result  : Type = Value
    .convert = (.value: Value) -> (.result: Result) { result = ~value }
)

implement#(.Source: Type: _BuiltinInteger, .Target: Type: _BuiltinInteger) Convert#(
    Source, Target
) (
    .Result  : Type = Errable#(Target, (..out_of_range))
    .convert = (.value: Source) -> (.result: Result) {
        result = ~_checked_integer_conversion#(.Target: Target)(.value = ~value)
    }
)

implement#(.Source: Type: _IntegerFitsInt16) Convert#(Source, Int16) (
    .Result  : Type = Int16
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: Int16)(.value = value)
    }
)

implement#(.Source: Type: _IntegerFitsInt32) Convert#(Source, Int32) (
    .Result  : Type = Int32
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: Int32)(.value = value)
    }
)

implement#(.Source: Type: _IntegerFitsInt64) Convert#(Source, Int64) (
    .Result  : Type = Int64
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: Int64)(.value = value)
    }
)

implement#(.Source: Type: _IntegerFitsUInt16) Convert#(Source, UInt16) (
    .Result  : Type = UInt16
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: UInt16)(.value = value)
    }
)

implement#(.Source: Type: _IntegerFitsUInt32) Convert#(Source, UInt32) (
    .Result  : Type = UInt32
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: UInt32)(.value = value)
    }
)

implement#(.Source: Type: _IntegerFitsUInt64) Convert#(Source, UInt64) (
    .Result  : Type = UInt64
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: UInt64)(.value = value)
    }
)

implement#(.Source: Type: _IntegerFitsUIntNative) Convert#(Source, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: Source) -> (.result: Result) {
        result = _integer_conversion_unchecked#(.Target: UIntNative)(.value = value)
    }
)
