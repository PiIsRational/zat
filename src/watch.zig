const std = @import("std");
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const Literal = @import("literal.zig").Literal;
const ClauseDb = @import("clause db.zig").ClauseDb;

pub const WatchList = struct {
    watches: []std.ArrayList(Watch),
    initialized: bool,
    allocator: Allocator,

    const Self = @This();

    /// init creates a new watchlist and initializes it
    ///
    /// the initialization does go through each clause and supposes that no variable in the clause is assigned
    pub fn init(variables: usize, allocator: Allocator) !Self {
        var watches = try allocator.alloc(std.ArrayList(Watch), variables * 2);
        return WatchList{
            .initialized = false,
            .watches = watches,
            .allocator = allocator,
        };
    }

    pub fn setUp(self: *Self, db: *ClauseDb) void {
        if (self.initialized) {
            return;
        }

        // iterate through each clause and check if it is garbage or no
        for (db.*.items) |clause| {
            if (clause.isGarbage()) {
                continue;
            }

            self.appendClause(
                clause,
                [_]Literal{
                    clause.getLiterals()[0],
                    clause.getLiterals()[1],
                },
            );
        }

        self.initialized = true;
    }

    /// appends a clause to the watch list
    ///
    /// The two given literals should be different variables and included in the clause.
    /// Additionally they should not be negated.
    pub fn append(self: *Self, clause: Clause, literals: [2]Literal) !void {
        for (literals, 0..) |literal, i| {
            try self.addWatch(literal, Watch{
                .other = literals[i ^ 1],
                .clause = clause,
            });
        }
    }

    pub fn deinit(self: *Self) void {
        self.initialized = false;
        for (self.watches) |watch| {
            watch.deinit();
        }

        self.allocator.free(self.watches);
    }

    /// move a watch from one Literal to an other
    fn move(self: *Self, watch: *Watch, from: Literal, to: Literal) void {
        self.addWatch(to, watch.*);
        self.remove(watch, from);
    }

    /// remove a watch from the watchlist of a given literal
    fn remove(self: *Self, watch: *Watch, literal: Literal) void {
        watch.* = self.watches[literal.toIndex()].pop();
    }

    /// add a watch to the watchlist of a literal
    fn addWatch(self: *Self, literal: Literal, watch: Watch) !void {
        try self.watches[literal.variable].append(watch);
    }
};

const Watch = struct {
    other: Literal,
    clause: Clause,

    const Self = @This();
};
