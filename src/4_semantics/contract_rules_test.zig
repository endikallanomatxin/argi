const checkSourceWithout = @import("source_test_support.zig").checkSourceWithout;
const checkSyntaxSource = @import("source_test_support.zig").checkSyntaxSource;
const checkSource = @import("source_test_support.zig").checkSource;

test "contract diagnostic 102X_duplicate_body_member" {
    try checkSource("102X_duplicate_body_member",
        \\Product#(.Input: Type): Contract = (
        \\    .Result : Type
        \\    .Result : Int
        \\)
        \\
        \\main := () -> () {}
    , null, "duplicate associated contract member name", false);
}

test "contract diagnostic 106X_associated_argument_not_participant" {
    try checkSource("106X_associated_argument_not_participant",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\)
        \\
        \\Row: Type = ()
        \\
        \\Column: Type = ()
        \\
        \\implement Product#(.Left: Row, .Result: Int32) (.Result: Type = Int32)
        \\
        \\main := () -> () {}
    , null, "unknown argument name", false);
}

test "contract diagnostic 117X_duplicate_operation_identity" {
    try checkSource("117X_duplicate_operation_identity",
        \\Duplicate#(.T: Type): Contract = (
        \\    .copy : (.value: &T) -> (.result: T)
        \\    .copy : (.value: T) -> (.result: T)
        \\)
        \\
        \\main := () -> () {}
    , null, "duplicate contract operation identity", false);
}

test "contract diagnostic 118X_missing_implementation_operation" {
    try checkSource("118X_missing_implementation_operation",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (
        \\    .Result : Type
        \\    .read   : (.value: &T) -> (.result: Result)
        \\)
        \\
        \\implement Reader#(Cell) (.Result: Type = Int32)
        \\
        \\main := () -> () {}
    , null, "missing implementation operation", false);
}

test "contract diagnostic 119X_unknown_implementation_operation" {
    try checkSource("119X_unknown_implementation_operation",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
        \\
        \\read_cell := (.value: &Cell) -> (.result: Int32) { result = value&.value }
        \\
        \\implement Reader#(Cell) (.write = read_cell)
        \\
        \\main := () -> () {}
    , null, "unknown implementation operation", false);
}

test "contract diagnostic 120X_duplicate_implementation_operation" {
    try checkSource("120X_duplicate_implementation_operation",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
        \\
        \\read_cell := (.value: &Cell) -> (.result: Int32) { result = value&.value }
        \\
        \\implement Reader#(Cell) (
        \\    .read = read_cell
        \\    .read = read_cell
        \\)
        \\
        \\main := () -> () {}
    , null, "duplicate implementation operation", false);
}

test "contract diagnostic 121X_implementation_result_mismatch" {
    try checkSource("121X_implementation_result_mismatch",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (
        \\    .Result : Type
        \\    .read   : (.value: &T) -> (.result: Result)
        \\)
        \\
        \\read_cell := (.value: &Cell) -> (.result: UInt8) { result = 1 }
        \\
        \\implement Reader#(Cell) (
        \\    .Result : Type = Int32
        \\    .read   = read_cell
        \\)
        \\
        \\main := () -> () {}
    , null, "operation returns an incompatible associated result", false);
}

test "contract diagnostic 122X_implementation_input_mismatch" {
    try checkSource("122X_implementation_input_mismatch",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
        \\
        \\read_integer := (.value: Int32) -> (.result: Int32) { result = value }
        \\
        \\implement Reader#(Cell) (.read = read_integer)
        \\
        \\main := () -> () {}
    , null, "incompatible input signature", false);
}

test "contract diagnostic 123X_operation_requires_explicit_implementation" {
    try checkSource("123X_operation_requires_explicit_implementation",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
        \\
        \\read := (.value: &Cell) -> (.result: Int32) { result = value&.value }
        \\
        \\implement Reader#(Cell) ()
        \\
        \\main := () -> () {}
    , null, "missing implementation operation", false);
}

test "contract diagnostic 124X_unknown_operation_alias" {
    try checkSource("124X_unknown_operation_alias",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
        \\
        \\implement Reader#(Cell) (.read = nonexistent_function)
        \\
        \\main := () -> () {}
    , null, "unknown or inaccessible implementation function", false);
}

test "contract diagnostic 135X_generic_implementation_result" {
    try checkSource("135X_generic_implementation_result",
        \\Copyable#(.Value: Type): Contract = (
        \\    .Result : Type
        \\    .copy   : (.value: Value) -> (.result: Result)
        \\)
        \\
        \\implement#(.T: Type) Copyable#(T) (
        \\    .Result : Type = T
        \\    .copy   = (.value: T) -> (.result: UInt8) { result = 1 }
        \\)
        \\
        \\main := () -> () {
        \\    Copyable#(Int32).copy(42)
        \\}
    , null, "incompatible associated result", false);
}

test "contract diagnostic 136X_generic_implementation_overlap" {
    try checkSource("136X_generic_implementation_overlap",
        \\Copyable#(.Value: Type): Contract = (.Result: Type, .copy: (.value: Value) -> (.result: Result))
        \\
        \\implement#(.T: Type) Copyable#(T) (
        \\    .Result : Type = T
        \\    .copy   = (.value: T) -> (.result: Result) { result = value }
        \\)
        \\
        \\implement#(.U: Type) Copyable#(U) (
        \\    .Result : Type = U
        \\    .copy   = (.value: U) -> (.result: Result) { result = value }
        \\)
        \\
        \\main := () -> () { Copyable#(Int32).copy(42) }
    , null, "equivalent implementation participant patterns", false);
}

test "contract diagnostic 138X_incomparable_generic_patterns" {
    try checkSource("138X_incomparable_generic_patterns",
        \\Pair#(.Left: Type, .Right: Type): Contract = (
        \\    .classify : (.left: Left, .right: Right) -> (.result: Int32)
        \\)
        \\
        \\implement#(.T: Type) Pair#(T, Int32) (
        \\    .classify = (.left: T, .right: Int32) -> (.result: Int32) { result = 1 }
        \\)
        \\
        \\implement#(.U: Type) Pair#(Int32, U) (
        \\    .classify = (.left: Int32, .right: U) -> (.result: Int32) { result = 2 }
        \\)
        \\
        \\main := () -> () { Pair#(Int32, Int32).classify(3, 4) }
    , null, "ambiguous maximal patterns", false);
}

