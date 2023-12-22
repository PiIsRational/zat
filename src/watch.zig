const std = @import("std");
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const SatInstance = @import("sat instance.zig").SatInstance;
const Literal = @import("literal.zig").Literal;

pub const WatchList = struct {
    watches: []std.ArrayList(Watch),
    allocator: Allocator,

    const Self = @This();

    /// init creates a new watchlist and initializes it
    /// the initialization does go through each clause and supposes that no variable in the clause is assigned
    pub fn init(variables: usize, allocator: Allocator, instance: SatInstance) !Self {
        var watches = try allocator.alloc(std.ArrayList(Watch), variables * 2);
        var list = WatchList{
            .watches = watches,
            .allocator = allocator,
        };

        // iterate through each clause and check if it is garbage or no
        for (instance.clauses.items) |clause| {
            if (clause.isGarbage()) {
                continue;
            }

            list.appendClause(clause);
        }
    }

    pub fn appendClause(self: *Self, clause: Clause, literals: [2]Literal) void {
        for (literals, 0..1) |literal, i| {
            self.add_watch(literal, Watch{
                .other = literals[i ^ 1],
                .clause = clause,
            });
        }
    }

    fn add_watch(self: *Self, literal: Literal, watch: Watch) void {
        self.watches[literal.variable].append(watch);
    }
};

const Watch = struct {
    other: Literal,
    clause: Clause,

    const Self = @This();
};
