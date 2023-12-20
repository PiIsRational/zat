const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;

const BinClauses = struct {
    allocator: Allocator,
    impls: []std.ArrayList(Literal),
    len: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, variables: usize) !Self {
        var impls = try allocator.alloc(std.ArrayList(Literal), 2 * variables);

        for (impls) |*impl| {
            impl = std.ArrayList(Literal).init(allocator);
        }

        return BinClauses{
            .allocator = allocator,
        };
    }

    /// add a binary clause
    pub fn addBinary(self: Self, first: Literal, second: Literal) void {
        // because of the clause (first | second) we have first -> !second and second -> !first
        self.impls[first.toIndex()].append(second.negated());
        self.impls[second.toIndex()].append(first.negated());
    }
};
