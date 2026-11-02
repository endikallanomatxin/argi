const checkSyntaxSource = @import("source_test_support.zig").checkSyntaxSource;
const checkSource = @import("source_test_support.zig").checkSource;

test "basics/50X_undeclared_assignment" {
    try checkSource("50X_undeclared_assignment",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    value = 1
        \\}
    , "value = 1", "cannot assign to undeclared binding 'value'; declare it first with ':=' or '::='", true);
}

test "basics/51X_array_outer_length" {
    try checkSource("51X_array_outer_length",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    data: [3][3]Int32 = (
        \\        (1, 2),
        \\        (3, 4)
        \\    )
        \\}
    , null, "array initializer has 2 elements; expected 3", false);
}

test "basics/52X_array_inner_length" {
    try checkSource("52X_array_inner_length",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    data: [2][3]Int32 = (
        \\        (1, 2),
        \\        (3, 4)
        \\    )
        \\}
    , null, "array initializer has 2 elements; expected 3", false);
}

test "basics/53X_array_reference_shape" {
    try checkSource("53X_array_reference_shape",
        \\MatrixView := (.data_p: &[2][2]Int32)
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    data: [3][3]Int32 = (
        \\        (1, 2, 3),
        \\        (4, 5, 6),
        \\        (7, 8, 9)
        \\    )
        \\    matrix: MatrixView = (.data_p = &data)
        \\}
    , null, "array value has type '&[3][3]Int32'; expected '&[2][2]Int32'", false);
}

test "functions/21X_assume_no_propagation" {
    try checkSource("21X_assume_no_propagation",
        \\take := (.number: Int32) -> () {}
        \\
        \\child := () -> () { take() }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    assume number :: Int32 = 42
        \\    child()
        \\}
    , null, "call to 'take' is missing required argument '.number'", false);
}

test "functions/22X_assume_incompatible_default" {
    try checkSource("22X_assume_incompatible_default",
        \\take := (.number: Int32 = 42) -> () {}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    assume number :: Bool = true
        \\    take()
        \\}
    , null, "no function named 'take' accepts arguments", false);
}

test "functions/23X_assume_unknown_variable" {
    try checkSource("23X_assume_unknown_variable",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    assume missing
        \\}
    , null, "assume requires an existing variable; 'missing' is not declared in this scope", false);
}

test "functions/26X_assume_scope_does_not_escape" {
    try checkSource("26X_assume_scope_does_not_escape",
        \\take := (.number: Int32) -> () {}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    number :: Int32 = 42
        \\    if true { assume number }
        \\    take()
        \\}
    , null, "call to 'take' is missing required argument '.number'", false);
}

test "basics/25X_numeric_binding_type" {
    try checkSource("basics_25X_numeric_binding_type",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    source :: UInt8 = 7
        \\    destination :: UInt32 = source
        \\}
    , null, "cannot assign numeric value of type", false);
}

test "basics/26X_numeric_assignment_type" {
    try checkSource("basics_26X_numeric_assignment_type",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    source :: UInt32 = 7
        \\    destination :: UInt8 = 0
        \\    destination = source
        \\}
    , null, "cannot assign numeric value of type", false);
}

test "basics/27X_numeric_pointer_assignment_type" {
    try checkSource("basics_27X_numeric_pointer_assignment_type",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    source :: UInt8 = 7
        \\    destination :: UInt64 = 0
        \\    pointer ::= $&destination
        \\    pointer&= source
        \\}
    , null, "cannot assign numeric value of type", false);
}

test "basics/28X_numeric_signedness_assignment" {
    try checkSource("basics_28X_numeric_signedness_assignment",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    source :: Int32 = 7
        \\    destination :: UInt32 = source
        \\}
    , null, "cannot assign numeric value of type", false);
}

test "basics/29X_numeric_float_assignment" {
    try checkSource("basics_29X_numeric_float_assignment",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    source :: Float32 = 1.5
        \\    destination :: Float64 = source
        \\}
    , null, "cannot assign numeric value of type", false);
}

test "basics/48X_numeric_record_field" {
    try checkSource("basics_48X_numeric_record_field",
        \\Values := (.wide: Float64)
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    narrow :: Float32 = 3.5
        \\    values: Values = (.wide = narrow)
        \\}
    , null, "cannot assign numeric value of type", false);
}

test "basics/63X_implicit_integer_widening" {
    try checkSource("basics_63X_implicit_integer_widening",
        \\main := () -> (.status_code: Int32) {
        \\    small: Int8 = 1
        \\    wide: Int64 = small
        \\    status_code = 0
        \\}
    , null, "implicit numeric conversion is not supported", false);
}

test "basics/69X_typed_array_store" {
    try checkSource("basics_69X_typed_array_store",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    bytes: [2]UInt8 = (0, 0)
        \\    value: Int32 = 45
        \\    bytes[0] = value
        \\}
    , null, "implicit numeric conversion is not supported", false);
}

test "basics/24X_abort_is_not_a_call" {
    try checkSyntaxSource("basics_24X_abort_is_not_a_call",
        \\main := () -> (.status_code: Int32) {
        \\    abort ()
        \\    status_code = 0
        \\}
    , "abort");
}

test "basics/59X_empty_expression_grouping" {
    try checkSyntaxSource("basics_59X_empty_expression_grouping",
        \\main := () -> (.status_code: Int32) {
        \\    status_code = []
        \\}
    , "expression grouping requires exactly one expression");
}

test "basics/60X_multiple_expression_grouping" {
    try checkSyntaxSource("basics_60X_multiple_expression_grouping",
        \\main := () -> (.status_code: Int32) {
        \\    status_code = [1, 2]
        \\}
    , "expected ']' after grouped expression");
}

test "basics/73X_multiline_operation_missing_operand" {
    try checkSyntaxSource("basics_73X_multiline_operation_missing_operand",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    value ::= [1 +
        \\    ]
        \\}
    , "expected an expression after operator '+'");
}

test "basics/74X_leading_operator_requires_group" {
    try checkSyntaxSource("basics_74X_leading_operator_requires_group",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    value ::= 1
        \\    +2
        \\}
    , "a leading operator requires scalar grouping");
}

test "functions/24X_assume_initializer" {
    try checkSyntaxSource("functions_24X_assume_initializer",
        \\main := () -> (.status_code: Int32 = 0) {
        \\    assume number = 42
        \\}
    , "use ':=' to declare an assumed variable, or 'assume name' for an existing variable");
}

test "functions/35X_nested_pipe_requires_outer_placeholder" {
    try checkSyntaxSource("functions_35X_nested_pipe_requires_outer_placeholder",
        \\identity := (.value: Int32) -> (.result: Int32) { result = value }
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    result ::= 1 | identity(.value = 2 | identity(.value = _))
        \\}
    , "pipe right-hand side must use at least one argument placeholder");
}
