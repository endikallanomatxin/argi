-- Struct type declaration
MyType : Type = (
    .x: Int32
    .y: Int32
)

main () -> (.status_code: Int32) := {
    -- Struct type declaration and initialization
    my_var: MyType = (.x = 1, .y = 2)

    status_code = 0
}
