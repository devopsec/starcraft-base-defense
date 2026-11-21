//! sbd_native: the native backend. SDL3 window + input, wgpu-native rendering, optional OpenXR,
//! with the Zig core imported directly. See engines/native/README.md for options and controls.
const std = @import("std");
const c = @import("c");
const core = @import("sbd_core");
const balance = @import("balance.zig");
const game_mod = @import("game.zig");
const input = @import("input.zig");
const gfx_mod = @import("gfx.zig");
const xr_mod = @import("xr.zig");
const smoke = @import("smoke.zig");

const T = core.types;

const Options = struct {
    smoke: bool = false,
    headless: bool = false,
    frames: ?u64 = null,
    balance_path: ?[]const u8 = null,
    xr: bool = true,
    serial: bool = false,
};

const usage =
    \\usage: sbd_native [options]
    \\  --smoke             headless scripted game; prints NATIVE SMOKE OK
    \\  --headless          run the simulation without a window (use with --frames)
    \\  --frames N          quit after N frames
    \\  --balance PATH      load balance JSON instead of the embedded data/balance.json
    \\  --no-xr             do not try to load OpenXR
    \\  --serial            step enemies on the main thread only
    \\
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const opts = parseArgs(init.arena.allocator(), init.minimal.args) catch {
        std.debug.print("{s}", .{usage});
        std.process.exit(2);
    };

    const bal = try loadBalance(gpa, io, opts.balance_path);

    if (opts.smoke) {
        smoke.run(gpa, io, bal) catch std.process.exit(1);
        try std.Io.File.stdout().writeStreamingAll(io, "NATIVE SMOKE OK\n");
        return;
    }

    const job_io: ?std.Io = if (opts.serial) null else io;
    var game = try game_mod.Game.init(gpa, bal.config, bal.weapon_range, job_io);
    defer game.deinit();

    if (opts.headless) {
        const frames = opts.frames orelse 600;
        var i: u64 = 0;
        while (i < frames) : (i += 1) game.frame(1.0 / 60.0, .{});
        std.debug.print("headless: {d} frames, score {d}, high {d}, health {d}, state {d}, enemies {d}\n", .{
            frames, game.score(), game.highScore(), game.playerHealth(), game.state(), game.enemies.items.len,
        });
        return;
    }

    try runWindowed(gpa, &game, opts);
}

