const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

// Zig 0.16's default debug Io is std.Io.Threaded, which currently fails to
// compile for wasm32-emscripten. On emscripten route std.debug through a
// no-op Io and trap on panic; native keeps default behavior.
pub const std_options_debug_io: std.Io = if (builtin.os.tag == .emscripten)
    std.Io.failing
else
    std.Io.Threaded.global_single_threaded.io();
pub const panic = if (builtin.os.tag == .emscripten) std.debug.no_panic else std.debug.FullPanic(std.debug.defaultPanic);

extern fn emscripten_set_main_loop_arg(
    func: *const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
    fps: c_int,
    simulate_infinite_loop: c_int,
) void;

const screenWidth: i32 = 800;
const screenHeight: i32 = 600;
const title = "Zig Invaders";

var game_state: GameState = undefined;

const GameState = struct {
    player: Player,
    timer: Timer,

    fn init() GameState {
        const playerWidth: f32 = 50;
        const playerHeight: f32 = 30;

        return .{
            .player = Player.init(
                @as(f32, @floatFromInt(screenWidth)) / 2 - playerWidth / 2,
                @as(f32, @floatFromInt(screenHeight)) - 60,
                playerWidth,
                playerHeight,
            ),

            .timer = Timer.init(),
        };
    }

    fn update(self: *@This()) void {
        self.player.update();
    }

    fn draw(self: *@This()) void {
        self.player.draw();
        self.timer.draw();
        rl.drawText(title, 300, 250, 40, rl.Color.green);
    }
};

const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    fn intersects(self: Rectangle, other: Rectangle) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }
};

const Player = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,

    fn init(x: f32, y: f32, w: f32, h: f32) @This() {
        return .{
            .position_x = x,
            .position_y = y,
            .width = w,
            .height = h,
            .speed = 5.0,
        };
    }

    fn update(self: *@This()) void {
        if (rl.isKeyDown(.right) and self.position_x + self.width < @as(f32, @floatFromInt(rl.getScreenWidth()))) {
            self.position_x += self.speed;
        }
        if (rl.isKeyDown(.left) and self.position_x > 0) {
            self.position_x -= self.speed;
        }
    }

    fn draw(self: @This()) void {
        rl.drawRectangle(
            @intFromFloat(self.position_x),
            @intFromFloat(self.position_y),
            @intFromFloat(self.width),
            @intFromFloat(self.height),
            rl.Color.blue,
        );
    }
};

const Timer = struct {
    start_ms: u64,

    fn init() @This() {
        return .{
            .start_ms = get_now_ms(),
        };
    }

    fn get_now_ms() u64 {
        return @intFromFloat(rl.getTime() * 1000.0);
    }

    fn get_elapsed_ms(self: @This()) u64 {
        return get_now_ms() - self.start_ms;
    }

    fn get_time_parts(self: @This()) struct { u64, u64 } {
        const total = self.get_elapsed_ms() / 1000;
        return .{ total / 60, total % 60 };
    }

    fn draw(self: *Timer) void {
        const time = self.get_time_parts();

        var buffer: [6]u8 = undefined;

        const text = std.fmt.bufPrintZ(
            &buffer,
            "{d:0>2}:{d:0>2}",
            .{ time[0], time[1] },
        ) catch "00:00";

        rl.drawText(text, screenWidth - 80, 20, 20, rl.Color.yellow);
    }
};

fn updateDrawFrame(arg: ?*anyopaque) callconv(.c) void {
    const game = @as(*GameState, @ptrCast(@alignCast(arg.?)));

    game.update();

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(rl.Color.black);

    game.draw();
}

pub fn main() !void {
    rl.initWindow(800, 600, title);
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    game_state = GameState.init();

    if (builtin.os.tag == .emscripten) {
        emscripten_set_main_loop_arg(updateDrawFrame, &game_state, 0, 1);
    } else {
        while (!rl.windowShouldClose()) {
            updateDrawFrame(&game_state);
        }
    }
}
