//! Unicode bidirectional helpers used by the RTL integration.

const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const c = if (build_options.fribidi) @cImport({
    @cInclude("fribidi.h");
}) else struct {};

pub const Level = u8;

pub const AnalysisResult = struct {
    levels: []Level,
    paragraph_level: Level,
    allocator: Allocator,

    pub fn deinit(self: *AnalysisResult) void {
        self.allocator.free(self.levels);
    }
};

pub const Script = enum {
    Latin,
    Arabic,
    Hebrew,
    Devanagari,
    Thai,
    Han,
    Cyrillic,
    Greek,
    Common,
};

pub fn detectScript(codepoint: u32) Script {
    if (codepoint >= 0x0600 and codepoint <= 0x06FF) return .Arabic;
    if (codepoint >= 0x0750 and codepoint <= 0x077F) return .Arabic;
    if (codepoint >= 0x08A0 and codepoint <= 0x08FF) return .Arabic;
    if (codepoint >= 0xFB50 and codepoint <= 0xFDFF) return .Arabic;
    if (codepoint >= 0xFE70 and codepoint <= 0xFEFF) return .Arabic;

    if (codepoint >= 0x0590 and codepoint <= 0x05FF) return .Hebrew;
    if (codepoint >= 0x0000 and codepoint <= 0x024F) return .Latin;
    if (codepoint >= 0x0400 and codepoint <= 0x04FF) return .Cyrillic;
    if (codepoint >= 0x0370 and codepoint <= 0x03FF) return .Greek;
    if (codepoint >= 0x4E00 and codepoint <= 0x9FFF) return .Han;
    if (codepoint >= 0x0900 and codepoint <= 0x097F) return .Devanagari;
    if (codepoint >= 0x0E00 and codepoint <= 0x0E7F) return .Thai;

    return .Common;
}

pub fn isComplexScript(script: Script) bool {
    return switch (script) {
        .Arabic, .Hebrew, .Devanagari, .Thai => true,
        else => false,
    };
}

pub fn isRtlScript(script: Script) bool {
    return switch (script) {
        .Arabic, .Hebrew => true,
        else => false,
    };
}

pub fn isStrongRtlCodepoint(cp: u32) ?bool {
    if (comptime build_options.fribidi) {
        const bidi_type = c.fribidi_get_bidi_type(cp);
        if (c.FRIBIDI_IS_STRONG(bidi_type) != 0) {
            return (bidi_type & c.FRIBIDI_MASK_RTL) != 0;
        }

        return null;
    }

    return switch (detectScript(cp)) {
        .Arabic, .Hebrew => true,
        .Latin, .Cyrillic, .Greek, .Devanagari, .Thai, .Han => false,
        .Common => null,
    };
}

pub fn analyzeBidi(allocator: Allocator, text: []const u8) !AnalysisResult {
    var codepoints = try std.ArrayList(u32).initCapacity(allocator, text.len);
    defer codepoints.deinit(allocator);

    var utf8_view = try std.unicode.Utf8View.init(text);
    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |cp| {
        try codepoints.append(allocator, cp);
    }

    return analyzeBidiCodepoints(allocator, codepoints.items);
}

pub fn analyzeBidiCodepoints(
    allocator: Allocator,
    codepoints: []const u32,
) !AnalysisResult {
    if (comptime !build_options.fribidi) return analyzeFallback(allocator, codepoints);
    if (codepoints.len == 0) {
        return .{
            .levels = try allocator.alloc(Level, 0),
            .paragraph_level = 0,
            .allocator = allocator,
        };
    }

    const bidi_types = try allocator.alloc(c.FriBidiCharType, codepoints.len);
    defer allocator.free(bidi_types);

    const bracket_types = try allocator.alloc(c.FriBidiBracketType, codepoints.len);
    defer allocator.free(bracket_types);

    const levels = try allocator.alloc(c.FriBidiLevel, codepoints.len);
    defer allocator.free(levels);

    c.fribidi_get_bidi_types(
        codepoints.ptr,
        @intCast(codepoints.len),
        bidi_types.ptr,
    );
    c.fribidi_get_bracket_types(
        codepoints.ptr,
        @intCast(codepoints.len),
        bidi_types.ptr,
        bracket_types.ptr,
    );

    // Let FriBidi resolve the paragraph direction from the first strong
    // character (UBA P2/P3). Hardcoding LTR made Arabic-first lines use
    // LTR paragraph order, so full sentences with Arabic + English were
    // laid out as left-to-right blocks instead of RTL paragraphs.
    var paragraph_dir: c.FriBidiParType = c.FRIBIDI_PAR_ON;
    _ = c.fribidi_get_par_embedding_levels_ex(
        bidi_types.ptr,
        bracket_types.ptr,
        @intCast(codepoints.len),
        &paragraph_dir,
        levels.ptr,
    );

    const result_levels = try allocator.alloc(Level, codepoints.len);
    errdefer allocator.free(result_levels);
    for (levels, 0..) |level, i| result_levels[i] = @intCast(level);

    return .{
        .levels = result_levels,
        .paragraph_level = if (c.FRIBIDI_IS_RTL(paragraph_dir) != 0) 1 else 0,
        .allocator = allocator,
    };
}

