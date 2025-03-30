const std = @import("std");
const Data = @import("Data.zig");

const Match = @import("Match.zig");
const Carry = Match.Carry;
const bitIndexesOfTag = Match.bitIndexesOfTag;
const bitIndexesOfScalar = Match.bitIndexesOfScalar;

const Tag = @This();
const BitTricks = @import("BitTricks");
const VECTOR_LEN: u8 = 64;

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
            '\'', '\"' => end = skipComment(usize, data, end),
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

pub fn count(comptime T: type, text: []const u8, char: u8) T {
    var n_found: T = 0;

    var i: T = 0;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch == '\'' or ch == '\"') {
            i = skipComment(T, text, i);
            continue;
        }
        n_found += @intFromBool(ch == char);
    }

    return n_found;
}

test "Count Tags" {
    const T: type = u16;
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const n_open = count(T, text, '<');
    const n_close = count(T, text, '>');
    try std.testing.expect(n_open == n_close);
    try std.testing.expect(n_open == 8);
}

pub fn getTags(allo: std.mem.Allocator, data: []const u8) !std.ArrayList(Tag) {
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

pub fn countTagsV(text: []const u8) u32 {
    const TEXT_LEN: u32 = @truncate(text.len);
    var n_tags: u32 = 0;

    var i: u32 = 0;
    var carry = std.mem.zeroes(Carry);
    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        const match = bitIndexesOfTag(text[i .. i + VECTOR_LEN], carry);
        carry = match.carry;
        n_tags += @popCount(match.open_matches);
    }

    if (i != TEXT_LEN) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. text.len - i], text[i..text.len]);
        @memset(text_data[text.len - i .. VECTOR_LEN], 0);

        const match = bitIndexesOfTag(&text_data, carry);
        carry = match.carry;
        n_tags += @popCount(match.open_matches);
    }

    return n_tags;
}

pub fn countScalarV(text: []const u8, comptime char: u8) u32 {
    const TEXT_LEN: u32 = @truncate(text.len);
    var n_tags: u32 = 0;

    var i: u32 = 0;
    var carry = std.mem.zeroes(Carry);
    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        const match = bitIndexesOfScalar(text[i .. i + VECTOR_LEN], char, carry);
        carry = match.carry;
        n_tags += @popCount(match.matches);
    }

    if (i != TEXT_LEN) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. text.len - i], text[i..text.len]);
        @memset(text_data[text.len - i .. VECTOR_LEN], 0);

        const match = bitIndexesOfScalar(&text_data, char, carry);
        carry = match.carry;
        n_tags += @popCount(match.matches);
    }

    return n_tags;
}

test "Count Chars - Vectorized Version" {
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";

    const n_tags = countTagsV(text);
    const n_open = countScalarV(text, '<');
    const n_close = countScalarV(text, '>');

    try std.testing.expect(n_open == n_close);
    try std.testing.expect(n_open == 8);
    try std.testing.expect(n_tags == n_open);
}

pub fn getTagsV(text: []const u8, tags: []Tag) void {
    if (text.len == 0) unreachable;
    if (tags.len == 0) unreachable;
    std.debug.assert(tags.len < std.math.maxInt(u32));
    const TEXT_LEN: u32 = @truncate(text.len);

    var i: u32 = 0;
    var carry: Carry = std.mem.zeroes(Carry);
    var tag_idx: u32 = 0;
    var is_first: bool = true;

    // normal case
    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        var match = bitIndexesOfTag(text[i .. i + VECTOR_LEN], carry);
        carry = match.carry;

        // spillover case
        if (is_first and match.close_matches > 0) {
            if (@ctz(match.close_matches) < @ctz(match.open_matches)) {
                match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);
            }
            is_first = false;
        }

        while (match.close_matches > 0) : (tag_idx += 1) {
            const open_bit = @ctz(match.open_matches);
            const close_bit = @ctz(match.close_matches);

            match.open_matches = BitTricks.turnOffLastBit(u64, match.open_matches);
            match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);

            tags[tag_idx] = Tag{
                .start = i + open_bit,
                .end = i + close_bit,
            };
        }
    }

    // leftover case
    if (i != TEXT_LEN) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. TEXT_LEN - i], text[i..text.len]);
        @memset(text_data[TEXT_LEN - i .. VECTOR_LEN], 0);

        var match = bitIndexesOfTag(&text_data, carry);
        carry = match.carry;

        // spillover case
        if (is_first and match.close_matches > 0) {
            if (@ctz(match.close_matches) < @ctz(match.open_matches)) {
                match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);
            }
            is_first = false;
        }

        while (match.close_matches > 0) : (tag_idx += 1) {
            const open_bit = @ctz(match.open_matches);
            const close_bit = @ctz(match.close_matches);

            match.open_matches = BitTricks.turnOffLastBit(u64, match.open_matches);
            match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);

            tags[tag_idx] = Tag{
                .start = i + open_bit,
                .end = i + close_bit,
            };
        }
    }
}

