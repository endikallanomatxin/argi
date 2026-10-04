same#(.t: Type)(.left: &t, .right: &t) -> () := {}
main() -> (.status_code: Int32 = 0) := {
    left: Int32 = 0
    right: Bool = false
    same(.left = &left, .right = &right)
}