pub fn reorderVisual(
    allocator: Allocator,
    analysis: *const AnalysisResult,
) ![]u32 {
    if (comptime !build_options.fribidi) {
        return identityMap(allocator, analysis.levels.len);
    }
    if (analysis.levels.len == 0) return identityMap(allocator, 0);

    const bidi_types = try allocator.alloc(c.FriBidiCharType, analysis.levels.len);
    defer allocator.free(bidi_types);

    const levels = try allocator.alloc(c.FriBidiLevel, analysis.levels.len);
    defer allocator.free(levels);
    for (analysis.levels, 0..) |level, i| levels[i] = @intCast(level);

    const map = try allocator.alloc(c.FriBidiStrIndex, analysis.levels.len);
    defer allocator.free(map);
    for (map, 0..) |*entry, i| entry.* = @intCast(i);

    const base_dir: c.FriBidiParType = if (analysis.paragraph_level % 2 == 1)
        c.FRIBIDI_PAR_RTL
    else
        c.FRIBIDI_PAR_LTR;

    _ = c.fribidi_reorder_line(
        c.FRIBIDI_FLAGS_DEFAULT | c.FRIBIDI_FLAGS_ARABIC,
        bidi_types.ptr,
        @intCast(analysis.levels.len),
        0,
        base_dir,
        levels.ptr,
        null,
        map.ptr,
    );

    const logical_to_visual = try allocator.alloc(u32, analysis.levels.len);
    errdefer allocator.free(logical_to_visual);
    for (map, 0..) |logical_index, visual_index| {
        logical_to_visual[@intCast(logical_index)] = @intCast(visual_index);
    }

    return logical_to_visual;
}

pub fn reorderVisualEx(
    allocator: Allocator,
    text: []const u8,
    analysis: *const AnalysisResult,
) ![]u32 {
    var codepoints = try std.ArrayList(u32).initCapacity(allocator, text.len);
    defer codepoints.deinit(allocator);

    var utf8_view = try std.unicode.Utf8View.init(text);
    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |cp| {
        try codepoints.append(allocator, cp);
    }

    return reorderVisualCodepoints(allocator, codepoints.items, analysis);
}

pub fn reorderVisualCodepoints(
    allocator: Allocator,
    codepoints: []const u32,
    analysis: *const AnalysisResult,
) ![]u32 {
    if (comptime !build_options.fribidi) {
        _ = analysis.paragraph_level;
        return identityMap(allocator, codepoints.len);
    }
    if (codepoints.len == 0) return identityMap(allocator, 0);

    // Keep any leading LTR prefix (line numbers, prompts, labels such as
    // "CONTROL:") at the left edge. Everything after the first RTL character
    // is analysed as a forced RTL paragraph so mixed Arabic/English sentences
    // are always read right-to-left, even when they start with Latin text.
    var prefix_len: usize = 0;
    while (prefix_len < codepoints.len) : (prefix_len += 1) {
        if (isStrongRtlCodepoint(codepoints[prefix_len]) orelse false) break;
    }
    if (prefix_len == codepoints.len) {
        // No RTL character: an LTR row needs no visual reordering.
        return identityMap(allocator, codepoints.len);
    }

    const suffix = codepoints[prefix_len..];

    const bidi_types = try allocator.alloc(c.FriBidiCharType, suffix.len);
    defer allocator.free(bidi_types);
    c.fribidi_get_bidi_types(suffix.ptr, @intCast(suffix.len), bidi_types.ptr);

    const bracket_types = try allocator.alloc(c.FriBidiBracketType, suffix.len);
    defer allocator.free(bracket_types);
    c.fribidi_get_bracket_types(
        suffix.ptr,
        @intCast(suffix.len),
        bidi_types.ptr,
        bracket_types.ptr,
    );

    const levels = try allocator.alloc(c.FriBidiLevel, suffix.len);
    defer allocator.free(levels);

    var paragraph_dir: c.FriBidiParType = c.FRIBIDI_PAR_RTL;
    _ = c.fribidi_get_par_embedding_levels_ex(
        bidi_types.ptr,
        bracket_types.ptr,
        @intCast(suffix.len),
        &paragraph_dir,
        levels.ptr,
    );

    // FriBidi writes map[visual] = logical; invert below for the renderer.
    const map = try allocator.alloc(c.FriBidiStrIndex, suffix.len);
    defer allocator.free(map);
    for (map, 0..) |*entry, i| entry.* = @intCast(i);

    _ = c.fribidi_reorder_line(
        c.FRIBIDI_FLAGS_DEFAULT | c.FRIBIDI_FLAGS_ARABIC,
        bidi_types.ptr,
        @intCast(suffix.len),
        0,
        c.FRIBIDI_PAR_RTL,
        levels.ptr,
        null,
        map.ptr,
    );

    const logical_to_visual = try allocator.alloc(u32, codepoints.len);
    errdefer allocator.free(logical_to_visual);
    for (0..prefix_len) |i| logical_to_visual[i] = @intCast(i);
    for (map, 0..) |logical_index, visual_index| {
        logical_to_visual[prefix_len + @as(usize, @intCast(logical_index))] =
            @intCast(prefix_len + @as(usize, @intCast(visual_index)));
    }

    return logical_to_visual;
}

