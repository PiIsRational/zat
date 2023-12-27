const std = @import("std");
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const Literal = @import("literal.zig").Literal;
const ClauseDb = @import("clause db.zig").ClauseDb;
const SatInstance = @import("sat instance.zig").SatInstance;

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

    /// sets `literal` to true and checks for unit clauses
    pub fn set(self: *Self, literal: Literal, instance: *SatInstance) void {
        for (self.watches[literal.negated().toIndex()].items) |*watch| {
            if (watch.*.set(literal, instance)) |new_literal| {
                // the returns value is not null, so we need to move the watch
                self.move(watch, literal, new_literal);
            }
        }
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
    blocking: Literal,
    clause: *Clause,

    const Self = @This();

    /// updates the watch according to `literal` and updates `instance`
    ///
    /// if returns non null the literal to watch is the returns value
    fn set(self: *Self, literal: Literal, instance: *SatInstance) ?Literal {
        // there are 3 cases:
        //
        // - the clause is assigned
        // - the clause has more than 2 unassinged literals
        // - the clause has 2 unassigned literals

        // first check that the blocking literal is assigned true
        // because if it is the case the clause is already satisfied
        if (instance.isTrue(self.blocking)) {
            return false;
        }

        var literals = self.clause.getLiterals();

        // if the current watched literal is the first, switch it with the second one
        // as it will not be watched anymore
        var other_watch = self.clause.getLiterals()[0];
        if (literal == other_watch) {
            std.mem.swap(Literal, &literals[0], &literals[1]);
            other_watch = literals[0];
        }

        // this watch is not needed anymore so we can update it for further needs
        // the blocking literal is set to be the other watch, as it is already known
        self.blocking = other_watch;

        // check that the other watch is true, because of it is we are done as te clause
        // is satisfied. we check that the blocking literal is not the other watch as the
        // blocking iteral is already known to be untrue.
        if (self.blocking != other_watch and instance.isTrue(other_watch)) {
            return null;
        }

        // go through the other literals to find a new watch
        for (literals[2..]) |*lit| {
            // if it is not a false literal we can watch it
            if (!instance.isFalse(lit.*)) {
                // reorder the literals and return it because we do need to
                // move this watch to the new watchlist
                std.mem.swap(Literal, lit, &literals[1]);

                return lit.*;
            }
        }

        // check that the other watched literal is not negated
        // it should not be possible for it to be false
        std.debug.assert(!instance.isFalse(other_watch));

        // if we did not find a second watch we got a unit clause
        // the literal
        instance.units.append(other_watch);

        // no need to move this watch
        return null;
    }
};
