//! Standalone diagnostics from feature categories.
const checkSource = @import("source_test_support.zig").checkSource;

const checkSyntaxSource = @import("source_test_support.zig").checkSyntaxSource;

test "collections/46X_fixed_array_constant_index_out_of_bounds" {
    try checkSource("collections_46X_fixed_array_constant_index_out_of_bounds",
        \\main := () -> (.status_code: Int32) {
        \\    values :: [2]Int32 = (10, 20)
        \\    value ::= values[2]
        \\    status_code = value
        \\}
    , null, "array index 2 is out of bounds for length 2", false);
}

test "errors/103X_defer_break" {
    try checkSource("errors_103X_defer_break",
        \\main := () -> () { while true {
        \\        defer { break }
        \\        break
        \\    } }
    , null, "cannot exit an enclosing loop from a deferred action", false);
}

test "errors/104X_defer_generic_continue" {
    try checkSource("errors_104X_defer_generic_continue",
        \\finish := #(.t: Type) (.value: t) -> () { while true {
        \\        defer { continue }
        \\        break
        \\    } }
        \\
        \\main := () -> () { finish#(.t: Int32) (1) }
    , null, "cannot exit an enclosing loop from a deferred action", false);
}

test "errors/109X_report_return_block_non_errable" {
    try checkSource("errors_109X_report_return_block_non_errable",
        \\main := () -> (.status_code: Int32 = 0) { 7!!! { status_code = 1 } }
    , null, "handle expects an Errable value", false);
}

test "errors/84X_handle_non_errable" {
    try checkSource("errors_84X_handle_non_errable",
        \\main := () -> () {
        \\    number ::= 7 handle error, value { value = 0 }
        \\}
    , null, "handle expects an Errable value", false);
}

test "errors/87X_handle_arbitrary_choice" {
    try checkSource("errors_87X_handle_arbitrary_choice",
        \\..ok
        \\..error
        \\
        \\Fake: Type = (..ok Int32, ..error Int32)
        \\
        \\main := () -> () {
        \\    input: Fake = ..ok 7
        \\    result ::= input handle error, value { value = 0 }
        \\}
    , null, "handle expects an Errable value", false);
}

test "errors/91X_handle_without_result_non_errable" {
    try checkSource("errors_91X_handle_without_result_non_errable",
        \\main := () -> () { 7 handle error {} }
    , null, "handle expects an Errable value", false);
}

test "errors/94X_defer_return" {
    try checkSource("errors_94X_defer_return",
        \\main := () -> () { defer { return } }
    , null, "cannot return or propagate errors from a deferred action", false);
}

test "errors/95X_report_return_non_errable" {
    try checkSource("errors_95X_report_return_non_errable",
        \\main := () -> (.status_code: Int32 = 0) { value ::= 7!!! }
    , null, "handle expects an Errable value", false);
}

test "errors/98X_defer_generic_return" {
    try checkSource("errors_98X_defer_generic_return",
        \\finish := #(.t: Type) (.value: t) -> () { defer { return } }
        \\
        \\main := () -> () { finish#(.t: Int32) (1) }
    , null, "cannot return or propagate errors from a deferred action", false);
}

test "execution/108X_module_condition_nonboolean" {
    try checkSource("execution_108X_module_condition_nonboolean",
        \\choose := () -> (.value: Int32) { value = 42 }
        \\
        \\#if choose() {
        \\    main := () -> () {}
        \\}
    , null, "compile-time condition requires a Bool result", false);
}

test "execution/109X_module_condition_safety" {
    try checkSource("execution_109X_module_condition_safety",
        \\choose := () -> (.ok: Bool) {
        \\    vacant :: Bool
        \\    ok = vacant
        \\}
        \\
        \\#if choose() {
        \\    main := () -> () {}
        \\}
    , null, "deinitialized", false);
}

test "execution/65X_comptime_noninteger_argument" {
    try checkSource("execution_65X_comptime_noninteger_argument",
        \\compute := () -> (.result: Bool = true) {}
        \\
        \\result := #(.n: Int32) () -> (.value: Int32 = n) {}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    status_code = result#(.n = #run () -> (.value: Bool) { value = compute() })()
        \\}
    , null, "compile-time integer argument requires an integer result", false);
}

test "execution/70X_computed_nonboolean_condition" {
    try checkSource("execution_70X_computed_nonboolean_condition",
        \\number := () -> (.value: Int32 = 1) {}
        \\
        \\main := () -> () { #if number() {} }
    , null, "compile-time condition requires a Bool result", false);
}

test "execution/72X_computed_selected_branch" {
    try checkSource("execution_72X_computed_selected_branch",
        \\main := () -> () { #if true { does_not_exist() } }
    , null, "cannot materialize function body", false);
}

test "execution/76X_computed_condition_cycle" {
    try checkSource("execution_76X_computed_condition_cycle",
        \\recursive := () -> (.ok: Bool = false) {
        \\    #if recursive() { ok = true }
        \\}
        \\
        \\main := () -> () { #if recursive() {} }
    , null, "unresolved or cyclic semantic dependencies", false);
}

test "execution/78X_computed_discarded_binding" {
    try checkSource("execution_78X_computed_discarded_binding",
        \\unrelated := (.missing: Int32) -> () {}
        \\
        \\main := () -> (.status_code: Int32 = 0) {
        \\    #if false { missing := 42 }
        \\    status_code = missing
        \\}
    , null, "unknown name 'missing' in this scope", false);
}

test "text/85X_unicode_literal_multiple_scalars" {
    try checkSyntaxSource("text_85X_unicode_literal_multiple_scalars",
        \\main := () -> ()  {
        \\    value ::= 'é'
        \\}
    , "exactly one Unicode scalar");
}