test "Vectorized Get Tags" {
    const allo = std.testing.allocator;
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";

    const expected_tags = [8]Tag{
        .{ .start = 0, .end = 7 },
        .{ .start = 8, .end = 14 },
        .{ .start = 26, .end = 33 },
        .{ .start = 34, .end = 39 },
        .{ .start = 44, .end = 50 },
        .{ .start = 51, .end = 56 },
        .{ .start = 72, .end = 78 },
        .{ .start = 79, .end = 87 },
    };

    const n_tags = countTagsV(text);
    try std.testing.expectEqual(n_tags, expected_tags.len);

    const tags = try allo.alloc(Tag, n_tags);
    defer allo.free(tags);
    getTagsV(text, tags);

    const expected_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };

    for (tags, expected_tags, expected_names) |tag, expected_tag, expected_name| {
        try std.testing.expectEqualDeep(expected_tag, tag);
        const actual_name = getTagName(text, tag);
        try std.testing.expectEqualStrings(expected_name, actual_name);
    }
}
test "Vectorzed Get Tags - 1 close bit before open bit" {
    const allo = std.testing.allocator;
    const text: []const u8 = "hello><member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";

    const n_tags = countTagsV(text);

    const tags = try allo.alloc(Tag, n_tags);
    defer allo.free(tags);

    getTagsV(text, tags);

    const expected_tags = [8]Tag{
        .{ .start = 6, .end = 13 },
        .{ .start = 14, .end = 20 },
        .{ .start = 32, .end = 39 },
        .{ .start = 40, .end = 45 },
        .{ .start = 50, .end = 56 },
        .{ .start = 57, .end = 62 },
        .{ .start = 78, .end = 84 },
        .{ .start = 85, .end = 93 },
    };

    const expected_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };

    for (tags, expected_tags, expected_names) |tag, expected_tag, expected_name| {
        try std.testing.expectEqualDeep(expected_tag, tag);
        const actual_name = getTagName(text, tag);
        try std.testing.expectEqualStrings(expected_name, actual_name);
    }
}

test "Vectorized Get Tags - 1 close bit before open bit on second chunk of 64 bits" {
    const allo = std.testing.allocator;
    const text: []const u8 = "hellohellohellohellohellohellohellohellohellohellohellohellohello><member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const n_tags = countTagsV(text);

    const tags = try allo.alloc(Tag, n_tags);
    defer allo.free(tags);

    getTagsV(text, tags);

    for (tags) |tag| {
        std.debug.print("{}-{} ", .{ tag.start, tag.end });
    }

    // const expected_tags2 = [8]Tag{
    //     .{ .start = 6, .end = 13 },
    //     .{ .start = 14, .end = 20 },
    //     .{ .start = 32, .end = 39 },
    //     .{ .start = 40, .end = 45 },
    //     .{ .start = 50, .end = 56 },
    //     .{ .start = 57, .end = 62 },
    //     .{ .start = 78, .end = 84 },
    //     .{ .start = 85, .end = 93 },
    // };
    //
    // const expected_names2 = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };
    //
    // for (tags2, expected_tags2, expected_names2) |tag, expected_tag, expected_name| {
    //     try std.testing.expectEqualDeep(expected_tag, tag);
    //     const actual_name = getTagName(text1, tag);
    //     try std.testing.expectEqualStrings(expected_name, actual_name);
    // }
}

fn countTagsVWrapper(text: []const u8, num_tags: *u32, is_complete: *bool) void {
    num_tags.* = countTagsV(text);
    is_complete.* = true;
}

