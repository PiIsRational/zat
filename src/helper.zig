const std = @import("std");

pub fn print_list(list: std.ArrayList(u8)) !void {
    const stdout = std.io.getStdOut().writer();
    for (list.items) |item| {
        try stdout.print("{c}", .{item});
    }
    try stdout.print("\n", .{});
}
