const Allocator = std.mem.Allocator;
const SatInstance = @import("sat instance.zig").SatInstance;
const Clause = @import("sat instance.zig").Clause;
const VarState = @import("sat instance.zig").Variable;
const Helper = @import("helper.zig");

const std = @import("std");
const fs = std.fs;
const BUFFER_SIZE = 10000;

pub const InstanceBuilder = struct {
    sat_type: SatData,
    clause_num: usize,
    allocator: Allocator,

    pub fn load_from_file(allocator: Allocator, path: []const u8) !SatInstance {
        const stdout = std.io.getStdOut().writer();
        var reader = try fs.cwd().openFile(path, .{});
        var buffer = try allocator.alloc(u8, BUFFER_SIZE);
        var characters = try reader.read(buffer);
        var index: usize = 0;
        var currline = std.ArrayList(u8).init(allocator);
        var self = InstanceBuilder{
            .allocator = allocator,
            .sat_type = undefined,
            .clause_num = 0,
        };

        var instance = SatInstance{
            .allocator = allocator,
            .clauses = std.ArrayList(Clause).init(allocator),
            .variables = try allocator.alloc(VarState, 0),
        };

        while (index < characters) {
            switch (buffer[index]) {
                '\n' => {
                    try self.parse_line(currline, &instance);
                    currline.clearRetainingCapacity();
                },
                else => {
                    try currline.append(buffer[index]);
                },
            }

            index += 1;
            if (index == BUFFER_SIZE) {
                index = 0;
                characters = try reader.read(buffer);
            }
        }

        if (self.clause_num <= self.sat_type.clause_count) {
            try self.parse_line(currline, &instance);
        }

        // wrong clause count
        if (self.clause_num != self.sat_type.clause_count) {
            try stdout.print("(ERROR) Illegal Clause Count!", .{});
            return ParseError.IllegalClauseCount;
        }

        try stdout.print("printing the clauses of the instance:\n", .{});
        for (instance.clauses.items, 0..) |clause, i| {
            const string = try clause.toString(self.allocator);
            try stdout.print("({s})", .{string});
            self.allocator.free(string);

            if (i == instance.clauses.items.len - 1) {
                try stdout.print("\n", .{});
            } else {
                try stdout.print(" & ", .{});
            }
        }

        return instance;
    }

    fn parse_line(self: *InstanceBuilder, line: std.ArrayList(u8), instance: *SatInstance) !void {
        const stdout = std.io.getStdOut().writer();
        switch (line.items[0]) {
            'c' => {},
            'p' => {
                try self.parse_p(line);
                instance.allocator.free(instance.variables);
                instance.variables = try instance.allocator.alloc(VarState, self.sat_type.variable_count);

                try stdout.print(
                    "c Parsed a SAT instance with {d} variables and {d} clauses.\n",
                    .{ self.sat_type.variable_count, self.sat_type.clause_count },
                );
            },
            else => try self.parse_clause(line, instance),
        }
    }

    fn parse_clause(self: *InstanceBuilder, line: std.ArrayList(u8), instance: *SatInstance) !void {
        var new_clause = Clause{
            .literals = std.ArrayList(i32).init(instance.allocator),
        };

        var parsing_num = false;
        var current_num: i32 = 1;
        for (line.items) |character| {
            if (parsing_num and is_whitespace(character)) {
                parsing_num = false;
                if (instance.*.variables.len < current_num) {
                    std.debug.print("found a disallowed: {d}\n", .{current_num});
                    return ParseError.NonExistingVariableRef;
                }

                if (current_num == 0) {
                    break;
                }

                try new_clause.literals.append(current_num);
                current_num = 1;
            }

            if (parsing_num) {
                if (!is_num(character)) {
                    std.debug.print("found a disallowed: ({c})\n", .{character});
                    return ParseError.NotaDigit;
                }

                current_num *= 10;
                current_num += @intCast(character - '0');
            }

            if (!parsing_num and (character == '-' or is_num(character))) {
                parsing_num = true;
                current_num = if (character == '-') -1 else @intCast(character - '0');
            }

            if (!parsing_num and !is_whitespace(character)) {
                std.debug.print("found a disallowed: {c}\n", .{character});
                return ParseError.UnexpectedCharacter;
            }
        }

        try instance.clauses.append(new_clause);
        self.clause_num += 1;
    }

    fn is_whitespace(character: u8) bool {
        return character == ' ' or character == '\t' or character == '\r';
    }

    fn is_num(character: u8) bool {
        return character >= '0' and character <= '9';
    }

    fn parse_p(self: *InstanceBuilder, line: std.ArrayList(u8)) !void {
        if (!std.mem.eql(u8, line.items[0..6], "p cnf ")) {
            return ParseError.IllegalHeader;
        }

        var var_count: usize = undefined;
        var clause_count: usize = undefined;
        var space_place: usize = undefined;
        var found_space = false;
        var end: usize = undefined;
        if (line.items[line.items.len - 1] == '\r') {
            end = line.items.len - 1;
        } else {
            end = line.items.len;
        }

        for (line.items[6..line.items.len], 6..) |char, i| {
            if (char == ' ') {
                var_count = try std.fmt.parseInt(usize, line.items[6..i], 0);
                space_place = i;
                found_space = true;
            } else if (char != '\r' and !is_num(char)) {
                return ParseError.NotaDigit;
            }
        }

        clause_count = try std.fmt.parseInt(usize, line.items[(space_place + 1)..end], 0);

        self.sat_type = SatData{
            .variable_count = var_count,
            .clause_count = clause_count,
        };
    }

    const ParseError = error{
        IllegalClauseCount,
        UnexpectedCharacter,
        NonExistingVariableRef,
        IllegalHeader,
        NotaDigit,
    };
};

const SatData = struct {
    variable_count: usize,
    clause_count: usize,
};
