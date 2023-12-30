const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const Literal = @import("literal.zig").Literal;
const ClauseDb = @import("clause db.zig").ClauseDb;
const SatInstance = @import("sat instance.zig").SatInstance;
const Result = @import("result.zig").Result;

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

        for (watches) |*watchlist| {
            watchlist.* = std.ArrayList(Watch).init(allocator);
        }

        return WatchList{
            .initialized = false,
            .watches = watches,
            .allocator = allocator,
        };
    }

    pub fn setUp(self: *Self, db: *ClauseDb) !void {
        if (self.initialized) {
            return;
        }

        // iterate through each clause and check if it is garbage or no
        for (db.*.clauses.items) |clause| {
            if (clause.isGarbage(db)) {
                continue;
            }

            try self.append(
                clause,
                [_]Literal{
                    clause.getLiterals(db)[0],
                    clause.getLiterals(db)[1],
                },
            );
        }

        self.initialized = true;
    }

    /// sets `literal` to true and checks for unit clauses
    ///
    /// iff there was an error returns true
    pub fn set(self: *Self, literal: Literal, instance: *SatInstance) !bool {
        for (self.watches[literal.negated().toIndex()].items) |*watch| {
            switch (try watch.set(literal, instance)) {
                .OK => |value| if (value) |new_literal| {
                    // the returns value is not null, so we need to move the watch
                    try self.move(watch, literal, new_literal);
                },
                .FAIL => return true,
            }
        }

        return false;
    }

    /// appends a clause to the watch list
    ///
    /// The two given literals should be different variables and included in the clause.
    /// Additionally they should not be negated.
    pub fn append(self: *Self, clause: Clause, literals: [2]Literal) !void {
        for (literals, 0..) |literal, i| {
            try self.addWatch(literal, Watch{
                .blocking = literals[i ^ 1],
                .clause = clause,
            });
        }
    }

    /// the destructor of the struct
    pub fn deinit(self: *Self) void {
        self.initialized = false;
        for (self.watches) |watch| {
            watch.deinit();
        }

        self.allocator.free(self.watches);
    }

    /// move a watch from one Literal to an other
    fn move(self: *Self, watch: *Watch, from: Literal, to: Literal) !void {
        try self.addWatch(to, watch.*);
        self.remove(watch, from);
    }

    /// remove a watch from the watchlist of a given literal
    fn remove(self: *Self, watch: *Watch, literal: Literal) void {
        watch.* = self.watches[literal.toIndex()].pop();
    }

    /// add a watch to the watchlist of a literal
    fn addWatch(self: *Self, literal: Literal, watch: Watch) !void {
        try self.watches[literal.toIndex()].append(watch);
    }
};

const Watch = struct {
    blocking: Literal,
    clause: Clause,

    const Self = @This();

    /// updates the watch according to `literal` and updates `instance`
    ///
    /// if returns non null the literal to watch is the returns value
    fn set(self: *Self, literal: Literal, instance: *SatInstance) !Result(?Literal) {
        // there are 3 cases:
        //
        // - the clause is assigned
        // - the clause has more than 2 unassinged literals
        // - the clause has 2 unassigned literals

        // first check that the blocking literal is assigned true
        // because if it is the case the clause is already satisfied
        if (instance.isTrue(self.blocking)) {
            return Result(?Literal){ .OK = null };
        }

        var literals = self.clause.getLiterals(&instance.clauses);

        // if the current watched literal is the first, switch it with the second one
        // as it will not be watched anymore
        var other_watch = self.clause.getLiterals(&instance.clauses)[0];
        if (literal.eql(other_watch)) {
            std.mem.swap(Literal, &literals[0], &literals[1]);
            other_watch = literals[0];
        }

        // this watch is not needed anymore so we can update it for further needs
        // the blocking literal is set to be the other watch, as it is already known
        self.blocking = other_watch;

        // check that the other watch is true, because of it is we are done as te clause
        // is satisfied. we check that the blocking literal is not the other watch as the
        // blocking iteral is already known to be untrue.
        if (!self.blocking.eql(other_watch) and instance.isTrue(other_watch)) {
            return Result(?Literal){ .OK = null };
        }

        // go through the other literals to find a new watch
        for (literals[2..]) |*lit| {
            // if it is not a false literal we can watch it
            if (!instance.isFalse(lit.*)) {
                // reorder the literals and return it because we do need to
                // move this watch to the new watchlist
                std.mem.swap(Literal, lit, &literals[1]);

                return Result(?Literal){ .OK = lit.* };
            }
        }

        // check that the other watched literal is not negated
        // it should not be possible for it to be false
        if (instance.isFalse(other_watch)) {
            return Result(?Literal).FAIL;
        }

        // if we did not find a second watch we got a unit clause
        // the literal
        try instance.units.append(other_watch);

        // no need to move this watch
        return Result(?Literal){ .OK = null };
    }
};
