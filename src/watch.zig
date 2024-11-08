const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const Literal = @import("literal.zig").Literal;
const ClauseDb = @import("clause_db.zig").ClauseDb;
const SatInstance = @import("sat_instance.zig").SatInstance;
const Result = @import("result.zig").Result;
const SatResult = @import("result.zig").SatResult;
const ClauseRef = @import("clause.zig").ClauseRef;

pub const WatchList = struct {
    watches: []std.ArrayList(Watch),
    initialized: bool,
    allocator: Allocator,
    db: *ClauseDb,

    const Self = @This();

    /// init creates a new watchlist and initializes it
    ///
    /// the initialization does go through each clause and
    /// supposes that no variable in the clause is assigned
    pub fn init(variables: usize, allocator: Allocator) !Self {
        const watches = try allocator.alloc(std.ArrayList(Watch), variables * 2);

        for (watches) |*watchlist| {
            watchlist.* = std.ArrayList(Watch).init(allocator);
        }

        return .{
            .initialized = false,
            .watches = watches,
            .allocator = allocator,
            .db = undefined,
        };
    }

    pub fn setUp(self: *Self, db: *ClauseDb) !void {
        self.db = db;

        if (self.initialized) return;
        self.initialized = true;

        // iterate through each clause and check if it is garbage or no
        for (self.db.clauses.items) |clause| {
            assert(!clause.isGarbage(self.db));

            const lits = clause.getLiterals(self.db);
            assert(!lits[0].eql(lits[1]));
            try self.append(clause, .{ lits[0], lits[1] });
        }
    }

    /// sets `literal` to true and checks for unit clauses
    ///
    /// iff there was an error returns true
    pub fn set(self: *Self, literal: Literal, instance: *SatInstance) !bool {
        const to_update = literal.negated();
        const watch_list = &self.watches[to_update.toIndex()].items;

        // cannot convert this to a for loop, as the watchlist length is updated during iteration
        var i: usize = 0;
        while (i < watch_list.*.len) {
            var watch = &watch_list.*[i];

            switch (try watch.set(to_update, instance)) {
                .OK => |value| if (value) |new_literal| {
                    // after setting the watch the new literal should be the first of the clause
                    assert(watch.clause.getLiterals(&instance.clauses)[1].eql(new_literal));

                    // the returns value is not null, so we need to move the watch
                    try self.move(watch, to_update, new_literal);
                } else {
                    i += 1;
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
        if (!self.initialized) {
            return;
        }

        for (literals, 0..) |literal, i| {
            assert(!literal.is_garbage);
            assert(clause.getLiterals(self.db)[i].eql(literal) or
                clause.getLiterals(self.db)[i ^ 1].eql(literal));

            try self.addWatch(literal, Watch{
                .blocking = literals[i ^ 1],
                .clause = clause,
            });
        }
    }

    pub fn isWatched(self: Self, clause: Clause, literal: Literal) bool {
        for (self.watches[literal.toIndex()].items) |w| {
            if (w.clause.index == clause.index) return true;
        }

        return false;
    }

    /// the destructor of the struct
    pub fn deinit(self: *Self) void {
        self.initialized = false;
        for (self.watches) |watch| watch.deinit();
        self.allocator.free(self.watches);
    }

    /// move `watch` from `from` to `to`
    fn move(self: *Self, watch: *Watch, from: Literal, to: Literal) !void {
        assert(!to.eql(from));
        try self.addWatch(to, watch.*);
        self.remove(watch, from);
    }

    /// remove a watch from the watchlist of a given literal
    fn remove(self: *Self, watch: *Watch, literal: Literal) void {
        // the watch should be in the watchlist of `literal`
        assert(@intFromPtr(watch) >= @intFromPtr(&self.watches[literal.toIndex()].items[0]));
        assert(@intFromPtr(watch) <=
            @intFromPtr(&self.watches[literal.toIndex()].items[self.watches[literal.toIndex()].items.len - 1]));

        watch.* = self.watches[literal.toIndex()].pop();
    }

    /// add a watch to the watchlist of a literal
    fn addWatch(self: *Self, literal: Literal, watch: Watch) !void {
        assert(watch.blocking.toIndex() < self.watches.len);

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
        assert(!self.blocking.is_garbage);
        assert(self.blocking.variable < instance.variables.impls.len);

        // there are 4 cases:
        //
        // - the clause is assigned
        // - the clause has more than 2 unassinged literals
        // - the clause has 2 unassigned literals
        // - the clause has only false variables (conflict)

        // first check that the blocking literal is assigned true
        // because if it is the case the clause is already satisfied
        if (instance.isTrue(self.blocking)) return .{ .OK = null };

        var literals = self.clause.getLitsMut(&instance.clauses);

        // if the current watched literal is the first, switch it with the second one
        // as it will not be watched anymore
        var other_watch = literals[0];
        if (literal.eql(other_watch)) {
            std.mem.swap(Literal, &literals[0], &literals[1]);
            other_watch = literals[0];
        }

        assert(instance.watch.isWatched(self.clause, other_watch));
        assert(instance.watch.isWatched(self.clause, literal));

        // check that the other watch is allowed to be false
        assert(!instance.isFalse(other_watch) or
            self.clause.fullyAssigned(instance) or
            instance.isLastChoice(literal) or
            instance.isUnitAssignement(literal));
        assert(literals[1].eql(literal));

        // check that the other watch is true, because if it is, we are done as the clause
        // is satisfied. we check that the blocking literal is not the other watch as the
        // blocking iteral is already known to be untrue.
        if (!self.blocking.eql(other_watch) and instance.isTrue(other_watch)) {
            return .{ .OK = null };
        }

        // this watch is not needed anymore so we can update it for further needs
        // the blocking literal is set to be the other watch, as it is already known to be untrue
        self.blocking = other_watch;

        // go through the other literals to find a new watch
        for (literals[2..]) |*lit| {
            // if it is not a false literal we can watch it
            if (!instance.isFalse(lit.*)) {
                assert(!lit.eql(literal));
                const new_watch = lit.*;

                // reorder the literals and return it because we do need to
                // move this watch to the new watchlist
                std.mem.swap(Literal, lit, &literals[1]);

                return .{ .OK = new_watch };
            }
        }

        // check that the other watched literal is not negated
        // if it is false we have a conflict
        if (instance.isFalse(other_watch)) return .FAIL;

        // if we did not find a second watch we got a unit clause
        try instance.addUnit(.{ .to_set = other_watch, .reason = self.clause });

        // no need to move this watch
        return .{ .OK = null };
    }
};

pub const UnitSetting = struct {
    to_set: Literal,
    reason: Clause,
};
