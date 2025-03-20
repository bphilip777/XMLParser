const std = @import("std");

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(.ok == da.deinit());
    const allo = da.allocator();

    // const filename = "src/vk.xml";
    const filename = "src/vk_extern_struct.xml";
    const data = try getData(allo, filename);
    defer allo.free(data);

    // Parse Tags
    const tags = try getTags(allo, data);
    defer tags.deinit();
    // try writeTags(allo, data, "src/tags.zig", &tags);
    // printTags(data, &tags);

    // // Parse Elements
    // var elements = try getElements(allo, data, tags.items);
    // defer elements.deinit(allo);
    // defer {
    //     const children = elements.items(.children);
    //     for (children) |maybe_child| {
    //         if (maybe_child) |child| {
    //             var list: std.ArrayList(u16) = @as(*std.ArrayList(u16), @ptrFromInt(child)).*;
    //             list.deinit();
    //         }
    //     }
    // }
    //
    // for (elements.items(.start), elements.items(.end)) |start, end| {
    //     const sname = getTagName(data, tags.items[start]);
    //     const ename = getTagName(data, tags.items[end]);
    //     std.debug.print("{s}:{s}\n", .{ sname, ename });
    //     // std.debug.print("{s}:{s}, {}:{}\n", .{ sname, ename, element.start, element.end });
    // }

    // Extract Extern Struct Data

}

