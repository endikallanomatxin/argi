choose := () -> (.value: Int32) { value = 42 }

#if choose() {
    main := () -> () {}
}