fn getTagsVWrapper(text: []const u8, tags: []Tag, is_complete: *bool, start: u32) void {
    if (text.len == 0) unreachable;
    if (tags.len == 0) unreachable;
    getTagsV(text, tags);
    if (start > 0) {
        for (0..tags.len) |i| {
            tags[i].start +%= start;
            tags[i].end +%= start;
        }
    }
    is_complete.* = true;
}

pub fn getTagsT(comptime N_THREADS: u8, allo: std.mem.Allocator, text: []const u8) ![]Tag {
    if (N_THREADS < 1 or N_THREADS > 12) @compileError("1 <= # of Threads <= 12");
    if (text.len == 0) unreachable;

    const MIN_TEXT_CHUNK_SIZE: u8 = 64; // want at least 64 bytes per chunk
    const n_chunks: u32 = @as(u32, @truncate(text.len / MIN_TEXT_CHUNK_SIZE)) + @as(u32, @intFromBool(@mod(text.len, MIN_TEXT_CHUNK_SIZE) == 0));
    const n_iters = @min(n_chunks, N_THREADS);

    const text_step: u32 = @max(@as(u32, @truncate(text.len / n_iters)), MIN_TEXT_CHUNK_SIZE);

    var is_complete = [_]bool{false} ** N_THREADS;
    if (n_chunks < N_THREADS) {
        for (n_chunks..N_THREADS) |i| is_complete[i] = true;
    }
    const trues: @Vector(N_THREADS, bool) = @splat(true);

    const text_start: [N_THREADS]u32, const text_end: [N_THREADS]u32 = blk: {
        var text_start: [N_THREADS]u32 = undefined;
        var text_end: [N_THREADS]u32 = undefined;
        var curr_pos: u32 = 0;
        for (0..n_iters - 1) |i| {
            text_start[i] = curr_pos;
            curr_pos +%= text_step;
            text_end[i] = curr_pos;
        } else {
            text_start[n_iters - 1] = curr_pos;
            text_end[n_iters - 1] = @truncate(text.len);
        }
        break :blk .{ text_start, text_end };
    };

    var threads: [N_THREADS]std.Thread = undefined;
    const n_tags: [N_THREADS]u32 = blk: {
        var n_tags = [_]u32{0} ** N_THREADS;
        for (0..n_iters) |i| {
            const curr_text = text[text_start[i]..text_end[i]];
            threads[i] = try std.Thread.spawn(.{}, countTagsVWrapper, .{ curr_text, &n_tags[i], &is_complete[i] });
        }
        for (0..n_iters) |i| threads[i].detach();
        while (true) {
            const v = @as(@Vector(N_THREADS, bool), is_complete);
            if (@reduce(.And, v == trues)) break;
        }
        break :blk n_tags;
    };

    const total_tags = @reduce(.Add, @as(@Vector(N_THREADS, u32), n_tags));
    const tags = try allo.alloc(Tag, total_tags);

    const tags_start: [N_THREADS]u32, const tags_end: [N_THREADS]u32 = blk: {
        var tags_start: [N_THREADS]u32 = undefined;
        var tags_end: [N_THREADS]u32 = undefined;
        var curr_pos: u32 = 0;
        for (0..n_iters - 1) |i| {
            tags_start[i] = curr_pos;
            curr_pos +%= n_tags[i];
            tags_end[i] = curr_pos;
        } else {
            tags_start[n_iters - 1] = curr_pos;
            tags_end[n_iters - 1] = @truncate(tags.len);
        }
        break :blk .{ tags_start, tags_end };
    };

    @memset(is_complete[0..n_iters], false);

    for (0..n_iters) |i| {
        if (text_start[i] == text_end[i] or tags_start[i] == tags_end[i]) {
            is_complete[i] = true;
            continue;
        }
        const curr_text: []const u8 = text[text_start[i]..text_end[i]];
        const curr_tags: []Tag = tags[tags_start[i]..tags_end[i]];
        threads[i] = try std.Thread.spawn(.{}, getTagsVWrapper, .{
            curr_text,
            curr_tags,
            &is_complete[i],
            text_start[i],
        });
    }
    for (0..n_iters) |i| threads[i].detach();

    while (true) {
        const v = @as(@Vector(N_THREADS, bool), is_complete);
        if (@reduce(.And, v == trues)) break;
    }

    return tags;
}

