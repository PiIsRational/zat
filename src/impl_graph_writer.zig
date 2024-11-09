const std = @import("std");
const SatInstance = @import("sat_instance.zig").SatInstance;
const Conflict = @import("impl.zig").Conflict;

instance: SatInstance,
conflict: Conflict,

const ImplGraphWriter = @This();

pub fn init(instance: SatInstance, conflict: Conflict) ImplGraphWriter {
    return .{ .instance = instance, .conflict = conflict };
}

pub fn format(
    self: ImplGraphWriter,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    self.instance.debugSettingOrder();
    var iter = std.mem.reverseIterator(self.instance.setting_order.items);
    try writer.print("digraph ImplGraph {{\n", .{});
    try writer.print("node [shape = doublecircle];", .{});

    for (self.instance.setting_order.items) |elem| {
        const reason = self.instance.variables.getReason(elem);
        const variable = self.instance.variables.getVar(elem);
        switch (reason.*) {
            .unary => try writer.print(" {s}{d}", .{ variable, elem + 1 }),
            else => continue,
        }
    }

    try writer.print(";\nnode [shape = circle];\n", .{});

    switch (self.conflict) {
        .binary => |bin| {
            try writer.print("{s} -> ⊥\n", .{bin[0].negated()});
            try writer.print("{s} -> ⊥\n", .{bin[1].negated()});
        },
        .other => |clause| for (clause.getLiterals(self.instance.clauses)) |lit| {
            try writer.print("{s} -> ⊥\n", .{lit.negated()});
        },
    }

    while (iter.next()) |elem| {
        const reason = self.instance.variables.getReason(elem);
        const variable = self.instance.variables.getVar(elem);
        switch (reason.*) {
            .binary => |literal| try writer.print(
                "{s} -> {s}{d}\n",
                .{ literal.negated(), variable, elem + 1 },
            ),
            .other => |clause| for (clause.getLiterals(self.instance.clauses)) |lit| {
                if (@as(usize, @intCast(lit.variable)) == elem and
                    lit.is_negated == variable.isFalse())
                {
                    continue;
                }

                try writer.print(
                    "{s} -> {s}{d}\n",
                    .{ lit.negated(), variable, elem + 1 },
                );
            },
            else => {},
        }
    }
    try writer.print("}}\n", .{});
}
