main := {
    value : Nullable#(.t: Int32) = ..some(.value = 5)

    for item in value {
        use item
    }
}
