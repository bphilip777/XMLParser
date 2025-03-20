const std = @import("std");
const Data = @import("Data.zig");
const Tag = @This();

start: u32,
end: u32,

pub fn getTagName(data: []const u8, tag: Tag) []const u8 {
    if (data[tag.start] != '<') unreachable;
    var start: usize = tag.start + 1;
    while (true) : (start += 1) {
        switch (data[start]) {
            'a'...'z', 'A'...'Z' => break,
            ' ', '/' => {},
            else => unreachable,
        }
    }

    var end: usize = start;
    while (true) : (end += 1) {
        switch (data[end]) {
            '>', ' ' => break,
            '\'', '\"' => end = skipComment(data, end),
            else => {},
        }
    }

    return data[start..end];
}

test "Get Tag Name" {
    const tags = [_][]const u8{ "<tag>", "</tag>", "<type category=\"struct\" name=\"VkInstanceCreateInfo\">" };
    const exp_names = [_][]const u8{ "tag", "tag", "type" };
    for (tags, exp_names) |tag, exp_name| {
        const tag_name = getTagName(tag, .{ .start = 0, .end = @truncate(tag.len) });
        try std.testing.expectEqualStrings(exp_name, tag_name);
    }
}

pub fn tagNamesMatch(data: []const u8, tag1: Tag, tag2: Tag) bool {
    const tag1_name = getTagName(data, tag1);
    const tag2_name = getTagName(data, tag2);
    return std.mem.eql(u8, tag1_name, tag2_name);
}

test "Tag Names Match" {
    const data = [_][]const u8{ "<tag></tag>", "<type category=\"struct\" name=\"VkInstanceCreateInfo\"></type>" };
    const tag1s = [_]Tag{ .{ .start = 0, .end = 4 }, .{ .start = 0, .end = 44 } };
    const tag2s = [_]Tag{ .{ .start = 5, .end = 10 }, .{ .start = 52, .end = 58 } };
    for (data, tag1s, tag2s) |datum, tag1, tag2| {
        try std.testing.expect(tagNamesMatch(datum, tag1, tag2));
    }
}

fn skipComment(comptime T: type, data: []const u8, i: T) T {
    var j: T = i + 1;
    const char = data[i];
    while (true) : (j += 1) {
        if (data[j] == char) break;
    }
    return j;
}

pub fn getTagsV(data: Data) void { // !std.ArrayList(Tag) {
    const n_tags = getNumberOfTagsV(u16, data) catch unreachable;
    std.debug.print("# of Tags: {}\n", .{n_tags});

    var tags = std.ArrayList(Tag).initCapacity(data.allo, n_tags) catch unreachable;
    defer tags.deinit();

    // use simd + multiple threads to get all open tag positions
    // use simd + multiple threads to get all close tag positions
}

pub fn getNumberOfTagsV(comptime T: type, data: Data) !T {
    // Steps:
    // 0. T = comptime input, must be unsigned int
    // 1. count the number of < inside data = # of tags, skip "" or '' = # of openings
    // 2. count the number of > inside data = # of tags, skip "" or '' = # of closings
    // 3. assert # of openings = # of closings
    // 4. return # of tags

    const n_threads: T = 8;
    var n_opens = [_]T{0} ** n_threads;
    var n_closes = [_]T{0} ** n_threads;
    const len: T = @truncate(data.data.len);
    const step: T = len / n_threads;

    _ = blk: {
        inline for (0..n_threads) |i| {
            const start: T = @as(T, @truncate(i)) * step;
            const end: T = start + step;
            const thread = try std.Thread.spawn(.{}, getNumberOfTagsPerBlock, .{ T, data.data[start..end], &n_opens[i], &n_closes[i] });
            defer thread.detach();
        }
        break :blk 0;
    };

    const V: type = @Vector(n_threads, T);
    const n_open: T = @reduce(.Add, @as(V, n_opens));
    const n_close: T = @reduce(.Add, @as(V, n_closes));
    std.debug.print("# of Opens: {}\n", .{n_open});
    std.debug.print("# of Closes: {}\n", .{n_close});
    std.debug.assert(n_open == n_close);
    return n_open;
}