fn runWindowed(gpa: std.mem.Allocator, game: *game_mod.Game, opts: Options) !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMEPAD)) return sdlFail("SDL_Init");
    defer c.SDL_Quit();

    // Save next to other per-user data (Linux: ~/.local/share/StarcraftBaseDefense/native, Windows: %APPDATA%).
    const pref = c.SDL_GetPrefPath("StarcraftBaseDefense", "native");
    defer if (pref) |p| c.SDL_free(p);
    var save_path_buf: [1024]u8 = undefined;
    const save_path: ?[:0]const u8 = if (pref) |p|
        std.fmt.bufPrintSentinel(&save_path_buf, "{s}save_v1.bin", .{std.mem.span(p)}, 0) catch null
    else
        null;
    if (save_path) |sp| loadSave(game, sp);

    const window = c.SDL_CreateWindow("Starcraft Base Defense", 1280, 720, c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse
        return sdlFail("SDL_CreateWindow");
    defer c.SDL_DestroyWindow(window);

    var pw: c_int = 0;
    var ph: c_int = 0;
    _ = c.SDL_GetWindowSizeInPixels(window, &pw, &ph);
    const gfx = try gpa.create(gfx_mod.Gfx);
    defer gpa.destroy(gfx);
    try gfx.init(window, @intCast(pw), @intCast(ph));
    defer gfx.deinit();
    std.log.info("wgpu adapter: {s}, video driver: {s}", .{ gfx.adapterName(), std.mem.span(c.SDL_GetCurrentVideoDriver().?) });

    const xr: ?*xr_mod.Xr = if (opts.xr) xr_mod.Xr.init(gpa) else null;
    defer if (xr) |x| x.deinit(gpa);
    if (xr) |x| std.log.info("OpenXR: {s} / {s} ({s})", .{ x.runtimeName(), x.systemName(), if (x.headless) "head pose + trigger" else "no session: needs XR_MND_headless" });

    var state: input.State = .{};
    var gamepad: ?*c.SDL_Gamepad = null;
    defer if (gamepad) |gp| c.SDL_CloseGamepad(gp);
    setMouseCapture(window, true);

    var last = c.SDL_GetTicksNS();
    var title_timer: f32 = 0;
    var frames: u64 = 0;
    var running = true;
    while (running) {
        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev)) {
            switch (ev.type) {
                c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => running = false,
                c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => gfx.resize(@intCast(ev.window.data1), @intCast(ev.window.data2)),
                c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => if (mapKey(ev.key.scancode)) |k| state.key(k, ev.key.down),
                c.SDL_EVENT_MOUSE_MOTION => state.mouseMotion(ev.motion.xrel, ev.motion.yrel),
                c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    if (ev.button.button == c.SDL_BUTTON_LEFT) state.key(.fire, ev.button.down);
                    if (ev.button.down and game.state() == T.State.playing) setMouseCapture(window, true);
                },
                c.SDL_EVENT_GAMEPAD_ADDED => {
                    if (gamepad == null) gamepad = c.SDL_OpenGamepad(ev.gdevice.which);
                },
                c.SDL_EVENT_GAMEPAD_REMOVED => if (gamepad) |gp| {
                    if (c.SDL_GetGamepadID(gp) == ev.gdevice.which) {
                        c.SDL_CloseGamepad(gp);
                        gamepad = null;
                    }
                },
                c.SDL_EVENT_GAMEPAD_BUTTON_DOWN, c.SDL_EVENT_GAMEPAD_BUTTON_UP => {
                    const k: ?input.Key = switch (ev.gbutton.button) {
                        c.SDL_GAMEPAD_BUTTON_START => .pause,
                        c.SDL_GAMEPAD_BUTTON_SOUTH => .restart,
                        else => null,
                    };
                    if (k) |key| state.key(key, ev.gbutton.down);
                },
                else => {},
            }
        }
        if (gamepad) |gp| {
            const ax = struct {
                fn f(g: *c.SDL_Gamepad, a: c.SDL_GamepadAxis) f32 {
                    return @as(f32, @floatFromInt(c.SDL_GetGamepadAxis(g, a))) / 32767.0;
                }
            }.f;
            state.moveStick(ax(gp, c.SDL_GAMEPAD_AXIS_LEFTX), ax(gp, c.SDL_GAMEPAD_AXIS_LEFTY));
            state.lookStick(ax(gp, c.SDL_GAMEPAD_AXIS_RIGHTX), ax(gp, c.SDL_GAMEPAD_AXIS_RIGHTY));
            state.pad_trigger = ax(gp, c.SDL_GAMEPAD_AXIS_RIGHT_TRIGGER) > 0.5;
        }

        if (xr) |x| {
            if (!x.update()) running = false;
            x.applyInput(&state);
        }

        const now = c.SDL_GetTicksNS();
        const dt: f32 = @floatCast(@as(f64, @floatFromInt(now - last)) / 1e9);
        last = now;

        const before = game.state();
        const actions = state.take(dt);
        if (actions.quit) running = false;
        game.frame(dt, actions);
        if (xr) |x| if (x.pose) |p| {
            game.player.yaw = p.yaw;
            game.player.pitch = p.pitch;
        };
        if (game.state() != before) setMouseCapture(window, game.state() == T.State.playing);
        if (game.save_dirty) {
            if (save_path) |sp| writeSave(game, sp);
            game.save_dirty = false;
        }

        _ = gfx.render(game);

        title_timer -= dt;
        if (title_timer <= 0) {
            title_timer = 0.1;
            updateTitle(window, game);
        }
        frames += 1;
        if (opts.frames) |n| if (frames >= n) {
            running = false;
        };
    }
    std.log.info("windowed run: {d} frames, {d} parallel enemy steps", .{ frames, game.stats.parallel_frames });
}

