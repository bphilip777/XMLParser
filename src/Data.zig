const std = @import("std");
const Data = @This();

allo: std.mem.Allocator,
data: []const u8,

pub fn init(allo: std.mem.Allocator, filename: []const u8) !Data {
    const rfile = std.fs.cwd().openFile(filename, .{}) catch unreachable;
    defer rfile.close();

    const size: u32 = 4 * 1024 * 1024;
    const data = rfile.readToEndAlloc(allo, size) catch unreachable;

    return .{
        .allo = allo,
        .data = data,
    };
}

pub fn deinit(self: *const Data) void {
    self.allo.free(self.data);
}
