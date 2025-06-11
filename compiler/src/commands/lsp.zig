const std = @import("std");
const json = std.json;
const allocator: *std.mem.Allocator = std.heap.page_allocator;
const File = std.fs.File;
const ReadError = std.fs.ReadError;

const LSPError = error{
    InvalidJson,
};

pub fn start() !void {}
