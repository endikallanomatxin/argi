dep := import("./dep")

main() -> (.status_code: Int32 = 0) := {
    named := dep.identity#(.t: Int32)(.value = 42)
    positional := dep.identity#(Int32)(.value = 43)
    inferred := dep.identity(.value = 44)
    box := dep.Box#(Int32)(.value = 45)
    if named != 42 or positional != 43 or inferred != 44 or box.value != 45 {
        status_code = 1
    }
}