test "contract diagnostic 147X_equivalent_nominal_patterns" {
    try checkSource("147X_equivalent_nominal_patterns",
        \\Kind#(.Value: Type): Contract = (.classify: (.value: &Value) -> (.result: Int32))
        \\
        \\Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)
        \\
        \\implement#(.A: Type, .B: Type) Kind#(Pair#(A, B)) (
        \\    .classify = (.value: &Pair#(A, B)) -> (.result: Int32) { result = 1 }
        \\)
        \\
        \\implement#(.X: Type, .Y: Type) Kind#(Pair#(.Right: Y, .Left: X)) (
        \\    .classify = (.value: &Pair#(X, Y)) -> (.result: Int32) { result = 2 }
        \\)
        \\
        \\main := () -> () {
        \\    pair: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
        \\    Kind#(Pair#(Int32, UInt8)).classify(&pair)
        \\}
    , null, "equivalent implementation participant patterns", false);
}

test "contract diagnostic 148X_incomparable_nominal_patterns" {
    try checkSource("148X_incomparable_nominal_patterns",
        \\Kind#(.Value: Type): Contract = (.classify: (.value: &Value) -> (.result: Int32))
        \\
        \\Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)
        \\
        \\implement#(.T: Type) Kind#(Pair#(T, Int32)) (
        \\    .classify = (.value: &Pair#(T, Int32)) -> (.result: Int32) { result = 1 }
        \\)
        \\
        \\implement#(.T: Type) Kind#(Pair#(Int32, T)) (
        \\    .classify = (.value: &Pair#(Int32, T)) -> (.result: Int32) { result = 2 }
        \\)
        \\
        \\main := () -> () {
        \\    pair: Pair#(Int32, Int32) = (.left = 1, .right = 2)
        \\    Kind#(Pair#(Int32, Int32)).classify(&pair)
        \\}
    , null, "overlapping generic implementations have ambiguous maximal patterns", false);
}

test "contract diagnostic 04X_missing_operation" {
    try checkSource("04X_missing_operation",
        \\Readable#(.Value: Type): Contract = (
        \\    .read : (.source: &Value) -> (.value: Int32)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Readable#(Cell) ()
        \\
        \\main := () -> () {}
    , null, "missing implementation operation", false);
}

test "contract diagnostic 08X_ambiguous_operation" {
    try checkSource("08X_ambiguous_operation",
        \\Readable#(.Value: Type): Contract = (
        \\    .read : (.source: &Value) -> (.value: Int32)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\_first_read := (.source: &Cell) -> (.value: Int32) { value = source&.value }
        \\
        \\_second_read := (.source: &Cell) -> (.value: Int32) { value = 2 }
        \\
        \\implement Readable#(Cell) (.read = _first_read)
        \\
        \\implement Readable#(Cell) (.read = _second_read)
        \\
        \\-- Identical participant patterns cannot establish two conformances.
        \\main := () -> () {}
    , null, "ambiguous conformances for the same participant tuple", false);
}

test "contract diagnostic 09X_incompatible_output" {
    try checkSource("09X_incompatible_output",
        \\Readable#(.Participant: Type): Contract = (
        \\    .read : (.source: &Participant) -> (.value: Int32) where {}
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Readable#(Cell) (.read = _impl_read_Cell)
        \\
        \\_impl_read_Cell := (.source: &Cell) -> (.value: Float64) { value = 2.5 }
        \\
        \\consume := #(.source_type: Type: Readable) (.source: &source_type) -> (.value: Int32) {
        \\    value = read(source)
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    cell ::= Cell(42)
        \\    if consume(&cell).value != 42 { abort }
        \\}
    , null, "operation returns an incompatible associated result", false);
}

test "contract diagnostic 108X_shared_generic_associated_mismatch" {
    try checkSource("108X_shared_generic_associated_mismatch",
        \\Readable#(.Participant: Type): Contract = (
        \\    .Other : Type
        \\    .item  : Type
        \\    .Count : Int
        \\    .read  : (.other: &Other, .source: &Participant) -> (.value: &item)
        \\    where depends_on(value, source)
        \\)
        \\
        \\Direct := (.value: Int32)
        \\
        \\Cell := #(.item: Type) (.value: item)
        \\
        \\implement Readable#(Direct) (
        \\    .Count : Int  = 2,
        \\    .item  : Type = Int32,
        \\    .Other : Type = Direct,
        \\    .read  = _direct_read
        \\)
        \\
        \\implement#(.item: Type) Readable#(Cell#(item)) (
        \\    .item  : Type = item,
        \\    .Other : Type = Cell#(item),
        \\    .Count : Int  = 2,
        \\    .read  = _cell_read
        \\)
        \\
        \\_direct_read := (.other: &Direct, .source: &Direct) -> (.value: &Int32) {
        \\    value = &source&.value
        \\}
        \\
        \\_cell_read := #(.item: Type) (.other: &Cell#(item), .source: &Cell#(item)) -> (.value: &item) {
        \\    value = &source&.value
        \\}
        \\
        \\consume := #(.item: Type, .n: Int, .T: Type: Readable#(.Other: T, .Count = n, .item: item)) (
        \\    .other: &T, .source: &T
        \\) -> (.value: &item) { value = read(other, source).value }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    direct_other ::= Direct(7)
        \\    direct ::= Direct(42)
        \\    generic_other ::= Cell#(Int32)(8)
        \\    generic ::= Cell#(Int32)(43)
        \\    if consume#(.item: Int32, .n = 2, .T: Direct)(&direct_other, &direct)&!= 42 { abort }
        \\    if consume#(.item: Int32, .n = 3, .T: Cell#(Int32))(&generic_other, &generic)&!= 43 { abort }
        \\    direct_handle ::= to_virtual#(.contract: Readable#(.item: Int32, .Count = 2, .Other: Direct))(
        \\        .value = &direct
        \\    )
        \\    generic_handle ::= to_virtual#(
        \\        .contract: Readable#(.Other: Cell#(Int32), .item: Int32, .Count = 2)
        \\    )(.value = &generic)
        \\    if read(&direct_other, &direct_handle)&!= 42 { abort }
        \\    if read(&generic_other, &generic_handle)&!= 43 { abort }
        \\}
    , null, "constraint", false);
}

