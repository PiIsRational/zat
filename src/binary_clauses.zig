const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;

pub const BinClauses = struct {
    allocator: Allocator,
    impls: []std.ArrayList(Literal),
    len: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, variables: usize) !Self {
        const impls = try allocator.alloc(std.ArrayList(Literal), 2 * variables);

        for (impls) |*impl| impl.* = std.ArrayList(Literal).init(allocator);

        return .{
            .allocator = allocator,
            .impls = impls,
            .len = 0,
        };
    }

    /// add a binary clause
    pub fn addBinary(self: *Self, first: Literal, second: Literal) !void {
        // because of the clause (first | second) we have !first -> second and !second -> first
        try self.impls[first.negated().toIndex()].append(second);
        try self.impls[second.negated().toIndex()].append(first);

        self.len += 1;
    }

    /// the destructor of the binary clauses
    pub fn deinit(self: *Self) void {
        for (self.impls) |*impl| impl.deinit();
        self.allocator.free(self.impls);
    }

    /// get the literals implied by a given literal
    pub fn getImplied(self: Self, literal: Literal) []const Literal {
        return self.impls[literal.toIndex()].items;
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        for (self.impls, 0..) |impls, i| {
            for (impls.items) |implicates| {
                try writer.print(" & ({s} -> {s})", .{ Literal.fromIndex(i), implicates });
            }
        }
    }
};
