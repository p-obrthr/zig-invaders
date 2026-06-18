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
const maxBullets: i32 = 10;

const invaderRows: i32 = 5;
const invaderCols: i32 = 11;

var game_state: GameState = undefined;

const GameState = struct {
    player: Player,
    bullets: Bullets,
    invaders: Invaders,
    timer: Timer,

    fn init() GameState {
        return .{
            .player = Player.init(),
            .bullets = Bullets.init(),
            .invaders = Invaders.init(),
            .timer = Timer.init(),
        };
    }

    fn update(self: *@This()) void {
        self.player.update();
        self.bullets.update(self.player);
    }

    fn draw(self: *@This()) void {
        self.player.draw();
        self.bullets.draw();
        self.invaders.draw();
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

    fn init() @This() {
        const playerWidth: f32 = 50;
        const playerHeight: f32 = 30;
        const x = @as(f32, @floatFromInt(screenWidth)) / 2 - playerWidth / 2;
        const y = @as(f32, @floatFromInt(screenHeight)) - 60;

        return .{
            .position_x = x,
            .position_y = y,
            .width = playerWidth,
            .height = playerHeight,
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

const Bullets = struct {
    bullets: [maxBullets]Bullet,

    fn init() @This() {
        var bullets: [maxBullets]Bullet = undefined;
        const bulletWidth: f32 = 4.0;
        const bulletHeight: f32 = 10.0;

        for (&bullets) |*bullet| {
            bullet.* = Bullet.init(0, 0, bulletWidth, bulletHeight);
        }

        return .{ .bullets = bullets };
    }

    fn update(self: *@This(), player: Player) void {
        if (rl.isKeyPressed(.space)) {
            for (&self.bullets) |*bullet| {
                if (bullet.spawn(player)) {
                    break;
                }
            }
        }

        for (&self.bullets) |*bullet| {
            bullet.update();
        }
    }

    fn draw(self: *@This()) void {
        for (&self.bullets) |*bullet| {
            bullet.draw();
        }
    }
};

const Bullet = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    active: bool,

    pub fn init(
        position_x: f32,
        position_y: f32,
        width: f32,
        height: f32,
    ) @This() {
        return .{
            .position_x = position_x,
            .position_y = position_y,
            .width = width,
            .height = height,
            .speed = 10.0,
            .active = false,
        };
    }

    fn spawn(self: *@This(), player: Player) bool {
        if (!self.active) {
            self.position_x = player.position_x + player.width / 2 - self.width / 2;
            self.position_y = player.position_y;
            self.active = true;
            return true;
        }
        return false;
    }

    fn update(self: *@This()) void {
        if (self.active) {
            self.position_y -= self.speed;
            if (self.position_y < 0) {
                self.active = false;
            }
        }
    }

    fn draw(self: @This()) void {
        if (self.active) {
            rl.drawRectangle(
                @intFromFloat(self.position_x),
                @intFromFloat(self.position_y),
                @intFromFloat(self.width),
                @intFromFloat(self.height),
                rl.Color.red,
            );
        }
    }
};

const Invaders = struct {
    invaders: [invaderRows][invaderCols]Invader,

    fn init() @This() {
        var invaders: [invaderRows][invaderCols]Invader = undefined;

        const invaderStartX: f32 = 100.0;
        const invaderStartY: f32 = 50.0;
        const invaderSpacingX = 60.0;
        const invaderSpacingY = 40.0;

        for (&invaders, 0..) |*row, i| {
            for (row, 0..) |*invader, j| {
                const x: f32 = invaderStartX + @as(f32, @floatFromInt(j)) * invaderSpacingX;
                const y: f32 = invaderStartY + @as(f32, @floatFromInt(i)) * invaderSpacingY;
                invader.* = Invader.init(x, y);
            }
        }

        return .{ .invaders = invaders };
    }

    fn draw(self: *@This()) void {
        for (&self.invaders) |*row| {
            for (row) |*invader| {
                invader.draw();
            }
        }
    }
};

const Invader = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    active: bool,

    fn init(position_x: f32, position_y: f32) @This() {
        const invaderWidth = 40.0;
        const invaderHeight = 30.0;

        return .{
            .position_x = position_x,
            .position_y = position_y,
            .width = invaderWidth,
            .height = invaderHeight,
            .speed = 5.0,
            .active = true,
        };
    }

    fn draw(self: @This()) void {
        if (self.active) {
            rl.drawRectangle(
                @intFromFloat(self.position_x),
                @intFromFloat(self.position_y),
                @intFromFloat(self.width),
                @intFromFloat(self.height),
                rl.Color.green,
            );
        }
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