test "contract diagnostic 109X_shared_direct_associated_conflict" {
    try checkSource("109X_shared_direct_associated_conflict",
        \\Readable#(.Participant: Type): Contract = (
        \\    .Other : Type
        \\    .item  : Type
        \\    .Count : Int
        \\    .read  : (.other: &Other, .source: &Participant) -> (.value: &item)
        \\    where depends_on(value, source)
        \\)
        \\
        \\Direct := (.value: Int32)
        \\
        \\Cell := #(.item: Type) (.value: item)
        \\
        \\implement Readable#(Direct) (
        \\    .Count : Int  = 2,
        \\    .item  : Type = Int32,
        \\    .Other : Type = Direct,
        \\    .read  = _direct_read
        \\)
        \\
        \\implement Readable#(Direct) (
        \\    .Count : Int  = 3,
        \\    .item  : Type = Int32,
        \\    .Other : Type = Direct,
        \\    .read  = _direct_read
        \\)
        \\
        \\implement#(.item: Type) Readable#(Cell#(item)) (
        \\    .item  : Type = item,
        \\    .Other : Type = Cell#(item),
        \\    .Count : Int  = 2,
        \\    .read  = _cell_read
        \\)
        \\
        \\_direct_read := (.other: &Direct, .source: &Direct) -> (.value: &Int32) {
        \\    value = &source&.value
        \\}
        \\
        \\_cell_read := #(.item: Type) (.other: &Cell#(item), .source: &Cell#(item)) -> (.value: &item) {
        \\    value = &source&.value
        \\}
        \\
        \\consume := #(.item: Type, .n: Int, .T: Type: Readable#(.Other: T, .Count = n, .item: item)) (
        \\    .other: &T, .source: &T
        \\) -> (.value: &item) { value = read(other, source).value }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    direct_other ::= Direct(7)
        \\    direct ::= Direct(42)
        \\    generic_other ::= Cell#(Int32)(8)
        \\    generic ::= Cell#(Int32)(43)
        \\    if consume#(.item: Int32, .n = 2, .T: Direct)(&direct_other, &direct)&!= 42 { abort }
        \\    if consume#(.item: Int32, .n = 2, .T: Cell#(Int32))(&generic_other, &generic)&!= 43 { abort }
        \\    direct_handle ::= to_virtual#(.contract: Readable#(.item: Int32, .Count = 2, .Other: Direct))(
        \\        .value = &direct
        \\    )
        \\    generic_handle ::= to_virtual#(
        \\        .contract: Readable#(.Other: Cell#(Int32), .item: Int32, .Count = 2)
        \\    )(.value = &generic)
        \\    if read(&direct_other, &direct_handle)&!= 42 { abort }
        \\    if read(&generic_other, &generic_handle)&!= 43 { abort }
        \\}
    , null, "ambiguous conformances for the same participant tuple", false);
}

test "contract diagnostic 111X_ordinary_function_overload" {
    try checkSource("111X_ordinary_function_overload",
        \\read := (.value: Int32) -> (.result: Int32) { result = value }
        \\read := (.value: UInt8) -> (.result: UInt8) { result = value }
        \\main := () -> () {}
    , null, "ordinary function 'read' has more than one declaration", false);
}

test "contract diagnostic 112X_ordinary_generic_arity" {
    try checkSource("112X_ordinary_generic_arity",
        \\identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
        \\
        \\identity := #(.T: Type, .Unused: Type) (.value: T) -> (.result: T) { result = value }
        \\
        \\main := () -> () {}
    , null, "ordinary function 'identity' has more than one declaration", false);
}

test "contract diagnostic 125X_qualified_operation_argument_mismatch" {
    try checkSource("125X_qualified_operation_argument_mismatch",
        \\Cell := (.value: Int32)
        \\
        \\Reader#(.T: Type): Contract = (.read: (.value: &T) -> (.result: Int32))
        \\
        \\implement Reader#(Cell) (
        \\    .read = (.value: &Cell) -> (.result: Int32) { result = value&.value }
        \\)
        \\
        \\main := () -> () { Reader#(Cell).read(7) }
    , null, "arguments do not match the selected contract operation", false);
}

test "contract diagnostic 149X_scoped_virtual_mutability" {
    try checkSource("149X_scoped_virtual_mutability",
        \\Input#(.Stream: Type): Contract = (
        \\    .read_byte : (.self: $&Stream) -> (.result: UInt8) where {}
        \\)
        \\
        \\Cursor := (.value: UInt8 = 7)
        \\
        \\implement Input#(Cursor) (
        \\    .read_byte = (.self: $&Cursor) -> (.result: UInt8) { result = self&.value }
        \\)
        \\
        \\main := () -> () {
        \\    stream ::= Cursor()
        \\    erased ::= to_virtual#(.contract: Input)(.value = &stream)
        \\}
    , null, "a mutable participant receiver requires a mutable concrete reference", false);
}

test "contract diagnostic 15X_tuple_wrong_result" {
    try checkSource("15X_tuple_wrong_result",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int64, .multiply = _impl_multiply_253)
        \\
        \\_impl_multiply_253 := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> () {}
    , null, "operation returns an incompatible associated result", false);
}

test "contract diagnostic 161X_unqualified_contract_ambiguity" {
    try checkSource("161X_unqualified_contract_ambiguity",
        \\First#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))
        \\
        \\Second#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))
        \\
        \\implement#(.T: Type) First#(T) (.copy = (.value: T) -> (.result: T) { result = value })
        \\
        \\implement Second#(Int32) (.copy = (.value: Int32) -> (.result: Int32) { result = value })
        \\
        \\main := () -> () {
        \\    value: Int32 = 7
        \\    copy(value)
        \\}
    , null, "multiple applicable operation identities", false);
}

test "contract diagnostic 162X_unqualified_ordinary_ambiguity" {
    try checkSource("162X_unqualified_ordinary_ambiguity",
        \\Copy#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))
        \\
        \\implement Copy#(Int32) (.copy = (.value: Int32) -> (.result: Int32) { result = value })
        \\
        \\copy := (.value: Int32) -> (.result: Int32) { result = value }
        \\
        \\main := () -> () {
        \\    value: Int32 = 7
        \\    copy(value)
        \\}
    , null, "multiple applicable operation identities", false);
}

test "contract diagnostic 164X_unqualified_generic_ordinary_ambiguity" {
    try checkSource("164X_unqualified_generic_ordinary_ambiguity",
        \\Copy#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))
        \\
        \\implement Copy#(Int32) (.copy = (.value: Int32) -> (.result: Int32) { result = value })
        \\
        \\copy := #(.T: Type) (.value: T) -> (.result: T) { result = value }
        \\
        \\main := () -> () {
        \\    value: Int32 = 7
        \\    copy(value)
        \\}
    , null, "multiple applicable operation identities", false);
}

test "contract diagnostic 166X_generic_operation_identity_ambiguity" {
    try checkSource("166X_generic_operation_identity_ambiguity",
        \\First#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))
        \\
        \\Second#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))
        \\
        \\implement First#(Int32) (.copy = (.value: Int32) -> (.result: Int32) { result = value })
        \\
        \\implement Second#(Int32) (.copy = (.value: Int32) -> (.result: Int32) { result = value })
        \\
        \\wrapper := #(.T: Type) (.value: T) -> (.result: T) { result = copy(value) }
        \\
        \\main := () -> () {
        \\    value: Int32 = 7
        \\    wrapper(value)
        \\}
    , null, "multiple applicable operation identities", false);
}

