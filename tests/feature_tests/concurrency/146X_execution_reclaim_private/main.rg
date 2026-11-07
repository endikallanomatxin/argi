main := () -> () {
    receipt: _ExecutionReceipt = (._marker = 1)
    _execution_complete(.receipt = $&receipt)
}
