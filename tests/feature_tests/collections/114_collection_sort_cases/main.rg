main() -> (.status_code: Int32 = 0) := {
    values : [7]Int32 = (-99, -99, -99, -99, -99, -99, -99)
    view ::= array_view(.array = $&values).view
    order ::= Int32OrderPolicy()
    size :: UIntNative = 0
    cases :: UIntNative = 1
    -- Enumerate every sequence over {0, 1, 2} through length seven.
    while size <= 7 {
        sequence :: UIntNative = 0
        while sequence < cases {
            code ::= sequence
            zeros :: UIntNative = 0
            ones :: UIntNative = 0
            twos :: UIntNative = 0
            index :: UIntNative = 0
            while index < 7 {
                values[index] = -99
                index = index + 1
            }
            index = 0
            while index < size {
                digit ::= code % 3
                code = code / 3
                if digit == 0 {
                    values[index] = 0
                    zeros = zeros + 1
                } else {
                    if digit == 1 {
                        values[index] = 1
                        ones = ones + 1
                    } else {
                        values[index] = 2
                        twos = twos + 1
                    }
                }
                index = index + 1
            }
            prefix ::= unwrap_or_abort(.value = slice(.self = &view, .start = 0, .count = size))
            sort(.self = $&prefix, .order = &order)
            index = 0
            while index < size {
                expected :: Int32 = 2
                if index < zeros { expected = 0 } else {
                    if index < zeros + ones { expected = 1 }
                }
                if values[index] != expected { abort }
                index = index + 1
            }
            if zeros + ones + twos != size { abort }
            while index < 7 {
                if values[index] != -99 { abort }
                index = index + 1
            }
            sequence = sequence + 1
        }
        size = size + 1
        cases = cases * 3
    }
}