test "contract diagnostic 16X_tuple_missing_operation" {
    try checkSource("16X_tuple_missing_operation",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32)
        \\
        \\main := () -> () {}
    , null, "missing implementation operation", false);
}

test "contract diagnostic 17X_tuple_ambiguous_operation" {
    try checkSource("17X_tuple_ambiguous_operation",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result   : Type
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result)
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\_int_product := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = [left&.value * right&.value]
        \\}
        \\
        \\_wide_product := (.left: &Row, .right: &Column) -> (.value: Int64) { value = 0 }
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _int_product)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int64, .multiply = _wide_product)
        \\
        \\-- The associated result cannot distinguish two identical participant tuples.
        \\main := () -> () {}
    , null, "ambiguous conformances for the same participant tuple", false);
}

test "contract diagnostic 18X_duplicate_tuple" {
    try checkSource("18X_duplicate_tuple",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_319)
        \\
        \\implement Product#(.Right: Column, .Left: Row) (
        \\    .Result   : Type = Int64,
        \\    .multiply = _impl_multiply_319
        \\)
        \\
        \\_impl_multiply_319 := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> () {}
    , null, "ambiguous conformances for the same participant tuple", false);
}

test "contract diagnostic 19X_missing_participant" {
    try checkSource("19X_missing_participant",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row) (.Result: Type = Int32, .multiply = _impl_multiply_245)
        \\
        \\_impl_multiply_245 := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> () {}
    , null, "missing argument", false);
}

test "contract diagnostic 20X_unknown_participant" {
    try checkSource("20X_unknown_participant",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(.Unknown: Row, .Right: Column) (
        \\    .Result   : Type = Int32,
        \\    .multiply = _impl_multiply_271
        \\)
        \\
        \\_impl_multiply_271 := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> () {}
    , null, "unknown argument name", false);
}

test "contract diagnostic 21X_participant_kind" {
    try checkSource("21X_participant_kind",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(.Left = 3, .Right: Column) (.Result: Type = Int32, .multiply = multiply)
        \\
        \\multiply := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> () {}
    , null, "argument kind does not match its parameter", false);
}

test "contract diagnostic 22X_missing_associated" {
    try checkSource("22X_missing_associated",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.multiply = _impl_multiply_234)
        \\
        \\_impl_multiply_234 := (.left: &Row, .right: &Column) -> (.value: Int32) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> () {}
    , null, "missing argument", false);
}

test "contract diagnostic 23X_explicit_self" {
    try checkSource("23X_explicit_self",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Self, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\main := () -> () {}
    , null, "use named participants instead of Self", false);
}

test "contract diagnostic 24X_duplicate_parameter" {
    try checkSource("24X_duplicate_parameter",
        \\Product#(.Left: Type, .Result: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\main := () -> () {}
    , null, "duplicate participant or associated parameter name", false);
}

test "contract diagnostic 28X_unknown_contract" {
    try checkSource("28X_unknown_contract",
        \\Cell: Type = ()
        \\
        \\implement Unknown#(Cell) ()
        \\
        \\main := () -> () {}
    , null, "unknown or inaccessible contract", false);
}

test "contract diagnostic 310X_virtual_scoped_association_mismatch" {
    try checkSource("310X_virtual_scoped_association_mismatch",
        \\Readable#(.Value: Type): Contract = (
        \\    .Item  : Type
        \\    .Count : Int
        \\    .read  : (.self: &Value) -> (.value: Item) where {}
        \\)
        \\
        \\Integer := (.value: Int32)
        \\
        \\Floating := (.value: Float64)
        \\
        \\_read_integer := (.self: &Integer) -> (.value: Int32) { value = self&.value }
        \\
        \\_read_floating := (.self: &Floating) -> (.value: Float64) { value = self&.value }
        \\
        \\implement Readable#(Integer) (.Item: Type = Int32, .Count: Int = 1, .read = _read_integer)
        \\
        \\implement Readable#(Floating) (.Item: Type = Float64, .Count: Int = 2, .read = _read_floating)
        \\
        \\main := (.system: System) -> () {
        \\    integer ::= Integer(17)
        \\    erased ::= to_virtual#(.contract: Readable#(.Item: Float64, .Count = 1))(.value = &integer)
        \\}
    , null, "incompatible associated elements", false);
}

test "contract diagnostic 312X_scoped_static_association_mismatch" {
    try checkSource("312X_scoped_static_association_mismatch",
        \\Readable#(.Participant: Type): Contract = (
        \\    .Other : Type
        \\    .read  : (.other: &Other, .source: &Participant) -> (.value: &Int32)
        \\    where depends_on(value, source)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\_cell_read := (.other: &Cell, .source: &Cell) -> (.value: &Int32) { value = &source&.value }
        \\
        \\implement Readable#(Cell) (.Other: Type = Cell, .read = _cell_read)
        \\
        \\main := () -> () {
        \\    other ::= Cell(7)
        \\    source ::= Cell(42)
        \\    value ::= Readable#(.Other: Float64).read(&other, &source)
        \\}
    , null, "incompatible associated elements for the operation interface", false);
}

test "contract diagnostic 313X_scoped_virtual_association_mismatch" {
    try checkSource("313X_scoped_virtual_association_mismatch",
        \\Readable#(.Participant: Type): Contract = (
        \\    .Other : Type
        \\    .read  : (.other: &Other, .source: &Participant) -> (.value: &Int32)
        \\    where depends_on(value, source)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\_cell_read := (.other: &Cell, .source: &Cell) -> (.value: &Int32) { value = &source&.value }
        \\
        \\implement Readable#(Cell) (.Other: Type = Cell, .read = _cell_read)
        \\
        \\main := () -> () {
        \\    other ::= Cell(7)
        \\    source ::= Cell(42)
        \\    handle ::= to_virtual#(.contract: Readable#(.Other: Cell))(.value = &source)
        \\    value ::= Readable#(.Other: Float64).read(&other, &handle)
        \\}
    , null, "incompatible associated elements for the operation interface", false);
}

test "contract diagnostic 319X_implicit_self_contract" {
    try checkSource("319X_implicit_self_contract",
        \\Reader: Contract = (.read: (.value: &Self) -> ())
        \\main := () -> () {}
    , null, "use named participants instead of Self", false);
}

test "contract diagnostic 326X_selected_deferred_operation_body" {
    try checkSource("326X_selected_deferred_operation_body",
        \\Reader#(.Value: Type): Contract = (
        \\    .Result : Type
        \\    .read   : (.value: &Value) -> (.result: Result)
        \\)
        \\
        \\Cell := (.value: Int32)
        \\
        \\implement Reader#(Cell) (
        \\    .Result : Type = Int32
        \\    .read   = (.value: &Cell) -> (.result: Result) {
        \\        result = missing_operation().result
        \\    }
        \\)
        \\
        \\main := () -> () {
        \\    cell ::= Cell(42)
        \\    result ::= Reader#(Cell).read(&cell).result
        \\}
    , null, "cannot materialize function body", false);
}

