const Allocator = std.mem.Allocator;
const SatInstance = @import("sat instance.zig").SatInstance;
const Clause = @import("clause.zig").Clause;
const Variable = @import("variable.zig").Variable;
const Literal = @import("literal.zig").Literal;
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

        var instance = SatInstance.init(allocator, try allocator.alloc(Variable, 0));

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
        try stdout.print("{s}\n", .{instance});

        return instance;
    }

    fn parse_line(self: *InstanceBuilder, line: std.ArrayList(u8), instance: *SatInstance) !void {
        const stdout = std.io.getStdOut().writer();

        if (line.items.len == 0) {
            try self.parse_clause(line, instance);
            return;
        }

        switch (line.items[0]) {
            'c' => {},
            'p' => {
                try self.parse_p(line);
                instance.allocator.free(instance.variables);
                instance.variables = try instance.allocator.alloc(Variable, self.sat_type.variable_count);
                @memset(instance.variables, .UNASSIGNED);

                try stdout.print(
                    "c Parsed a SAT instance with {d} variables and {d} clauses.\n",
                    .{ self.sat_type.variable_count, self.sat_type.clause_count },
                );
            },
            else => try self.parse_clause(line, instance),
        }
    }

    fn parse_clause(self: *InstanceBuilder, line: std.ArrayList(u8), instance: *SatInstance) !void {
        _ = instance;
        _ = line;
        _ = self;
        return;
        //if (instance.clauses.items.len == self.sat_type.clause_count) {
        //    return;
        //}

        //var new_clause = Clause{
        //    .literals = std.ArrayList(Literal).init(instance.allocator),
        //};

        //var parsing_num = false;
        //var current_num: u31 = 1;
        //var neg: bool = false;
        //for (line.items) |character| {
        //    if (parsing_num and is_whitespace(character)) {
        //        parsing_num = false;
        //        if (instance.*.variables.len < current_num) {
        //            std.debug.print("found a disallowed: {d}\n", .{current_num});
        //            return ParseError.NonExistingVariableRef;
        //        }

        //        if (current_num == 0) {
        //            break;
        //        }

        //        try new_clause.literals.append(Literal{
        //            .is_negated = neg,
        //            .variable = current_num - 1,
        //        });

        //        current_num = 1;
        //        neg = false;
        //    }

        //    if (parsing_num) {
        //        if (!is_num(character)) {
        //            std.debug.print("found a disallowed: ({c})\n", .{character});
        //            return ParseError.NotaDigit;
        //        }

        //        current_num *= 10;
        //        current_num += @intCast(character - '0');
        //    }

        //    if (!parsing_num and (character == '-' or is_num(character))) {
        //        parsing_num = true;

        //        if (character == '-') {
        //            neg = true;
        //            current_num = 0;
        //        } else {
        //            current_num = @intCast(character - '0');
        //        }
        //    }

        //    if (!parsing_num and !is_whitespace(character)) {
        //        std.debug.print("found a disallowed: {c}\n", .{character});
        //        return ParseError.UnexpectedCharacter;
        //    }
        //}

        //try instance.clauses.append(new_clause);
        //self.clause_num += 1;
    }

    fn is_whitespace(character: u8) bool {
        return character == ' ' or character == '\t' or character == '\r';
    }

    fn is_num(character: u8) bool {
        return character >= '0' and character <= '9';
    }

    fn parse_p(self: *InstanceBuilder, line: std.ArrayList(u8)) !void {
        if (!std.mem.eql(u8, line.items[0..5], "p cnf")) {
            return ParseError.IllegalHeader;
        }

        var var_count: usize = undefined;
        var clause_count: usize = undefined;

        var num_start: usize = 0;

        var end: usize = undefined;
        var parsing = false;
        var parsing_var_count = true;

        if (line.items[line.items.len - 1] == '\r') {
            end = line.items.len - 1;
        } else {
            end = line.items.len;
        }

        for (line.items[6..end], 6..) |char, i| {
            if (!parsing) {
                if (is_num(char)) {
                    parsing = true;
                    num_start = i;
                } else if (!is_whitespace(char)) {
                    return ParseError.UnexpectedCharacter;
                }
            } else if (parsing and is_whitespace(char)) {
                if (parsing_var_count) {
                    var_count = try std.fmt.parseInt(usize, line.items[num_start..i], 0);
                    parsing_var_count = false;
                } else {
                    clause_count = try std.fmt.parseInt(usize, line.items[num_start..i], 0);
                    break;
                }
                parsing = false;
            } else if (parsing and !is_num(char)) {
                return ParseError.NotaDigit;
            }

            if (parsing and i == end - 1) {
                clause_count = try std.fmt.parseInt(usize, line.items[num_start..end], 0);
                if (parsing_var_count) {
                    return ParseError.UnknownFormat;
                }
            }
        }

        if (parsing_var_count) {
            return ParseError.UnknownFormat;
        }

        self.sat_type = SatData{
            .variable_count = var_count,
            .clause_count = clause_count,
        };
    }

    const ParseError = error{
        UnknownFormat,
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
