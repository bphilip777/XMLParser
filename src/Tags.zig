const std = @import("std");
const Data = @import("Data.zig");

const Carry = @import("Match.zig").Carry;
const bitIndexesOfTag = @import("Match.zig").bitIndexesOfTag;
const bitIndexesOf = @import("Match.zig").bitIndexesOf;

const Tag = @This();
const BitTricks = @import("BitTricks");
const VECTOR_LENGTH: u8 = 64;

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

// test "Match" {
//     const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
//     const bit_matches = bitIndexesOfTag(text, 0);
// }

// not generic - made to count the # of tags inside a text
pub fn countV(text: []const u8) u32 {
    const TEXT_LEN: u32 = @truncate(text.len);
    var n_tags: u32 = 0;

    var i: u32 = 0;
    var carry: Carry = 0;
    while (i + VECTOR_LENGTH < TEXT_LEN) : (i += VECTOR_LENGTH) {
        const match = bitIndexesOf(text, "<", carry);
        carry = match.carry;
        n_tags += @popCount(match.open_matches);
    }

    if (i != TEXT_LEN) {
        const text_data = [_]u8{0} ** VECTOR_LENGTH;
        @memcpy(text_data[0 .. text.len - i], text[i..text.len]);
        const match = bitIndexesOfTag(text, carry);
        carry = match.carry;
        n_tags += @popCount(match.open_matches);
    }

    return n_tags;
}

test "Count Tags - Vectorized Version" {
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const n_open = countV(text, '<');
    const n_close = countV(text, '>');
    try std.testing.expect(n_open == n_close);
    try std.testing.expect(n_open == 8);
}

