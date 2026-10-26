integer_identity := <.T: Type: Int> (.value: T) -> (.result: T) { result = value }

unsigned_identity := <.T: Type: UInt> (.value: T) -> (.result: T) { result = value }

float_identity := <.T: Type: Float> (.value: T) -> (.result: T) { result = value }

main := () -> (.status_code: Int32 = 0) {
    value_0 :: Int8 = 7
    if integer_identity(value_0) != value_0 { abort }
    value_1 :: Int16 = 7
    if integer_identity(value_1) != value_1 { abort }
    value_2 :: Int32 = 7
    if integer_identity(value_2) != value_2 { abort }
    value_3 :: Int64 = 7
    if integer_identity(value_3) != value_3 { abort }
    value_4 :: UInt8 = 7
    if integer_identity(value_4) != value_4 { abort }
    if unsigned_identity(value_4) != value_4 { abort }
    value_5 :: UInt16 = 7
    if integer_identity(value_5) != value_5 { abort }
    if unsigned_identity(value_5) != value_5 { abort }
    value_6 :: UInt32 = 7
    if integer_identity(value_6) != value_6 { abort }
    if unsigned_identity(value_6) != value_6 { abort }
    value_7 :: UInt64 = 7
    if integer_identity(value_7) != value_7 { abort }
    if unsigned_identity(value_7) != value_7 { abort }
    value_8 :: UIntNative = 7
    if integer_identity(value_8) != value_8 { abort }
    if unsigned_identity(value_8) != value_8 { abort }
    floating_0 :: Float16 = 1.5
    if float_identity(floating_0) != floating_0 { abort }
    floating_1 :: Float32 = 1.5
    if float_identity(floating_1) != floating_1 { abort }
    floating_2 :: Float64 = 1.5
    if float_identity(floating_2) != floating_2 { abort }
}