fn getNumberOfTagsPerBlock(comptime T: type, data: []const u8, n_open: *T, n_close: *T) void {
    var i: T = 0;
    const len = data.len;

    const V_len = 64;
    const V: type = @Vector(V_len, u8);
    const open_char: V = @splat('<');
    const close_char: V = @splat('>');

    // var overflow_paren: bool = false; // inside paren
    while (i + V_len < len) : (i += 8) {
        const v = @as(V, data[i..][0..V_len].*);

        // const parens: u64 = @bitCast(v == '\"' or v == '\'');

        const o: u64 = @bitCast(v == open_char);
        n_open.* += @as(T, @popCount(o));

        const c: u64 = @bitCast(v == close_char);
        n_close.* += @as(T, @popCount(c));
    }

    if (i + 1 < len) {
        var bit: [V_len]u8 = undefined;
        @memcpy(bit[0 .. len - i - 1], data[i..][0 .. len - i - 1]);
        @memset(bit[len - i - 1 .. V_len], 0);
        const v: V = bit;

        const o: u64 = @bitCast(v == open_char);
        n_open.* += @as(T, @popCount(o));

        const c: u64 = @bitCast(v == close_char);
        n_close.* += @as(T, @popCount(c));
    }
}

pub fn getNumberOfTags(comptime T: type, data: Data) !T {
    var n_opens: T = 0;
    var n_closes: T = 0;

    var i: T = 0;
    while (i < data.data.len) : (i += 1) {
        const ch = data.data[i];
        switch (ch) {
            '<' => n_opens += 1,
            '>' => n_closes += 1,
            '\'', '\"' => i = skipComment(T, data.data, i),
            else => {},
        }
    }
    std.debug.assert(n_opens == n_closes);
    return n_opens;
}

pub fn getTags(
    allo: std.mem.Allocator,
    data: []const u8,
) !std.ArrayList(Tag) {
    var tags = std.ArrayList(Tag).initCapacity(allo, 1_024) catch unreachable;

    var found_prolog: bool = false;
    var found_open: bool = false;

    var i: usize = 0;
    var j: usize = 0;

    while (true) : (i += 1) {
        if (i == data.len) break;
        switch (data[i]) {
            '<' => {
                if (found_open) std.log.err("On open, did not end previous tag: position: {}\n", .{i});
                const tag_type: TagType = getTagType(data, .{ .start = @truncate(i), .end = undefined });

                switch (tag_type) {
                    .prolog => {
                        if (found_prolog) std.log.err("On prolog, found more than 1: position: {}\n", .{i});
                        found_prolog = true;
                    },
                    else => {},
                }

                try tags.append(.{
                    .start = @truncate(i),
                    .end = undefined,
                });
                found_open = true;
            },
            '>' => {
                if (!found_open) std.log.err("On close, did not end previous tag: positon: {}\n", .{i});
                tags.items[j].end = @truncate(i);
                if (tags.items[j].end < tags.items[j].start) std.log.err("Tag: {} has end < start\n", .{i});
                found_open = false;
                j += 1;
            },
            '\'', '\"' => {
                i = skipComment(data, i);
            },
            else => {},
        }
    }

    return tags;
}

pub fn getTagType(data: []const u8, tag: Tag) TagType {
    return switch (data[tag.start + 1]) {
        '?' => .prolog,
        '/' => .close,
        'a'...'z', 'A'...'Z' => .open,
        else => unreachable,
    };
}

test "Get Tag Type" {
    const names = [_][]const u8{ "<name>", "</name>", "<?xml>" };
    const values = [_]TagType{ .open, .close, .prolog };
    for (names, values) |name, value| {
        const tag_type = getTagType(name, .{ .start = 0, .end = @truncate(name.len) });
        try std.testing.expect(tag_type == value);
    }
}

pub fn writeTags(
    allo: std.mem.Allocator,
    data: []const u8,
    filename: []const u8,
    tags: *const std.ArrayList(Tag),
) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    for (tags.items) |tag| {
        const line = try std.fmt.allocPrint(allo, "{s}\n", .{data[tag.start .. tag.end + 1]});
        defer allo.free(line);
        _ = file.write(line) catch unreachable;
    }
}

pub inline fn printTag(data: []const u8, tag: Tag) void {
    std.debug.print("{s}\n", .{data[tag.start .. tag.end + 1]});
}

pub fn printTags(data: []const u8, tags: []const Tag) void {
    for (tags) |tag| {
        printTag(data, tag);
    }
}

pub const TagType = enum {
    prolog,
    open,
    close,
};
