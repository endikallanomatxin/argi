main := {
    value : Errable#(.t: Int32, .e: Char) = ..ok(.value = 7)

    match value {
        ..none {
            return 0
        }
        ..ok(payload) {
            return payload
        }
        ..error(err) {
            use err
            return 0
        }
    }
}