pub fn getBaseDirection(text: []const u8) !Level {
    var utf8_view = try std.unicode.Utf8View.init(text);
    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (isStrongRtlCodepoint(cp)) |rtl| return if (rtl) 1 else 0;
    }

    return 0;
}

fn analyzeFallback(allocator: Allocator, codepoints: []const u32) !AnalysisResult {
    // Limited fallback: assigns levels based on first strong directional character.
    // Does not implement full Unicode Bidirectional Algorithm (no bracket pairs,
    // no isolated glyph handling, no mirroring). Sufficient for basic RTL detection
    // but will produce incorrect results for complex scenarios (nested embeddings,
    // numbers, paired punctuation). When FriBidi is available, it is used instead.
    const levels = try allocator.alloc(Level, codepoints.len);
    errdefer allocator.free(levels);

    var paragraph_level: Level = 0;
    var saw_direction = false;
    for (codepoints) |cp| {
        if (isStrongRtlCodepoint(cp)) |rtl| {
            paragraph_level = if (rtl) 1 else 0;
            saw_direction = true;
            break;
        }
    }

    for (codepoints, 0..) |cp, i| {
        levels[i] = if (isStrongRtlCodepoint(cp)) |rtl|
            if (rtl) 1 else 0
        else if (saw_direction)
            paragraph_level
        else
            0;
    }

    return .{
        .levels = levels,
        .paragraph_level = paragraph_level,
        .allocator = allocator,
    };
}

fn identityMap(allocator: Allocator, len: usize) ![]u32 {
    const map = try allocator.alloc(u32, len);
    errdefer allocator.free(map);
    for (map, 0..) |*entry, i| entry.* = @intCast(i);
    return map;
}

test "detect script: arabic" {
    try std.testing.expectEqual(Script.Arabic, detectScript(0x0628));
}

test "detect script: hebrew" {
    try std.testing.expectEqual(Script.Hebrew, detectScript(0x05D0));
}

test "detect script: latin" {
    try std.testing.expectEqual(Script.Latin, detectScript('A'));
}

test "get base direction: arabic" {
    const text = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7";
    try std.testing.expectEqual(@as(Level, 1), try getBaseDirection(text));
}

test "get base direction: latin" {
    try std.testing.expectEqual(@as(Level, 0), try getBaseDirection("hello"));
}

test "analyze bidi: latin text" {
    var result = try analyzeBidi(std.testing.allocator, "hello");
    defer result.deinit();

    try std.testing.expectEqual(@as(Level, 0), result.paragraph_level);
    try std.testing.expectEqual(@as(usize, 5), result.levels.len);
}

test "analyze bidi: arabic text" {
    const text = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7";
    var result = try analyzeBidi(std.testing.allocator, text);
    defer result.deinit();

    try std.testing.expectEqual(@as(Level, 1), result.paragraph_level);
    try std.testing.expectEqual(@as(usize, 5), result.levels.len);
}

fn testCodepoints(allocator: Allocator, text: []const u8) ![]u32 {
    var list = std.ArrayList(u32).init(allocator);
    errdefer list.deinit(allocator);
    var view = try std.unicode.Utf8View.init(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| try list.append(allocator, cp);
    return list.toOwnedSlice(allocator);
}

test "reorder: latin prefix stays left, arabic suffix is RTL" {
    // "1: أنا" — the number and colon must stay at the left, the Arabic
    // word is laid out right-to-left after the prefix.
    const cps = try testCodepoints(std.testing.allocator, "1: \xd9\xa3\xd9\x86\xd8\xa7");
    defer std.testing.allocator.free(cps);
    var analysis = try analyzeBidiCodepoints(std.testing.allocator, cps);
    defer analysis.deinit();

    const map = try reorderVisualCodepoints(std.testing.allocator, cps, &analysis);
    defer std.testing.allocator.free(map);

    try std.testing.expectEqual(@as(u32, 0), map[0]);
    try std.testing.expectEqual(@as(u32, 1), map[1]);
    try std.testing.expectEqual(@as(u32, 2), map[2]);
    try std.testing.expectEqual(@as(u32, 5), map[3]);
    try std.testing.expectEqual(@as(u32, 4), map[4]);
    try std.testing.expectEqual(@as(u32, 3), map[5]);
}

test "reorder: ltr-only row is identity" {
    const cps = try testCodepoints(std.testing.allocator, "CONTROL: hello");
    defer std.testing.allocator.free(cps);
    var analysis = try analyzeBidiCodepoints(std.testing.allocator, cps);
    defer analysis.deinit();

    const map = try reorderVisualCodepoints(std.testing.allocator, cps, &analysis);
    defer std.testing.allocator.free(map);

    for (cps, 0..) |_, i| try std.testing.expectEqual(@as(u32, @intCast(i)), map[i]);
}