test "contract diagnostic 32X_tuple_virtual" {
    try checkSource("32X_tuple_virtual",
        \\Pair#(.Left: Type, .Right: Type): Contract = ()
        \\
        \\Cell: Type = ()
        \\
        \\implement Pair#(Cell, Cell) ()
        \\
        \\main := () -> () {
        \\    cell ::= Cell()
        \\    handle ::= to_virtual#(.contract: Pair)(&cell)
        \\}
    , null, "explicit participants require joint virtual evidence", false);
}

test "contract diagnostic 333X_virtual_implementation_signature" {
    try checkSource("333X_virtual_implementation_signature",
        \\Open#(.T: Type): Contract = (.read: _)
        \\
        \\Owner := (.value: Int32)
        \\
        \\implement Open#(Owner) (
        \\    .read = (.self: &Owner) -> (.result: Int32) { result = self&.value }
        \\)
        \\
        \\main := () -> () {
        \\    owner: Owner = (.value = 42)
        \\    handle ::= to_virtual#(.contract: Open)(.value = &owner)
        \\}
    , null, "implementation-defined operation signatures require static selection and cannot be virtualized", false);
}

test "contract diagnostic 343X_open_operation_identity_ambiguity" {
    try checkSource("343X_open_operation_identity_ambiguity",
        \\First#(.T: Type): Contract = (.choose: _)
        \\Second#(.T: Type): Contract = (.choose: _)
        \\
        \\implement First#(Int32) (
        \\    .choose = (.value: Int32) -> (.result: Int32) { result = value }
        \\)
        \\implement Second#(Int32) (
        \\    .choose = (.value: Int32) -> (.result: Int32) { result = value }
        \\)
        \\
        \\main := () -> () { result ::= choose(42) }
    , null, "multiple applicable operation identities", false);
}

test "contract diagnostic 344X_open_operation_participant_ambiguity" {
    try checkSource("344X_open_operation_participant_ambiguity",
        \\First: Type = ()
        \\Second: Type = ()
        \\Build#(.Target: Type): Contract = (.build: _)
        \\
        \\implement Build#(First) (
        \\    .build = (.value: Int32) -> (.result: First) { result = () }
        \\)
        \\implement Build#(Second) (
        \\    .build = (.value: Int32) -> (.result: Second) { result = () }
        \\)
        \\
        \\main := () -> () { result: First = build(42) }
    , null, "operation inputs do not determine a unique participant tuple", false);
}

test "contract diagnostic 348X_bound_operation_signature" {
    try checkSource("348X_bound_operation_signature",
        \\identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
        \\int_identity := identity#(Int32)
        \\Fixed#(.T: Type): Contract = (.fixed_value: (.value: T) -> (.result: T))
        \\implement Fixed#(Bool) (.fixed_value = int_identity)
        \\main := () -> () {}
    , null, "the selected input signature does not match the generic operation alias", false);
}

test "contract diagnostic 349X_non_function_operation_value" {
    try checkSource("349X_non_function_operation_value",
        \\number := 42
        \\Action#(.T: Type): Contract = (.act: _)
        \\implement Action#(Int32) (.act = number)
        \\main := () -> () {}
    , null, "implementation operation must be a compile-time function definition value", false);
}

test "contract diagnostic 34X_tuple_associated_bound" {
    try checkSource("34X_tuple_associated_bound",
        \\Capability#(.Participant: Type): Contract = (
        \\    .item : Type
        \\)
        \\
        \\Group#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type: Capability#(.item: Left)
        \\)
        \\
        \\Row: Type = ()
        \\
        \\Column: Type = ()
        \\
        \\implement Capability#(Row) (.item: Type = Column)
        \\
        \\implement Group#(Row, Column) (.Result: Type = Row)
        \\
        \\main := () -> () {}
    , null, "does not satisfy its declared bound", false);
}

test "contract diagnostic 351X_operation_expression_value" {
    try checkSource("351X_operation_expression_value",
        \\Action#(.T: Type): Contract = (.act: _)
        \\
        \\implement Action#(Int32) (.act = 42)
        \\
        \\main := () -> () {}
    , null, "implementation operation must be a compile-time function definition value", false);
}

test "contract diagnostic 40X_empty_participants" {
    try checkSource("40X_empty_participants",
        \\Empty#(): Contract = ()
        \\
        \\main := () -> () {}
    , null, "at least one named participant", false);
}

test "contract diagnostic 41X_value_participant" {
    try checkSource("41X_value_participant",
        \\Pair#(.Left: Type, .Right: Int): Contract = ()
        \\
        \\main := () -> () {}
    , null, "participants must be named Type parameters", false);
}

test "contract diagnostic 42X_duplicate_participant_argument" {
    try checkSource("42X_duplicate_participant_argument",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\)
        \\
        \\Row: Type = ()
        \\
        \\Column: Type = ()
        \\
        \\implement Product#(.Left: Row, .Left: Column) (.Result: Type = Int32)
        \\
        \\main := () -> () {}
    , null, "duplicate argument", false);
}

test "contract diagnostic 43X_associated_kind" {
    try checkSource("43X_associated_kind",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\)
        \\
        \\Row: Type = ()
        \\
        \\Column: Type = ()
        \\
        \\implement Product#(Row, Column) (.Result: Int = 42)
        \\
        \\main := () -> () {}
    , null, "argument kind does not match its parameter", false);
}

test "contract diagnostic 44X_extra_participant" {
    try checkSource("44X_extra_participant",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\)
        \\
        \\Row: Type = ()
        \\
        \\Column: Type = ()
        \\
        \\implement Product#(Row, Column, Int32) (.Result: Type = Int32)
        \\
        \\main := () -> () {}
    , null, "too many arguments", false);
}

test "contract diagnostic 45X_missing_composed_dependency" {
    try checkSource("45X_missing_composed_dependency",
        \\Pair #(.Left: Type, .Right: Type ): Contract = ()
        \\Wrapper #(.Value: Type ): Contract = (Pair #( Value, Int32 ))
        \\Cell: Type = ()
        \\implement Wrapper #( Cell ) ()
        \\main := () -> () {}
    , null, "a required contract dependency is not satisfied", false);
}

