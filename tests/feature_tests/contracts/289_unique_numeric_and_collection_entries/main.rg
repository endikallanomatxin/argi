Counter: Type = (.count: UIntNative)
implement CollectionLength#(Counter) (
    .measure_length = (.self: &Counter) -> (.count: UIntNative) { count = self&.count }
)
implement CollectionCapacity#(Counter) (
    .measure_capacity = (.self: &Counter) -> (.count: UIntNative) { count = self&.count + 1 }
)
query#(.Value: Type: CollectionLength#(Value)) := (.self: &Value) -> (.count: UIntNative) {
    count = length(self)
}
read_maximum#(.Value: Type: IntegerBounds#(Value)) := (.value: Value) -> (.maximum: Value) {
    maximum = integer_limits(value).maximum
}
main := () -> (.status_code: Int32 = 0) {
    counter ::= Counter(7)
    if query(&counter) != 7 or capacity(&counter) != 8 { status_code = 1 }
    byte :: UInt8 = 0
    signed :: Int8 = 0
    if read_maximum(byte) != 255 or read_maximum(signed) != 127 { status_code = 2 }
    float :: Float32 = -1.5
    if truncate_float(float) != -1.0 or float_sign_bit(float) == false { status_code = 3 }
}
