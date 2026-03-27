Box #(.t: Type) : Type = (
    .n: Int32
)

touch #(.t: Type) (.box: Box#(.t: t)) -> () := {
}

main () -> (.status_code: Int32) := {
    box : Box#(.t: Int32) = (.n = 0)
    touch#(.t: Int32)(.box = box)
    status_code = 0
}