test "contract diagnostic 47X_tuple_result_identity" {
    try checkSource("47X_tuple_result_identity",
        \\Reader#(.Participant: Type): Contract = ()
        \\
        \\Cell: Type = ()
        \\
        \\implement Reader#(Cell) ()
        \\
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: Left, .right: Right) -> (.value: Result) where {}
        \\)
        \\
        \\implement Product#(Int32, Int64) (.Result: Type = Reader, .multiply = _impl_multiply_254)
        \\
        \\_impl_multiply_254 := (.left: Int32, .right: Int64) -> (.value: Cell) { value = Cell() }
        \\
        \\main := () -> () {}
    , null, "operation returns an incompatible associated result", false);
}

test "contract diagnostic 50X_projection_missing_tuple" {
    try checkSource("50X_projection_missing_tuple",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_256)
        \\
        \\_impl_multiply_256 := (.left: &Row, .right: &Column) -> (.value: Product#(Column, Row).Result) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "no conformance for the projected participant tuple", false);
}

test "contract diagnostic 51X_projection_unknown_member" {
    try checkSource("51X_projection_unknown_member",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_256)
        \\
        \\_impl_multiply_256 := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Missing) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "unknown associated type", false);
}

test "contract diagnostic 53X_projection_wrong_argument" {
    try checkSource("53X_projection_wrong_argument",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_256)
        \\
        \\_impl_multiply_256 := (.left: &Row, .right: &Column) -> (
        \\    .value: Product#(.Wrong: Row, .Right: Column).Result
        \\) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "unknown argument name", false);
}

test "contract diagnostic 55X_projection_value_member" {
    try checkSource("55X_projection_value_member",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\    .Count  : Int
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (
        \\    .Result   : Type = Int32,
        \\    .Count    : Int  = 4,
        \\    .multiply = _impl_multiply_284
        \\)
        \\
        \\_impl_multiply_284 := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Count) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "associated element is not a type", false);
}

test "contract diagnostic 56X_projection_cycle" {
    try checkSource("56X_projection_cycle",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (
        \\    .Result   : Type = Product#(Row, Column).Result,
        \\    .multiply = _multiply
        \\)
        \\
        \\_multiply := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "cyclic or unresolved associated type projection", false);
}

test "contract diagnostic 59X_generic_projection_missing_tuple" {
    try checkSource("59X_generic_projection_missing_tuple",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _impl_multiply_256)
        \\
        \\_impl_multiply_256 := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\product := #(.A: Type, .B: Type) (.left: &A, .right: &B) -> (.value: Product#(B, A).Result) {
        \\    value = multiply(left, right).value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if product(&row, &column).value != 42 { abort }
        \\}
    , null, "no conformance for the projected participant tuple", false);
}

test "contract diagnostic 60X_projection_nested_cycle" {
    try checkSource("60X_projection_nested_cycle",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\implement Product#(Row, Column) (
        \\    .Result   : Type = Array#(.n = 1, .t: Product#(Row, Column).Result),
        \\    .multiply = _multiply
        \\)
        \\
        \\_multiply := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "cyclic or unresolved associated type projection", false);
}

test "contract diagnostic 61X_projection_duplicate_after_resolution" {
    try checkSource("61X_projection_duplicate_after_resolution",
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .Result : Type
        \\
        \\    .multiply : (.left: &Left, .right: &Right) -> (.value: Result) where {}
        \\)
        \\
        \\Row := (.value: Int32)
        \\
        \\Column := (.value: Int32)
        \\
        \\Kind#(.Input: Type): Contract = (
        \\    .Result : Type
        \\)
        \\
        \\implement Kind#(Row) (.Result: Type = Row)
        \\
        \\implement Product#(Row, Column) (.Result: Type = Int32, .multiply = _multiply)
        \\
        \\implement Product#(Kind#(Row).Result, Column) (.Result: Type = Int64, .multiply = _multiply)
        \\
        \\_multiply := (.left: &Row, .right: &Column) -> (.value: Product#(Row, Column).Result) {
        \\    value = left&.value * right&.value
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    row ::= Row(6)
        \\    column ::= Column(7)
        \\    if multiply(&row, &column).value != 42 { abort }
        \\}
    , null, "ambiguous conformances for the same participant tuple", false);
}

test "contract diagnostic 69X_constant_projection_unknown_member" {
    try checkSource("69X_constant_projection_unknown_member",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\read := (.values: &Array#(.n = Shape#(Cell).Missing, .t: Int32)) -> () {}
        \\
        \\main := () -> () {}
    , null, "unknown associated constant", false);
}

test "contract diagnostic 70X_constant_projection_missing_tuple" {
    try checkSource("70X_constant_projection_missing_tuple",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\read := (.values: &Array#(.n = Shape#(Int32).Count, .t: Int32)) -> () {}
        \\
        \\main := () -> () {}
    , null, "no conformance for the projected participant tuple", false);
}

test "contract diagnostic 71X_constant_projection_type_member" {
    try checkSource("71X_constant_projection_type_member",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Type
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Type = Int32)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if sum(&values).value != 42 { abort }
        \\}
    , null, "associated element is not an integer constant", false);
}

test "contract diagnostic 72X_constant_projection_negative_dimension" {
    try checkSource("72X_constant_projection_negative_dimension",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = -1)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if sum(&values).value != 42 { abort }
        \\}
    , null, "array length must be non-negative", false);
}

test "contract diagnostic 73X_constant_projection_overflow" {
    try checkSource("73X_constant_projection_overflow",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 9223372036854775807)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count + 1, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if sum(&values).value != 42 { abort }
        \\}
    , null, "compile-time integer arithmetic overflow", false);
}

test "contract diagnostic 74X_constant_projection_division_by_zero" {
    try checkSource("74X_constant_projection_division_by_zero",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count / 0, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if sum(&values).value != 42 { abort }
        \\}
    , null, "division by zero in compile-time expression", false);
}

test "contract diagnostic 75X_constant_projection_empty_tuple" {
    try checkSource("75X_constant_projection_empty_tuple",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\sum := (.values: &Array#(.n = Shape#().Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if sum(&values).value != 42 { abort }
        \\}
    , null, "missing argument", false);
}

test "contract diagnostic 82X_constant_projection_generic_overflow" {
    try checkSource("82X_constant_projection_generic_overflow",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 9223372036854775807)
        \\
        \\invalid := #(.T: Type) (.tag: T) -> (.value: Array#(.n = Shape#(T).Count + 1, .t: Int32)) {}
        \\
        \\main := () -> () { invalid#(.T: Cell) (Cell()) }
    , null, "compile-time integer arithmetic overflow", false);
}

test "contract diagnostic 83X_constant_projection_generic_negative_dimension" {
    try checkSource("83X_constant_projection_generic_negative_dimension",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = -1)
        \\
        \\invalid := #(.T: Type) (.tag: T) -> (.value: Array#(.n = Shape#(T).Count, .t: Int32)) {}
        \\
        \\main := () -> () { invalid#(.T: Cell) (Cell()) }
    , null, "array length must be non-negative", false);
}