// test "Get Tags T" {
//     const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
//     const allo = std.testing.allocator;
//
//     const expected_tags = [_]Tag{
//         .{ .start = 0, .end = 7 },
//         .{ .start = 8, .end = 14 },
//         .{ .start = 26, .end = 33 },
//         .{ .start = 34, .end = 39 },
//         .{ .start = 44, .end = 50 },
//         .{ .start = 51, .end = 56 },
//         .{ .start = 72, .end = 78 },
//         .{ .start = 79, .end = 87 },
//     };
//
//     const expected_tag_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };
//
//     { // single thread works
//         const tags = try getTagsT(1, allo, text);
//         defer allo.free(tags);
//
//         for (expected_tags, tags) |expected_tag, tag| {
//             try std.testing.expectEqual(tag.start, expected_tag.start);
//             try std.testing.expectEqual(tag.end, expected_tag.end);
//         }
//
//         for (expected_tag_names, tags) |expected_tag_name, tag| {
//             const tag_name = getTagName(text, tag);
//             try std.testing.expectEqualStrings(expected_tag_name, tag_name);
//         }
//     }
//
//     { // Multiple Threads - Basic Test
//         const tags = try getTagsT(2, allo, text);
//         defer allo.free(tags);
//
//         for (expected_tags, tags) |expected_tag, tag| {
//             try std.testing.expectEqual(expected_tag.start, tag.start);
//             try std.testing.expectEqual(expected_tag.end, tag.end);
//         }
//
//         for (expected_tag_names, tags) |expected_tag_name, tag| {
//             const tag_name = getTagName(text, tag);
//             try std.testing.expectEqualStrings(expected_tag_name, tag_name);
//         }
//     }
//
//     { // Multiple Threads - 1. split data into 64 byte chunks and process those w/ fewest needed threads
//         const tags = try getTagsT(3, allo, text);
//         defer allo.free(tags);
//
//         for (expected_tags, tags) |expected_tag, tag| {
//             try std.testing.expectEqual(expected_tag.start, tag.start);
//             try std.testing.expectEqual(expected_tag.end, tag.end);
//         }
//
//         for (expected_tag_names, tags) |expected_tag_name, tag| {
//             const tag_name = getTagName(text, tag);
//             try std.testing.expectEqualStrings(expected_tag_name, tag_name);
//         }
//     }
// }
//
// test "Get Tags W/ Real-World Dataset " {
//     const allo = std.testing.allocator;
//
//     const filename = "src/vk_extern_struct.xml";
//     const data = try Data.init(allo, filename);
//     defer data.deinit();
//
//     const tags_t0 = blk: {
//         const n_tags = Tag.countTagsV(data.data);
//         const tags = try allo.alloc(Tag, n_tags);
//         Tag.getTagsV(data.data, tags);
//         break :blk tags;
//     };
//     defer allo.free(tags_t0);
//
//     const tags_t1 = blk: {
//         const tags = try Tag.getTagsT(1, allo, data.data);
//         break :blk tags;
//     };
//     defer allo.free(tags_t1);
//
//     const tags_t2 = blk: {
//         const tags = try Tag.getTagsT(2, allo, data.data);
//         break :blk tags;
//     };
//     defer allo.free(tags_t2);
//     for (tags_t0, tags_t2) |t0, t2| {
//         std.debug.print("{}{} {}{}\n", .{ t0.start, t2.start, t0.end, t2.end });
//     }
//
//     const tags_t4 = blk: {
//         const tags = try Tag.getTagsT(4, allo, data.data);
//         break :blk tags;
//     };
//     defer allo.free(tags_t4);
//     // for (tags_t0, tags_t4) |t0, t4| {
//     //     std.debug.print("{}{} {}{}\n", .{ t0.start, t4.start, t0.end, t4.end });
//     // }
//
//     // breaks - why?
//     // std.debug.print("12 Threads.\n", .{});
//     // const tags_t12 = blk: {
//     //     const tags = try Tag.getTagsT(11, allo, data.data);
//     //     break :blk tags;
//     // };
//     // defer allo.free(tags_t12);
//
//     // std.debug.print("Here.\n", .{});
//     // for (tags_t0, tags_t1, tags_t2) |tag0, tag1, tag2| {
//     //     try std.testing.expectEqual(tag0.start, tag1.start);
//     //     try std.testing.expectEqual(tag0.end, tag1.end);
//     //
//     //     try std.testing.expectEqual(tag0.start, tag2.start);
//     //     try std.testing.expectEqual(tag0.end, tag2.end);
//     // }
// }
