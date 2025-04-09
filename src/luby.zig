const std = @import("std");

sum: usize = 1,
value: usize = 1,

pub const init: @This() = .{};

pub fn next(self: *@This()) usize {
    const trailing = @ctz(self.sum);
    const out = self.value;

    if (trailing + 1 == self.value) {
        self.value = 1;
        self.sum += 1;
    } else {
        self.value += 1;
    }

    return @as(usize, 1) << @intCast(out - 1);
}