test "contract diagnostic 87X_constant_projection_constructor_unknown_member" {
    try checkSource("87X_constant_projection_constructor_unknown_member",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\read_buffer := (.buffer: &Buffer#(.n = Shape#(Cell).Count)) -> (.value: Int32) {
        \\    value = sum(&buffer&.values).value
        \\}
        \\
        \\main := () -> () {
        \\    buffer ::= Buffer#(.n = Shape#(Cell).Missing)((20, 22))
        \\    if read_buffer(&buffer).value != 42 { abort }
        \\}
    , null, "unknown associated element", false);
}

test "contract diagnostic 88X_constant_projection_constructor_missing_tuple" {
    try checkSource("88X_constant_projection_constructor_missing_tuple",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\read_buffer := (.buffer: &Buffer#(.n = Shape#(Cell).Count)) -> (.value: Int32) {
        \\    value = sum(&buffer&.values).value
        \\}
        \\
        \\main := () -> () {
        \\    buffer ::= Buffer#(.n = Shape#(Int32).Count)((20, 22))
        \\    if read_buffer(&buffer).value != 42 { abort }
        \\}
    , null, "no conformance for the projected participant tuple", false);
}

test "contract diagnostic 89X_constant_projection_constructor_negative_dimension" {
    try checkSource("89X_constant_projection_constructor_negative_dimension",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = -1)
        \\
        \\Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))
        \\
        \\sum := (.values: &Array#(.n = 2, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\read_buffer := (.buffer: &Buffer#(.n = 2)) -> (.value: Int32) {
        \\    value = sum(&buffer&.values).value
        \\}
        \\
        \\main := () -> () {
        \\    buffer ::= Buffer#(.n = Shape#(Cell).Count)((20, 22))
        \\    if read_buffer(&buffer).value != 42 { abort }
        \\}
    , null, "array length must be non-negative", false);
}

test "contract diagnostic 90X_constant_projection_constructor_overflow" {
    try checkSource("90X_constant_projection_constructor_overflow",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\Buffer := #(.n: Int) (.values: Array#(.n = n, .t: Int32))
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\read_buffer := (.buffer: &Buffer#(.n = Shape#(Cell).Count)) -> (.value: Int32) {
        \\    value = sum(&buffer&.values).value
        \\}
        \\
        \\main := () -> () {
        \\    buffer ::= Buffer#(.n = Shape#(Cell).Count + 9223372036854775807)((20, 22))
        \\    if read_buffer(&buffer).value != 42 { abort }
        \\}
    , null, "compile-time integer arithmetic overflow", false);
}

test "contract diagnostic 91X_constant_projection_concrete_function_division_by_zero" {
    try checkSource("91X_constant_projection_concrete_function_division_by_zero",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\take := #(.n: Int) (.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\forward := #(.T: Type) (.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (
        \\    .value : Int32
        \\) { value = take#(.n = Shape#(T).Count)(values).value }
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if take#(.n = Shape#(Cell).Count / 0)(&values).value != 42 { abort }
        \\}
    , null, "division by zero in compile-time expression", false);
}

test "contract diagnostic 94X_constant_projection_concrete_kind_mismatch" {
    try checkSource("94X_constant_projection_concrete_kind_mismatch",
        \\Shape#(.Input: Type): Contract = (
        \\    .Element : Type
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Element: Type = Int32)
        \\
        \\first := #(.n: Int) (.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) {
        \\    value = values&[0]
        \\}
        \\
        \\main := () -> () {
        \\    values ::= (42, 0)
        \\    first#(.n = Shape#(Cell).Element) (&values)
        \\}
    , null, "compile-time argument kind does not match its parameter", false);
}

test "contract diagnostic 95X_constant_projection_concrete_unknown_participant" {
    try checkSource("95X_constant_projection_concrete_unknown_participant",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\take := #(.n: Int) (.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\forward := #(.T: Type) (.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (
        \\    .value : Int32
        \\) { value = take#(.n = Shape#(T).Count)(values).value }
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if take#(.n = Shape#(Unknown).Count)(&values).value != 42 { abort }
        \\}
    , null, "unknown or inaccessible type or contract in compile-time call arguments", false);
}

test "contract diagnostic 96X_constant_projection_concrete_unknown_contract" {
    try checkSource("96X_constant_projection_concrete_unknown_contract",
        \\Shape#(.Input: Type): Contract = (
        \\    .Count : Int
        \\)
        \\
        \\Cell: Type = ()
        \\
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\
        \\sum := (.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\take := #(.n: Int) (.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) {
        \\    value = [values&[0] + values&[1]]
        \\}
        \\
        \\forward := #(.T: Type) (.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (
        \\    .value : Int32
        \\) { value = take#(.n = Shape#(T).Count)(values).value }
        \\
        \\main := () -> () {
        \\    values ::= (20, 22)
        \\    if take#(.n = Unknown#(Cell).Count)(&values).value != 42 { abort }
        \\}
    , null, "unknown or inaccessible type or contract in compile-time call arguments", false);
}

test "contract diagnostic 99X_unary_reserved_self_parameter" {
    try checkSource("99X_unary_reserved_self_parameter",
        \\Broken: Contract = (
        \\    .Self : Type
        \\)
        \\
        \\main := () -> () {}
    , null, "associated contract members cannot be named Self", false);
}

test "contract diagnostic 103X_body_member_missing_type" {
    try checkSyntaxSource("103X_body_member_missing_type",
        \\Product #(.Input: Type ): Contract = (
        \\    .Result
        \\)
        \\main := () -> () {}
    , "associated contract members require a type declaration");
}

test "contract diagnostic 104X_body_member_default" {
    try checkSyntaxSource("104X_body_member_default",
        \\Product #(.Input: Type ): Contract = (
        \\    .Count : Int = 2
        \\)
        \\main := () -> () {}
    , "associated contract members are supplied by implement");
}

test "contract diagnostic 170X_unqualified_conformance_ambiguity" {
    try checkSourceWithout("170X_unqualified_conformance_ambiguity",
        \\Pair#(.Left: Type, .Right: Type): Contract = (
        \\    .combine : (.left: Left, .right: Right) -> (.result: Int32)
        \\)
        \\
        \\implement#(.T: Type) Pair#(T, Int32) (
        \\    .combine = (.left: T, .right: Int32) -> (.result: Int32) { result = 1 }
        \\)
        \\
        \\implement#(.T: Type) Pair#(Int32, T) (
        \\    .combine = (.left: Int32, .right: T) -> (.result: Int32) { result = 2 }
        \\)
        \\
        \\main := () -> () {
        \\    left: Int32 = 1
        \\    right: Int32 = 2
        \\    combine(left, right)
        \\}
    , "ambiguous maximal patterns", "no function named");
}