fn getTagName(data: []const u8, tag: Tag) []const u8 {
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

fn tagNamesMatch(data: []const u8, tag1: Tag, tag2: Tag) bool {
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

fn getData(allo: std.mem.Allocator, filename: []const u8) ![]const u8 {
    const rfile = std.fs.cwd().openFile(filename, .{}) catch unreachable;
    defer rfile.close();

    const size: u32 = 4 * 1024 * 1024;
    const data = rfile.readToEndAlloc(allo, size) catch unreachable;
    return data;
}

fn skipComment(data: []const u8, i: usize) usize {
    var j: usize = i + 1;
    const char = data[i];
    while (true) : (j += 1) {
        if (data[j] == char) break;
    }
    return j;
}

fn getTags(
    allo: std.mem.Allocator,
    data: []const u8,
) !std.ArrayList(Tag) {
    // add simd + multiple threads
    var tags = std.ArrayList(Tag).initCapacity(allo, 1_024) catch unreachable;

    const suggested_vec_len = std.simd.suggestVectorLength(u8);
    std.debug.print("Suggested Vector Len: {}\n", .{suggested_vec_len});
    const n_threads = std.Thread.getCpuCouknt() catch 4;
    std.debug.print("Suggested # of Threads: {}\n", .{n_threads});

    var found_prolog: bool = false;

    var i: usize = 0;
    var found_open: bool = false;
    var j: usize = 0;
    while (true) : (i += 1) {
        if (i == data.len) break;
        switch (data[i]) {
            '<' => {
                if (found_open) std.log.err("On open, did not end previous tag: position: {}\n", .{i});
                const tag_type: TagType = getTagType(data, .{ .start = @truncate(i), .end = undefined });
                n_prologs += @intFromBool(tag_type == .prolog);
                if (n_prologs > 1) std.log.err("On prolog, found more than 1: position: {}\n", .{i});
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
                // skip any close tags found within a comment
                i = skipComment(data, i);
            },
            else => {},
        }
    }

    return tags;
}

// fn getTagType(data: []const u8, tag: Tag) TagType {
//     return switch (data[tag.start + 1]) {
//         '?' => .prolog,
//         '/' => .close,
//         'a'...'z', 'A'...'Z' => .open,
//         else => unreachable,
//     };
// }
//
// test "Get Tag Type" {
//     const names = [_][]const u8{ "<name>", "</name>", "<?xml>" };
//     const values = [_]TagType{ .open, .close, .prolog };
//     for (names, values) |name, value| {
//         const tag_type = getTagType(name, .{ .start = 0, .end = @truncate(name.len) });
//         try std.testing.expect(tag_type == value);
//     }
// }
//
// fn writeTags(
//     allo: std.mem.Allocator,
//     data: []const u8,
//     filename: []const u8,
//     tags: *const std.ArrayList(Tag),
// ) !void {
//     const file = try std.fs.cwd().createFile(filename, .{});
//     defer file.close();
//
//     for (tags.items) |tag| {
//         const line = try std.fmt.allocPrint(allo, "{s}\n", .{data[tag.start .. tag.end + 1]});
//         defer allo.free(line);
//         _ = file.write(line) catch unreachable;
//     }
// }
//
// inline fn printTag(data: []const u8, tag: Tag) void {
//     std.debug.print("{s}\n", .{data[tag.start .. tag.end + 1]});
// }
//
// fn printTags(data: []const u8, tags: []const Tag) void {
//     for (tags) |tag| {
//         printTag(data, tag);
//     }
// }
//
// fn printTagsByPtr(data: []const u8, tag_ptrs: []u32) void {
//     for (tag_ptrs) |tag_ptr| {
//         const tag = @as(*const Tag, @ptrFromInt(tag_ptr)).*;
//         printTag(data, tag);
//     }
// }
//
// pub const TagType = enum {
//     prolog,
//     open,
//     close,
// };
//
// const Tag = struct {
//     start: u32,
//     end: u32,
// };
//
// const Element = struct {
//     start: u16, // position inside []const Tag
//     end: u16, // position inside []const Tag
//     parent: u16, // position to elements array - if position = itself in the array, it has no parent
//     children: ?usize = null, // *std.ArrayList(u16) = null, children = positions in elements array, ptr is held as an int that points to std.ArrayList (saves some memory)
// };
//
// fn getElements(
//     allo: std.mem.Allocator,
//     data: []const u8,
//     tags: []const Tag,
// ) !std.MultiArrayList(Element) {
//     var elements = std.MultiArrayList(Element){};
//     errdefer elements.deinit(allo);
//     try elements.ensureTotalCapacity(allo, tags.len / 2);
//
//     var i: u16 = 0;
//     while (i < tags.len) : (i += 1) {
//         const tag = tags[i];
//         const tag_type = getTagType(data, tag);
//         switch (tag_type) {
//             .close => {
//                 var j: u16 = @truncate(elements.len - 1);
//                 if (j == 0) unreachable;
//
//                 const starts = elements.items(.start);
//                 const ends = elements.items(.end);
//
//                 while (true) : (j -= 1) {
//                     if (starts[j] != ends[j]) continue;
//
//                     const tag2 = tags[starts[j]];
//                     const prev_tag_type = getTagType(data, tag2);
//                     switch (prev_tag_type) {
//                         .close => continue,
//                         .prolog => unreachable,
//                         .open => {},
//                     }
//
//                     if (!tagNamesMatch(data, tag, tag2)) continue;
//
//                     ends[j] = i;
//                     break;
//                 }
//                 ends[j] = i;
//             },
//             else => { // prolog or open
//                 elements.appendAssumeCapacity(.{
//                     .start = i,
//                     .end = i,
//                     .parent = i, // null = same space as a regular ptr, less space this way
//                 });
//             },
//         }
//     }
//
//     // Identify Children
//     const starts = elements.items(.start);
//     const ends = elements.items(.end);
//     const rents = elements.items(.parent);
//     const children = elements.items(.children);
//     const len = elements.len;
//
//     i = 1;
//     while (i < len) : (i += 1) {
//         var j: u16 = i - 1;
//         while (true) : (j -= 1) {
//             if (starts[j] < starts[i] and ends[j] > ends[i]) {
//                 rents[i] = j;
//
//                 if (children[j]) |child| {
//                     var list = @as(*std.ArrayList(u16), @ptrFromInt(child)).*;
//                     try list.append(i);
//                     break;
//                 } else {
//                     var list = std.ArrayList(u16).init(allo);
//                     try list.append(i);
//                     children[j] = @intFromPtr(&list);
//                     break;
//                 }
//             }
//
//             if (j == 0) break;
//         }
//     }
//
//     return elements;
// }
//
// test "Get Elements" {
//     const data: []const u8 = "<1><2></2></1>";
//     const exp_names = [_][]const u8{ "1", "2" };
//     const exp_elem_ends = [_]Tag{
//         .{ .start = 0, .end = data.len - 1 },
//         .{ .start = 3, .end = 9 },
//     };
//
//     const allo = std.testing.allocator;
//
//     const tags = try getTags(allo, data);
//     defer tags.deinit();
//
//     const elements: std.ArrayList(Element) = try getElements(allo, data, tags);
//     defer elements.deinit();
//
//     for (elements.items, exp_names, exp_elem_ends) |element, exp_name, exp_elem_end| {
//         const elem_name = getTagName(data, element.start);
//         try std.testing.expectEqualStrings(elem_name, exp_name);
//
//         const match = tagNamesMatch(data, element.start, element.end);
//         try std.testing.expect(match);
//
//         try std.testing.expect(tags.items[element.start].start == exp_elem_end.start);
//         try std.testing.expect(tags.items[element.end].end == exp_elem_end.end);
//     }
// }
//
// fn isModified(e: Element) bool {
//     return e.start != e.end;
// }
//
// const ElementTree = struct {
//     root: ?*Element,
// };

// Notes:
// Extern Struct:
// Look for tags that start w/ type
// Parse the data