fn updateTitle(window: *c.SDL_Window, game: *const game_mod.Game) void {
    var buf: [192]u8 = undefined;
    const status: []const u8 = switch (game.state()) {
        T.State.paused => "  |  PAUSED (Esc to resume)",
        T.State.game_over => if (game.new_high_score) "  |  NEW HIGH SCORE! Enter to restart" else "  |  GAME OVER - Enter to restart",
        else => "",
    };
    const title = std.fmt.bufPrintSentinel(&buf, "Starcraft Base Defense  |  Score {d}  |  High {d}  |  Health {d}  |  Enemies {d}{s}", .{
        game.score(), game.highScore(), @max(game.playerHealth(), 0), game.enemies.items.len, status,
    }, 0) catch return;
    _ = c.SDL_SetWindowTitle(window, title.ptr);
}

fn setMouseCapture(window: *c.SDL_Window, on: bool) void {
    _ = c.SDL_SetWindowRelativeMouseMode(window, on);
}

fn mapKey(sc: c.SDL_Scancode) ?input.Key {
    return switch (sc) {
        c.SDL_SCANCODE_W, c.SDL_SCANCODE_UP => .forward,
        c.SDL_SCANCODE_S, c.SDL_SCANCODE_DOWN => .back,
        c.SDL_SCANCODE_A, c.SDL_SCANCODE_LEFT => .left,
        c.SDL_SCANCODE_D, c.SDL_SCANCODE_RIGHT => .right,
        c.SDL_SCANCODE_SPACE => .fire,
        c.SDL_SCANCODE_ESCAPE, c.SDL_SCANCODE_P => .pause,
        c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_KP_ENTER => .restart,
        c.SDL_SCANCODE_F10 => .quit,
        else => null,
    };
}

fn loadSave(game: *game_mod.Game, path: [:0]const u8) void {
    var len: usize = 0;
    const data = c.SDL_LoadFile(path.ptr, &len) orelse return; // no save yet
    defer c.SDL_free(data);
    const bytes: [*]const u8 = @ptrCast(data);
    const r = game.loadSave(bytes[0..len]);
    if (r < 0) std.log.warn("ignoring corrupt save {s} (error {d})", .{ path, r });
}

fn writeSave(game: *const game_mod.Game, path: [:0]const u8) void {
    var buf: [64]u8 = undefined;
    const n = game.writeSave(&buf);
    if (!c.SDL_SaveFile(path.ptr, &buf, n)) std.log.warn("could not write save {s}: {s}", .{ path, std.mem.span(c.SDL_GetError()) });
}

fn loadBalance(gpa: std.mem.Allocator, io: std.Io, path: ?[]const u8) !balance.Balance {
    const p = path orelse return balance.parse(gpa, balance.embedded);
    const text = try std.Io.Dir.cwd().readFileAlloc(io, p, gpa, .limited(1 << 20));
    defer gpa.free(text);
    return balance.parse(gpa, text);
}

fn parseArgs(arena: std.mem.Allocator, args: std.process.Args) !Options {
    const argv = try args.toSlice(arena);
    var o: Options = .{};
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--smoke")) {
            o.smoke = true;
        } else if (std.mem.eql(u8, a, "--headless")) {
            o.headless = true;
        } else if (std.mem.eql(u8, a, "--no-xr")) {
            o.xr = false;
        } else if (std.mem.eql(u8, a, "--serial")) {
            o.serial = true;
        } else if (std.mem.eql(u8, a, "--frames") and i + 1 < argv.len) {
            i += 1;
            o.frames = try std.fmt.parseInt(u64, argv[i], 10);
        } else if (std.mem.eql(u8, a, "--balance") and i + 1 < argv.len) {
            i += 1;
            o.balance_path = argv[i];
        } else return error.BadArgs;
    }
    return o;
}

fn sdlFail(what: []const u8) error{Sdl} {
    std.log.err("{s}: {s}", .{ what, std.mem.span(c.SDL_GetError()) });
    return error.Sdl;
}

test {
    _ = xr_mod;
    _ = gfx_mod;
}