test "contract diagnostic 174X_selected_associated_constraint_mismatch" {
    try checkSourceWithout("174X_selected_associated_constraint_mismatch",
        \\Source#(.Provider: Type): Contract = (.Item: Type)
        \\
        \\Cell: Type = ()
        \\
        \\implement Source#(Cell) (.Item: Type = Int32)
        \\
        \\consume := #(.T: Type: Source#(.Provider: T, .Item: UInt8)) (.source: &T) -> () {}
        \\
        \\main := () -> () {
        \\    cell ::= Cell()
        \\    consume(&cell)
        \\}
    , "does not satisfy contract constraint 'Source'", "failed without a diagnostic");
}

test "contract diagnostic 176X_missing_contract_dependency" {
    try checkSourceWithout("176X_missing_contract_dependency",
        \\Readable #(.T: Type ): Contract = ()
        \\Writable #(.T: Type ): Contract = (Readable #( T ))
        \\Cell: Type = ()
        \\implement Writable #( Cell ) ()
        \\main := () -> () {}
    , "a required contract dependency is not satisfied", "failed without a diagnostic");
}

test "contract diagnostic 179X_generic_alias_output_inference" {
    try checkSourceWithout("179X_generic_alias_output_inference",
        \\Factory#(.Source: Type): Contract = (
        \\    .Result : Type
        \\    .make   : (.source: Source) -> (.result: Result)
        \\)
        \\
        \\make_value := #(.T: Type) (.source: Int32) -> (.result: T) { result = source }
        \\
        \\implement Factory#(Int32) (
        \\    .Result : Type = Int32
        \\    .make   = make_value
        \\)
        \\
        \\main := () -> () {}
    , "parameters must be inferred from the selected input signature", "failed without a diagnostic");
}

test "contract diagnostic 180X_generic_alias_result_mismatch" {
    try checkSourceWithout("180X_generic_alias_result_mismatch",
        \\Copy#(.T: Type): Contract = (
        \\    .Result : Type
        \\    .copy   : (.source: T) -> (.result: Result)
        \\)
        \\
        \\copy_value := #(.T: Type) (.source: T) -> (.result: T) { result = source }
        \\
        \\implement Copy#(Int32) (
        \\    .Result : Type = UInt8
        \\    .copy   = copy_value
        \\)
        \\
        \\main := () -> () {}
    , "operation returns an incompatible associated result", "failed without a diagnostic");
}

test "contract diagnostic 181X_dormant_equivalent_implementations" {
    try checkSourceWithout("181X_dormant_equivalent_implementations",
        \\Copy#(.T: Type): Contract = (.copy: (.source: T) -> (.result: T))
        \\
        \\implement#(.T: Type) Copy#(T) (
        \\    .copy = (.source: T) -> (.result: T) { result = source }
        \\)
        \\
        \\implement#(.U: Type) Copy#(U) (
        \\    .copy = (.source: U) -> (.result: U) { result = source }
        \\)
        \\
        \\main := () -> () {}
    , "equivalent implementation participant patterns are not allowed", "failed without a diagnostic");
}

test "contract diagnostic 184X_generic_alias_unsatisfied_bound" {
    try checkSourceWithout("184X_generic_alias_unsatisfied_bound",
        \\Supported#(.T: Type): Contract = ()
        \\
        \\Copy#(.T: Type): Contract = (.copy: (.source: T) -> (.result: T))
        \\
        \\copy_value := #(.T: Type: Supported#(T)) (.source: T) -> (.result: T) { result = source }
        \\
        \\implement Copy#(Int32) (.copy = copy_value)
        \\
        \\main := () -> () {}
    , "does not satisfy the generic operation alias bounds", "failed without a diagnostic");
}

test "contract diagnostic 229X_nominal_pattern_repeated_type" {
    try checkSourceWithout("229X_nominal_pattern_repeated_type",
        \\Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)
        \\
        \\Inspect#(.Args: Type): Contract = (.inspect: (.args: Args) -> ())
        \\
        \\implement#(.T: Type) Inspect#(Pair#(T, T)) (
        \\    .inspect = (.args: Pair#(T, T)) -> () {}
        \\)
        \\
        \\main := () -> () {
        \\    matching :: Pair#(Int32, Int32) = (.left = 1, .right = 2)
        \\    Inspect#(Pair#(Int32, Int32)).inspect(matching)
        \\    mismatched :: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
        \\    Inspect#(Pair#(Int32, UInt8)).inspect(mismatched)
        \\}
    , "no conformance for the qualified operation's participants", "failed without a diagnostic");
}

test "contract diagnostic 230X_nominal_pattern_ambiguous" {
    try checkSourceWithout("230X_nominal_pattern_ambiguous",
        \\Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)
        \\
        \\Inspect#(.Args: Type): Contract = (.inspect: (.args: Args) -> ())
        \\
        \\implement#(.T: Type) Inspect#(Pair#(Int32, T)) (
        \\    .inspect = (.args: Pair#(Int32, T)) -> () {}
        \\)
        \\
        \\implement#(.T: Type) Inspect#(Pair#(T, UInt8)) (
        \\    .inspect = (.args: Pair#(T, UInt8)) -> () {}
        \\)
        \\
        \\main := () -> () {
        \\    args :: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
        \\    Inspect#(Pair#(Int32, UInt8)).inspect(args)
        \\}
    , "ambiguous maximal patterns", "failed without a diagnostic");
}

test "contract diagnostic 255X_generic_unknown_argument" {
    try checkSourceWithout("255X_generic_unknown_argument",
        \\identity := #(.T: Type) (.value: T) -> (.result: T) { result = ~value }
        \\
        \\main := () -> () {
        \\    source: Int8 = 7
        \\    value ::= identity#(.Destination: Int64)(source)
        \\}
    , "unknown compile-time argument in call to 'identity'", "failed without a diagnostic");
}

test "contract diagnostic 284X_operation_alias_dependency_diagnostic" {
    try checkSourceWithout("284X_operation_alias_dependency_diagnostic",
        \\Required#(.Value: Type): Contract = (
        \\    .perform : (.value: Value) -> (.result: Int32)
        \\)
        \\
        \\Consumer#(.Value: Type): Contract = (
        \\    .run : (.value: Value) -> (.result: Int32)
        \\)
        \\
        \\forward := #(.Value: Type) (.value: Value) -> (.result: Int32) {
        \\    result = Required#(Value).perform(.value = value)
        \\}
        \\
        \\implement Consumer#(Int32) (
        \\    .run = forward
        \\)
        \\
        \\main := () -> () {
        \\    result ::= Consumer#(Int32).run(.value = 42)
        \\}
    , "invalid conformance for contract 'Required'", "the generic operation alias body could not be specialized");
}
