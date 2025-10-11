pub fn containsIndex(list: []const u32, idx: u32) bool {
    for (list) |v| if (v == idx) return true;
    return false;
}