// pub fn getTagsV(tags: []Tag, text: []const u8, complete: *bool) !void {
//     // Vectorized Version of get Tags
//     // assumes no intersection b/w quotes - only subsets or independent quotes (i.e. '""' or ''"", no '"'")
//     // assumes '<' precedes '>', all independent, no subsets (i.e. no <<>>, only <><>)
//     // assumes memory pre-allocated by using countV for size
//     const TEXT_LEN = text.len;
//
//     // flags
//     var open_carry: bool = false;
//     var open_position: u32 = 0;
//
//     var squote_carry: bool = false;
//     var dquote_carry: bool = false;
//
//     var i: u32 = 0;
//     var tag_idx: u32 = 0;
//
//     // first match - b/c of threads could have a close before an open
//     while (i + VECTOR_LENGTH < TEXT_LEN) : (i += VECTOR_LENGTH) {
//         const data_vector: V = @as(V, text[i..][0..VECTOR_LENGTH].*);
//
//         // matches are in bitreverse order already
//         var open_matches = @as(u64, @bitCast(o == data_vector));
//         var close_matches = @as(u64, @bitCast(c == data_vector));
//         var squote_matches = @as(u64, @bitCast(s == data_vector));
//         var dquote_matches = @as(u64, @bitCast(d == data_vector));
//
//         // turn quote matches into masks
//         squote_matches, squote_carry = blk: {
//             const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
//             break :blk .{ bt.mask, bt.carry };
//         };
//
//         dquote_matches, dquote_carry = blk: {
//             const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
//             break :blk .{ bt.mask, bt.carry };
//         };
//
//         // remove matches within masks
//         open_matches &= ~squote_matches;
//         close_matches &= ~squote_matches;
//
//         open_matches &= ~dquote_matches;
//         close_matches &= ~dquote_matches;
//
//         // no matches = skip
//         if (close_matches == 0 and open_matches == 0) continue;
//
//         // on first match, open idx must be smaller than close idx for threaded version
//         if (@ctz(close_matches) < @ctz(open_matches)) {
//             close_matches = BitTricks.turnOffLastBit(u64, close_matches);
//         }
//
//         while (close_matches > 0) {
//             const o_bit = @ctz(open_matches);
//             const c_bit = @ctz(close_matches);
//
//             open_matches = BitTricks.turnOffLastBit(u64, open_matches);
//             close_matches = BitTricks.turnOffLastBit(u64, close_matches);
//
//             tags[tag_idx] = .{
//                 .start = i + o_bit,
//                 .end = i + c_bit,
//             };
//             tag_idx += 1;
//         }
//
//         break;
//     }
//
//     // normal loop
//     while (i + VECTOR_LENGTH < TEXT_LEN) : (i += VECTOR_LENGTH) {
//         const data_vector: V = @as(V, text[i..][0..VECTOR_LENGTH].*);
//
//         // matches are in bitreverse order already
//         var open_matches = @as(u64, @bitCast(o == data_vector));
//         var close_matches = @as(u64, @bitCast(c == data_vector));
//         var squote_matches = @as(u64, @bitCast(s == data_vector));
//         var dquote_matches = @as(u64, @bitCast(d == data_vector));
//
//         // turn quote matches into masks
//         squote_matches, squote_carry = blk: {
//             const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
//             break :blk .{ bt.mask, bt.carry };
//         };
//
//         dquote_matches, dquote_carry = blk: {
//             const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
//             break :blk .{ bt.mask, bt.carry };
//         };
//
//         // remove matches within masks
//         open_matches &= ~squote_matches;
//         close_matches &= ~squote_matches;
//
//         open_matches &= ~dquote_matches;
//         close_matches &= ~dquote_matches;
//
//         // carrying a match across loops
//         if (open_carry) {
//             if (close_matches == 0) continue;
//
//             const c_bit = @ctz(close_matches);
//             close_matches = BitTricks.turnOffLastBit(u64, close_matches);
//             tags[tag_idx] = .{
//                 .start = open_position,
//                 .end = i + c_bit,
//             };
//
//             tag_idx += 1;
//             open_carry = false;
//             open_position = undefined;
//         }
//
//         // assume all open matches precede close matches + no open carry + no intersections of open and close carries
//         while (close_matches > 0) {
//             const o_bit = @ctz(open_matches);
//             const c_bit = @ctz(close_matches);
//
//             open_matches = BitTricks.turnOffLastBit(u64, open_matches);
//             close_matches = BitTricks.turnOffLastBit(u64, close_matches);
//
//             tags[tag_idx] = .{
//                 .start = i + o_bit,
//                 .end = i + c_bit,
//             };
//             tag_idx += 1;
//         }
//
//         if (open_matches > 0) {
//             open_carry = true;
//             open_position = i + @ctz(open_matches);
//         }
//     }
//
//     if (i != TEXT_LEN) {
//         var data = [_]u8{0} ** VECTOR_LENGTH;
//         @memcpy(data[0 .. TEXT_LEN - i], text[i..TEXT_LEN]);
//         const data_vector: V = @as(V, data);
//
//         // matches are in bitreverse order already
//         var open_matches = @as(u64, @bitCast(o == data_vector));
//         var close_matches = @as(u64, @bitCast(c == data_vector));
//         var squote_matches = @as(u64, @bitCast(s == data_vector));
//         var dquote_matches = @as(u64, @bitCast(d == data_vector));
//
//         // turn quote matches into masks
//         squote_matches, squote_carry = blk: {
//             const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
//             break :blk .{ bt.mask, bt.carry };
//         };
//
//         dquote_matches, dquote_carry = blk: {
//             const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
//             break :blk .{ bt.mask, bt.carry };
//         };
//
//         // remove matches within masks
//         open_matches &= ~squote_matches;
//         close_matches &= ~squote_matches;
//
//         open_matches &= ~dquote_matches;
//         close_matches &= ~dquote_matches;
//
//         if (open_carry) {
//             if (close_matches == 0) {
//                 tags[tag_idx] = .{
//                     .start = open_position,
//                     .end = undefined,
//                 };
//                 return;
//             }
//
//             const c_bit = @ctz(close_matches);
//             close_matches = BitTricks.turnOffLastBit(u64, close_matches);
//             tags[tag_idx] = .{
//                 .start = open_position,
//                 .end = i + c_bit,
//             };
//
//             tag_idx += 1;
//             open_carry = false;
//             open_position = undefined;
//         }
//
//         // assume all open matches precede close matches + no open carry + no intersections of open and close carries
//         while (close_matches > 0) {
//             const o_bit = @ctz(open_matches);
//             const c_bit = @ctz(close_matches);
//
//             open_matches = BitTricks.turnOffLastBit(u64, open_matches);
//             close_matches = BitTricks.turnOffLastBit(u64, close_matches);
//
//             tags[tag_idx] = .{
//                 .start = i + o_bit,
//                 .end = i + c_bit,
//             };
//             tag_idx += 1;
//         }
//
//         // illegal behavior if single thread looping through entire text
//         // allowable behavior if multi-threaded looping through partitioned text - caught outside this fn in getTagsT
//         if (open_matches > 0) {
//             tags[tag_idx] = .{
//                 .start = i + @ctz(open_matches),
//                 .end = undefined,
//             };
//         }
//     }
//
//     complete.* = true;
// }
//
// test "Vectorized Get Tags" {
//     const allo = std.testing.allocator;
//     const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
//
//     const expected_tags = [8]Tag{
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
//     const n_tags = countV(text, '<');
//     const tags: []Tag = try allo.alloc(Tag, n_tags);
//     defer allo.free(tags);
//
//     var is_complete: bool = false;
//     try getTagsV(tags, text, &is_complete);
//
//     const expected_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };
//
//     for (tags, expected_tags, expected_names) |tag, expected_tag, expected_name| {
//         try std.testing.expectEqualDeep(expected_tag, tag);
//         const actual_name = getTagName(text, tag);
//         try std.testing.expectEqualStrings(expected_name, actual_name);
//     }
// }
//
// pub fn getTagsT(comptime N_THREADS: u8, allo: std.mem.Allocator, text: []const u8) ![]Tag {
//     // Vectorized + Threaded version of getTags
//     // Assumptions:
//     // 1. Distance b/w tag open + tag close < section length
//     // - Section Length = text.len / # of threads
//     // - tags can open and close w/in a section
//     // - tags can span across 1 section
//     // 2. Text split evenly into sections except for last section (goes to text length)
//     // - # of threads <= 2 * # of characters in text
//     // 3. Equal # of tag opens and closes
//     // - Illegal behavior otherwise
//     // 4. Every close tag is preceded by an open tag
//     // 5. Tags do not intersect nor subset - are independent
//     // - <><> = Valid
//     // - <<>> = subset = illegal behavior
//     // - <_1 <_2 >_1 >_2 = intersect = illegal behavior
//     // 6. Total # of Tags < std.math.maxInt(u32)
//     // 7. Memory available to store total # of tags
//
//     if (N_THREADS == 0 or N_THREADS > 12) @compileError("1 <= # of Threads <= 12.");
//     if (!(N_THREADS <= text.len * 2)) return error.MoreThreadsThanCharactersInText;
//
//     const step: u32 = @truncate(text.len / N_THREADS);
//     var n_opens = [_]u32{0} ** N_THREADS;
//     var n_closes = [_]u32{0} ** N_THREADS;
//     var is_spanning_sections = [_]bool{false} ** N_THREADS;
//
//     inline for (0..N_THREADS) |i| {
//         const start = i * step;
//         const end = if (i == N_THREADS - 1) text.len else start + step;
//
//         n_opens[i] = countV(text[start..end], '<');
//         n_closes[i] = countV(text[start..end], '>');
//
//         std.debug.assert(!(n_opens[i] == n_closes[i] and n_opens[i] == 0));
//
//         const last_open_idx = std.mem.lastIndexOfScalar(u8, text[start..end], '<') orelse start;
//         const last_close_idx = std.mem.lastIndexOfScalar(u8, text[start..end], '>') orelse start;
//         is_spanning_sections[i] = last_open_idx > last_close_idx;
//     }
//
//     // Make sure each thread has tags within it - otherwise parsing may break
//     inline for (n_opens) |n_open| {
//         std.debug.assert(n_open != 0);
//     }
//
//     const TOTAL_TAGS: u32 = @reduce(.Add, @as(@Vector(N_THREADS, u32), n_opens));
//     const tags = try allo.alloc(Tag, TOTAL_TAGS);
//
//     var is_thread_complete = [_]bool{false} ** N_THREADS;
//
//     var tag_idx: u32 = 0;
//     for (0..N_THREADS) |i| {
//         const start = i * step;
//         const end = if (i == N_THREADS - 1) text.len else start + step;
//
//         const thread = try std.Thread.spawn(.{}, getTagsV, .{
//             tags[tag_idx .. tag_idx + n_opens[i]],
//             text[start..end],
//             &is_thread_complete[i],
//         });
//         defer thread.detach();
//
//         tag_idx += n_opens[i];
//     }
//
//     const trues = @as(@Vector(N_THREADS, bool), @splat(true));
//     while (true) {
//         const all_complete = @as(@Vector(N_THREADS, bool), is_thread_complete);
//         if (@reduce(.And, all_complete == trues)) break;
//     }
//
//     // Fix tags spanning sections
//     tag_idx = 0;
//     for (0..N_THREADS - 1) |i| {
//         const iss = is_spanning_sections[i];
//         if (!iss) continue;
//
//         const n_open = n_opens[i];
//         const start = (i + 1) * step;
//         const end = if (i == N_THREADS - 2) text.len else start + step;
//         tag_idx += n_open;
//         tags[tag_idx].end = @truncate(std.mem.indexOfScalar(u8, text[start..end], '>') orelse unreachable);
//     }
//
//     // Adjust tags based on section
//     var tags_start: u32 = 0;
//     var tags_end: u32 = 0;
//     for (0..N_THREADS) |i| {
//         const section_start: u32 = @truncate(i * step);
//         tags_end += n_opens[i];
//
//         for (tags_start..tags_end) |j| {
//             tags[j].start += section_start;
//             tags[j].end += section_start;
//         }
//
//         tags_start += n_opens[i];
//     }
//
//     return tags;
// }
//
// test "Get Tags T" {
//     const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
//     const allo = std.testing.allocator;
//     // getTagsT(1, allo, text);
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
//             try std.testing.expect(expected_tag.start == tag.start and expected_tag.end == tag.end);
//         }
//
//         for (expected_tag_names, tags) |expected_tag_name, tag| {
//             const tag_name = getTagName(text, tag);
//             try std.testing.expectEqualStrings(expected_tag_name, tag_name);
//         }
//     }
//
//     { // Multiple Threads
//         const tags = try getTagsT(2, allo, text);
//         defer allo.free(tags);
//
//         for (expected_tags, tags) |expected_tag, tag| {
//             try std.testing.expect(expected_tag.start == tag.start and expected_tag.end == tag.end);
//         }
//
//         for (expected_tag_names, tags) |expected_tag_name, tag| {
//             const tag_name = getTagName(text, tag);
//             try std.testing.expectEqualStrings(expected_tag_name, tag_name);
//         }
//     }
// }
