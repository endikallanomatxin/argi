main() -> (.status_code: Int32 = 0) := {
    -- Int8 to Int8: infallible
    {
        source_0 : Int8 = -128
        converted_0 : Int8 = Int8(.value = source_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int8 = 127
        converted_1 : Int8 = Int8(.value = source_1)
        if converted_1 != 127 { status_code = 1 return }
    }
    -- Int8 to Int16: infallible
    {
        source_0 : Int8 = -128
        converted_0 : Int16 = Int16(.value = source_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int8 = 127
        converted_1 : Int16 = Int16(.value = source_1)
        if converted_1 != 127 { status_code = 1 return }
    }
    -- Int8 to Int32: infallible
    {
        source_0 : Int8 = -128
        converted_0 : Int32 = Int32(.value = source_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int8 = 127
        converted_1 : Int32 = Int32(.value = source_1)
        if converted_1 != 127 { status_code = 1 return }
    }
    -- Int8 to Int64: infallible
    {
        source_0 : Int8 = -128
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int8 = 127
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 127 { status_code = 1 return }
    }
    -- Int8 to UInt8: checked
    {
        source_0 : Int8 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int8 = 127
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int8 = -1
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int8 to UInt16: checked
    {
        source_0 : Int8 = 0
        checked_0 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_0)
        converted_0 : UInt16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int8 = 127
        checked_1 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_1)
        converted_1 : UInt16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int8 = -1
        if is(.value = UInt16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int8 to UInt32: checked
    {
        source_0 : Int8 = 0
        checked_0 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_0)
        converted_0 : UInt32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int8 = 127
        checked_1 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_1)
        converted_1 : UInt32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int8 = -1
        if is(.value = UInt32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int8 to UInt64: checked
    {
        source_0 : Int8 = 0
        checked_0 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_0)
        converted_0 : UInt64 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int8 = 127
        checked_1 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_1)
        converted_1 : UInt64 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int8 = -1
        if is(.value = UInt64(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int16 to Int8: checked
    {
        source_0 : Int16 = -128
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int16 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int16 = -129
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int16 = 128
        if is(.value = Int8(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int16 to Int16: infallible
    {
        source_0 : Int16 = -32768
        converted_0 : Int16 = Int16(.value = source_0)
        if converted_0 != -32768 { status_code = 1 return }
        source_1 : Int16 = 32767
        converted_1 : Int16 = Int16(.value = source_1)
        if converted_1 != 32767 { status_code = 1 return }
    }
    -- Int16 to Int32: infallible
    {
        source_0 : Int16 = -32768
        converted_0 : Int32 = Int32(.value = source_0)
        if converted_0 != -32768 { status_code = 1 return }
        source_1 : Int16 = 32767
        converted_1 : Int32 = Int32(.value = source_1)
        if converted_1 != 32767 { status_code = 1 return }
    }
    -- Int16 to Int64: infallible
    {
        source_0 : Int16 = -32768
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != -32768 { status_code = 1 return }
        source_1 : Int16 = 32767
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 32767 { status_code = 1 return }
    }
    -- Int16 to UInt8: checked
    {
        source_0 : Int16 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int16 = 255
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 255 { status_code = 1 return }
        invalid_0 : Int16 = -1
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int16 = 256
        if is(.value = UInt8(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int16 to UInt16: checked
    {
        source_0 : Int16 = 0
        checked_0 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_0)
        converted_0 : UInt16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int16 = 32767
        checked_1 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_1)
        converted_1 : UInt16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : Int16 = -1
        if is(.value = UInt16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int16 to UInt32: checked
    {
        source_0 : Int16 = 0
        checked_0 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_0)
        converted_0 : UInt32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int16 = 32767
        checked_1 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_1)
        converted_1 : UInt32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : Int16 = -1
        if is(.value = UInt32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int16 to UInt64: checked
    {
        source_0 : Int16 = 0
        checked_0 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_0)
        converted_0 : UInt64 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int16 = 32767
        checked_1 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_1)
        converted_1 : UInt64 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : Int16 = -1
        if is(.value = UInt64(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int32 to Int8: checked
    {
        source_0 : Int32 = -128
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int32 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int32 = -129
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int32 = 128
        if is(.value = Int8(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int32 to Int16: checked
    {
        source_0 : Int32 = -32768
        checked_0 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_0)
        converted_0 : Int16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != -32768 { status_code = 1 return }
        source_1 : Int32 = 32767
        checked_1 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_1)
        converted_1 : Int16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : Int32 = -32769
        if is(.value = Int16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int32 = 32768
        if is(.value = Int16(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int32 to Int32: infallible
    {
        source_0 : Int32 = -2147483648
        converted_0 : Int32 = Int32(.value = source_0)
        if converted_0 != -2147483648 { status_code = 1 return }
        source_1 : Int32 = 2147483647
        converted_1 : Int32 = Int32(.value = source_1)
        if converted_1 != 2147483647 { status_code = 1 return }
    }
    -- Int32 to Int64: infallible
    {
        source_0 : Int32 = -2147483648
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != -2147483648 { status_code = 1 return }
        source_1 : Int32 = 2147483647
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 2147483647 { status_code = 1 return }
    }
    -- Int32 to UInt8: checked
    {
        source_0 : Int32 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int32 = 255
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 255 { status_code = 1 return }
        invalid_0 : Int32 = -1
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int32 = 256
        if is(.value = UInt8(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int32 to UInt16: checked
    {
        source_0 : Int32 = 0
        checked_0 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_0)
        converted_0 : UInt16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int32 = 65535
        checked_1 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_1)
        converted_1 : UInt16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 65535 { status_code = 1 return }
        invalid_0 : Int32 = -1
        if is(.value = UInt16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int32 = 65536
        if is(.value = UInt16(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int32 to UInt32: checked
    {
        source_0 : Int32 = 0
        checked_0 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_0)
        converted_0 : UInt32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int32 = 2147483647
        checked_1 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_1)
        converted_1 : UInt32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 2147483647 { status_code = 1 return }
        invalid_0 : Int32 = -1
        if is(.value = UInt32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int32 to UInt64: checked
    {
        source_0 : Int32 = 0
        checked_0 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_0)
        converted_0 : UInt64 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int32 = 2147483647
        checked_1 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_1)
        converted_1 : UInt64 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 2147483647 { status_code = 1 return }
        invalid_0 : Int32 = -1
        if is(.value = UInt64(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to Int8: checked
    {
        source_0 : Int64 = -128
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != -128 { status_code = 1 return }
        source_1 : Int64 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : Int64 = -129
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int64 = 128
        if is(.value = Int8(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to Int16: checked
    {
        source_0 : Int64 = -32768
        checked_0 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_0)
        converted_0 : Int16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != -32768 { status_code = 1 return }
        source_1 : Int64 = 32767
        checked_1 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_1)
        converted_1 : Int16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : Int64 = -32769
        if is(.value = Int16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int64 = 32768
        if is(.value = Int16(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to Int32: checked
    {
        source_0 : Int64 = -2147483648
        checked_0 : Errable#(.t: Int32, .reasons: (..out_of_range)) = Int32(.value = source_0)
        converted_0 : Int32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != -2147483648 { status_code = 1 return }
        source_1 : Int64 = 2147483647
        checked_1 : Errable#(.t: Int32, .reasons: (..out_of_range)) = Int32(.value = source_1)
        converted_1 : Int32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 2147483647 { status_code = 1 return }
        invalid_0 : Int64 = -2147483649
        if is(.value = Int32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int64 = 2147483648
        if is(.value = Int32(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to Int64: infallible
    {
        source_0 : Int64 = -9223372036854775808
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != -9223372036854775808 { status_code = 1 return }
        source_1 : Int64 = 9223372036854775807
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 9223372036854775807 { status_code = 1 return }
    }
    -- Int64 to UInt8: checked
    {
        source_0 : Int64 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int64 = 255
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 255 { status_code = 1 return }
        invalid_0 : Int64 = -1
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int64 = 256
        if is(.value = UInt8(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to UInt16: checked
    {
        source_0 : Int64 = 0
        checked_0 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_0)
        converted_0 : UInt16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int64 = 65535
        checked_1 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_1)
        converted_1 : UInt16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 65535 { status_code = 1 return }
        invalid_0 : Int64 = -1
        if is(.value = UInt16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int64 = 65536
        if is(.value = UInt16(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to UInt32: checked
    {
        source_0 : Int64 = 0
        checked_0 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_0)
        converted_0 : UInt32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int64 = 4294967295
        checked_1 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_1)
        converted_1 : UInt32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 4294967295 { status_code = 1 return }
        invalid_0 : Int64 = -1
        if is(.value = UInt32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
        invalid_1 : Int64 = 4294967296
        if is(.value = UInt32(.value = invalid_1), .variant = ..error) == false { status_code = 2 return }
    }
    -- Int64 to UInt64: checked
    {
        source_0 : Int64 = 0
        checked_0 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_0)
        converted_0 : UInt64 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : Int64 = 9223372036854775807
        checked_1 : Errable#(.t: UInt64, .reasons: (..out_of_range)) = UInt64(.value = source_1)
        converted_1 : UInt64 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 9223372036854775807 { status_code = 1 return }
        invalid_0 : Int64 = -1
        if is(.value = UInt64(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt8 to Int8: checked
    {
        source_0 : UInt8 = 0
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : UInt8 = 128
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt8 to Int16: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : Int16 = Int16(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : Int16 = Int16(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt8 to Int32: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : Int32 = Int32(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : Int32 = Int32(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt8 to Int64: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt8 to UInt8: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : UInt8 = UInt8(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : UInt8 = UInt8(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt8 to UInt16: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : UInt16 = UInt16(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : UInt16 = UInt16(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt8 to UInt32: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : UInt32 = UInt32(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : UInt32 = UInt32(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt8 to UInt64: infallible
    {
        source_0 : UInt8 = 0
        converted_0 : UInt64 = UInt64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt8 = 255
        converted_1 : UInt64 = UInt64(.value = source_1)
        if converted_1 != 255 { status_code = 1 return }
    }
    -- UInt16 to Int8: checked
    {
        source_0 : UInt16 = 0
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : UInt16 = 128
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt16 to Int16: checked
    {
        source_0 : UInt16 = 0
        checked_0 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_0)
        converted_0 : Int16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 32767
        checked_1 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_1)
        converted_1 : Int16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : UInt16 = 32768
        if is(.value = Int16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt16 to Int32: infallible
    {
        source_0 : UInt16 = 0
        converted_0 : Int32 = Int32(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 65535
        converted_1 : Int32 = Int32(.value = source_1)
        if converted_1 != 65535 { status_code = 1 return }
    }
    -- UInt16 to Int64: infallible
    {
        source_0 : UInt16 = 0
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 65535
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 65535 { status_code = 1 return }
    }
    -- UInt16 to UInt8: checked
    {
        source_0 : UInt16 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 255
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 255 { status_code = 1 return }
        invalid_0 : UInt16 = 256
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt16 to UInt16: infallible
    {
        source_0 : UInt16 = 0
        converted_0 : UInt16 = UInt16(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 65535
        converted_1 : UInt16 = UInt16(.value = source_1)
        if converted_1 != 65535 { status_code = 1 return }
    }
    -- UInt16 to UInt32: infallible
    {
        source_0 : UInt16 = 0
        converted_0 : UInt32 = UInt32(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 65535
        converted_1 : UInt32 = UInt32(.value = source_1)
        if converted_1 != 65535 { status_code = 1 return }
    }
    -- UInt16 to UInt64: infallible
    {
        source_0 : UInt16 = 0
        converted_0 : UInt64 = UInt64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt16 = 65535
        converted_1 : UInt64 = UInt64(.value = source_1)
        if converted_1 != 65535 { status_code = 1 return }
    }
    -- UInt32 to Int8: checked
    {
        source_0 : UInt32 = 0
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : UInt32 = 128
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt32 to Int16: checked
    {
        source_0 : UInt32 = 0
        checked_0 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_0)
        converted_0 : Int16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 32767
        checked_1 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_1)
        converted_1 : Int16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : UInt32 = 32768
        if is(.value = Int16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt32 to Int32: checked
    {
        source_0 : UInt32 = 0
        checked_0 : Errable#(.t: Int32, .reasons: (..out_of_range)) = Int32(.value = source_0)
        converted_0 : Int32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 2147483647
        checked_1 : Errable#(.t: Int32, .reasons: (..out_of_range)) = Int32(.value = source_1)
        converted_1 : Int32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 2147483647 { status_code = 1 return }
        invalid_0 : UInt32 = 2147483648
        if is(.value = Int32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt32 to Int64: infallible
    {
        source_0 : UInt32 = 0
        converted_0 : Int64 = Int64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 4294967295
        converted_1 : Int64 = Int64(.value = source_1)
        if converted_1 != 4294967295 { status_code = 1 return }
    }
    -- UInt32 to UInt8: checked
    {
        source_0 : UInt32 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 255
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 255 { status_code = 1 return }
        invalid_0 : UInt32 = 256
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt32 to UInt16: checked
    {
        source_0 : UInt32 = 0
        checked_0 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_0)
        converted_0 : UInt16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 65535
        checked_1 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_1)
        converted_1 : UInt16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 65535 { status_code = 1 return }
        invalid_0 : UInt32 = 65536
        if is(.value = UInt16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt32 to UInt32: infallible
    {
        source_0 : UInt32 = 0
        converted_0 : UInt32 = UInt32(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 4294967295
        converted_1 : UInt32 = UInt32(.value = source_1)
        if converted_1 != 4294967295 { status_code = 1 return }
    }
    -- UInt32 to UInt64: infallible
    {
        source_0 : UInt32 = 0
        converted_0 : UInt64 = UInt64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt32 = 4294967295
        converted_1 : UInt64 = UInt64(.value = source_1)
        if converted_1 != 4294967295 { status_code = 1 return }
    }
    -- UInt64 to Int8: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_0)
        converted_0 : Int8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 127
        checked_1 : Errable#(.t: Int8, .reasons: (..out_of_range)) = Int8(.value = source_1)
        converted_1 : Int8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 127 { status_code = 1 return }
        invalid_0 : UInt64 = 128
        if is(.value = Int8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to Int16: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_0)
        converted_0 : Int16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 32767
        checked_1 : Errable#(.t: Int16, .reasons: (..out_of_range)) = Int16(.value = source_1)
        converted_1 : Int16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 32767 { status_code = 1 return }
        invalid_0 : UInt64 = 32768
        if is(.value = Int16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to Int32: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: Int32, .reasons: (..out_of_range)) = Int32(.value = source_0)
        converted_0 : Int32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 2147483647
        checked_1 : Errable#(.t: Int32, .reasons: (..out_of_range)) = Int32(.value = source_1)
        converted_1 : Int32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 2147483647 { status_code = 1 return }
        invalid_0 : UInt64 = 2147483648
        if is(.value = Int32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to Int64: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: Int64, .reasons: (..out_of_range)) = Int64(.value = source_0)
        converted_0 : Int64 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 9223372036854775807
        checked_1 : Errable#(.t: Int64, .reasons: (..out_of_range)) = Int64(.value = source_1)
        converted_1 : Int64 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 9223372036854775807 { status_code = 1 return }
        invalid_0 : UInt64 = 9223372036854775808
        if is(.value = Int64(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to UInt8: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_0)
        converted_0 : UInt8 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 255
        checked_1 : Errable#(.t: UInt8, .reasons: (..out_of_range)) = UInt8(.value = source_1)
        converted_1 : UInt8 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 255 { status_code = 1 return }
        invalid_0 : UInt64 = 256
        if is(.value = UInt8(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to UInt16: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_0)
        converted_0 : UInt16 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 65535
        checked_1 : Errable#(.t: UInt16, .reasons: (..out_of_range)) = UInt16(.value = source_1)
        converted_1 : UInt16 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 65535 { status_code = 1 return }
        invalid_0 : UInt64 = 65536
        if is(.value = UInt16(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to UInt32: checked
    {
        source_0 : UInt64 = 0
        checked_0 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_0)
        converted_0 : UInt32 = unwrap_or_abort(.value = checked_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 4294967295
        checked_1 : Errable#(.t: UInt32, .reasons: (..out_of_range)) = UInt32(.value = source_1)
        converted_1 : UInt32 = unwrap_or_abort(.value = checked_1)
        if converted_1 != 4294967295 { status_code = 1 return }
        invalid_0 : UInt64 = 4294967296
        if is(.value = UInt32(.value = invalid_0), .variant = ..error) == false { status_code = 2 return }
    }
    -- UInt64 to UInt64: infallible
    {
        source_0 : UInt64 = 0
        converted_0 : UInt64 = UInt64(.value = source_0)
        if converted_0 != 0 { status_code = 1 return }
        source_1 : UInt64 = 18446744073709551615
        converted_1 : UInt64 = UInt64(.value = source_1)
        if converted_1 != 18446744073709551615 { status_code = 1 return }
    }
}
