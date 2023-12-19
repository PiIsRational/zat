const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;

const BinClauses = struct {
    allocator: Allocator,
    impls: []std.ArrayList(Literal),
    len: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, variables: usize) !Self {
        var impls = try allocator.alloc(std.ArrayList(Literal), variables);

        for (impls) |*impl| {
            impl = std.ArrayList(Literal).init(allocator);
        }

        return BinClauses{
            .allocator = allocator,
        };
    }

    pub fn addBinary(self: Self, first: Literal, second: Literal) void {
        _ = second;
        _ = first;
        _ = self;
    }
};
