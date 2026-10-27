main := () -> (.status_code: Int32) {
    runtime :: Int32 = 42
    status_code = #run () -> (.answer: Int32) {
        #if true { answer = runtime } #else { answer = missing_value }
    }
}
