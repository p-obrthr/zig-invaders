const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

// Zig 0.16's default debug Io is std.Io.Threaded, which currently fails to compile for wasm32-emscripten. On emscripten route std.debug through a
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
const maxEnemyBullets: i32 = 20;

const invaderRows: i32 = 5;
const invaderCols: i32 = 11;

var game_state: GameState = undefined;

const GameState = struct {
    player: Player,
    bullets: Bullets,
    enemyBullets: EnemyBullets,
    invaders: Invaders,
    timer: Timer,
    score: Score,

    fn init() GameState {
        return .{
            .player = Player.init(),
            .bullets = Bullets.init(),
            .enemyBullets = EnemyBullets.init(),
            .invaders = Invaders.init(),
            .timer = Timer.init(),
            .score = Score.init(),
        };
    }

    fn update(self: *@This()) void {
        self.player.update();
        self.bullets.update(self.player);
        self.bullets.checkCollision(&self.invaders, &self.score);
        self.enemyBullets.update();
        self.enemyBullets.shoot(&self.invaders);
        self.invaders.update();
    }

    fn draw(self: *@This()) void {
        self.player.draw();
        self.bullets.draw();
        self.enemyBullets.draw();
        self.invaders.draw();
        self.timer.draw();
        self.score.draw();
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

const Score = struct {
    value: i32,

    fn init() Score {
        return .{
            .value = 0,
        };
    }

    fn draw(self: @This()) void {
        const scoreText: [:0]const u8 = rl.textFormat("Score: %d", .{self.value});
        rl.drawText(scoreText, 20, screenHeight - 20, 20, rl.Color.white);
    }

    fn increment(self: *@This()) void {
        self.value += 10;
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
        for (&bullets) |*bullet| {
            bullet.* = Bullet.init();
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

    fn checkCollision(
        self: *@This(),
        invaders: *Invaders,
        score: *Score,
    ) void {
        for (&self.bullets) |*bullet| {
            if (bullet.active and invaders.checkCollision(bullet)) {
                score.increment();
            }
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

    pub fn init() @This() {
        return .{
            .position_x = 0,
            .position_y = 0,
            .width = 4.0,
            .height = 10.0,
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

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const Invaders = struct {
    invaders: [invaderRows][invaderCols]Invader,
    speed: f32,
    moveDelay: i32,
    direction: f32,
    moveTimer: i32,
    dropDistance: f32,

    fn init() @This() {
        var invaders: [invaderRows][invaderCols]Invader = undefined;

        const startX: f32 = 100.0;
        const startY: f32 = 50.0;
        const spacingX = 60.0;
        const spacingY = 40.0;

        for (&invaders, 0..) |*row, i| {
            for (row, 0..) |*invader, j| {
                const x: f32 = startX + @as(f32, @floatFromInt(j)) * spacingX;
                const y: f32 = startY + @as(f32, @floatFromInt(i)) * spacingY;
                invader.* = Invader.init(x, y);
            }
        }

        return .{
            .invaders = invaders,
            .speed = 5.0,
            .moveDelay = 30,
            .direction = 1.0,
            .moveTimer = 0,
            .dropDistance = 20.0,
        };
    }

    fn update(self: *@This()) void {
        self.moveTimer += 1;
        if (self.moveTimer >= self.moveDelay) {
            self.moveTimer = 0;

            var hitEdge = false;

            for (&self.invaders) |*row| {
                for (row) |*invader| {
                    if (invader.active) {
                        const nextX = invader.position_x + (self.speed * self.direction);
                        if (nextX < 0 or nextX + invader.width > @as(f32, @floatFromInt(screenWidth))) {
                            hitEdge = true;
                            break;
                        }
                    }
                }
                if (hitEdge) {
                    break;
                }
            }

            if (hitEdge) {
                self.direction *= -1.0;
                for (&self.invaders) |*row| {
                    for (row) |*invader| {
                        invader.update(0, self.dropDistance);
                    }
                }
            } else {
                for (&self.invaders) |*row| {
                    for (row) |*invader| {
                        invader.update(self.speed * self.direction, 0);
                    }
                }
            }
        }
    }

    fn draw(self: *@This()) void {
        for (&self.invaders) |*row| {
            for (row) |*invader| {
                invader.draw();
            }
        }
    }

    fn checkCollision(self: *@This(), bullet: *Bullet) bool {
        for (&self.invaders) |*row| {
            for (row) |*invader| {
                if (invader.active and bullet.getRect().intersects(invader.getRect())) {
                    bullet.active = false;
                    invader.active = false;
                    return true;
                }
            }
        }
        return false;
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
        return .{
            .position_x = position_x,
            .position_y = position_y,
            .width = 40.0,
            .height = 30.0,
            .speed = 5.0,
            .active = true,
        };
    }

    fn update(self: *@This(), dx: f32, dy: f32) void {
        self.position_x += dx;
        self.position_y += dy;
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

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const EnemyBullets = struct {
    enemyBullets: [maxEnemyBullets]EnemyBullet,
    enemyShootDelay: i32,
    enemyShootChance: i32,
    enemyShootTimer: i32,

    fn init() @This() {
        var enemyBullets: [maxEnemyBullets]EnemyBullet = undefined;

        for (&enemyBullets) |*enemyBullet| {
            enemyBullet.* = EnemyBullet.init();
        }

        return .{
            .enemyBullets = enemyBullets,
            .enemyShootDelay = 60,
            .enemyShootChance = 5,
            .enemyShootTimer = 0,
        };
    }

    fn update(self: *@This()) void {
        for (&self.enemyBullets) |*bullet| {
            bullet.update();
        }
    }

    fn shoot(self: *@This(), invaders: *Invaders) void {
        self.enemyShootTimer += 1;
        if (self.enemyShootTimer >= self.enemyShootDelay) {
            self.enemyShootTimer = 0;
            for (&invaders.invaders) |*row| {
                for (row) |*invader| {
                    if (invader.active and rl.getRandomValue(0, 100) < self.enemyShootChance) {
                        for (&self.enemyBullets) |*bullet| {
                            if (!bullet.active) {
                                bullet.position_x = invader.position_x + invader.width / 2 - bullet.width / 2;
                                bullet.position_y = invader.position_y + invader.height;
                                bullet.active = true;
                                break;
                            }
                        }
                        break;
                    }
                }
            }
        }
    }

    fn draw(self: *@This()) void {
        for (&self.enemyBullets) |*bullet| {
            bullet.draw();
        }
    }
};

const EnemyBullet = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    active: bool,

    fn init() @This() {
        return .{
            .position_x = 0,
            .position_y = 0,
            .width = 4.0,
            .height = 10.0,
            .speed = 5.0,
            .active = false,
        };
    }

    fn update(self: *@This()) void {
        if (self.active) {
            self.position_y += self.speed;
            if (self.position_y > @as(f32, @floatFromInt(screenHeight))) {
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
                rl.Color.yellow,
            );
        }
    }

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
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
