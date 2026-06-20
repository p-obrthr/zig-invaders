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

var game: Game = undefined;

const Game = struct {
    view: View,

    fn init() @This() {
        return .{
            .view = View{ .run = Run.init() },
        };
    }

    fn cycle(self: *@This()) void {
        self.update();
        self.draw();
    }

    fn update(self: *@This()) void {
        switch (self.view) {
            inline else => |*s| {
                if (s.update()) |new| {
                    self.view = new;
                }
            },
        }
    }

    fn draw(self: *@This()) void {
        switch (self.view) {
            inline else => |*s| s.draw(),
        }
    }
};

const View = union(enum) {
    run: Run,
    gameOver: GameOver,
};

const Run = struct {
    player: Player,
    bullets: Bullets,
    enemyBullets: EnemyBullets,
    invaders: Invaders,
    timer: Timer,
    score: Score,

    fn init() @This() {
        return .{
            .player = Player.init(),
            .bullets = Bullets.init(),
            .enemyBullets = EnemyBullets.init(),
            .invaders = Invaders.init(),
            .timer = Timer.init(),
            .score = Score.init(),
        };
    }

    fn update(self: *@This()) ?View {
        self.player.update();
        self.bullets.update(self.player);

        const hitCount = self.bullets.checkCollision(&self.invaders);
        if (hitCount > 0) {
            self.score.incrementByCount(hitCount);
        }

        self.enemyBullets.update();
        self.enemyBullets.shoot(self.invaders);
        self.invaders.update();

        if (self.enemyBullets.checkHit(self.player) and self.player.getHittedAndReturnIsDead()) {
            return View{
                .gameOver = GameOver.init(self.score.total, self.timer.get_time_parts()),
            };
        }

        self.timer.update();

        return null;
    }

    fn draw(self: @This()) void {
        self.player.draw();
        self.bullets.draw();
        self.enemyBullets.draw();
        self.invaders.draw();
        self.timer.draw();
        self.drawStatus();
    }

    fn drawStatus(self: @This()) void {
        const scoreText: [:0]const u8 = rl.textFormat("Score: %d, Lives: %d", .{ self.score.total, self.player.lives });
        rl.drawText(scoreText, 20, screenHeight - 20, 20, rl.Color.white);
    }

    fn view(self: *@This()) void {
        self.View.update();
        self.View.draw();
    }
};

const GameOver = struct {
    score: i32,
    time: [8:0]u8,

    fn init(score: i32, timeParts: struct { u64, u64 }) @This() {
        var buffer: [8:0]u8 = std.mem.zeroes([8:0]u8);

        writeDisplayTimeIntoBuffer(&buffer, timeParts);
        return .{
            .score = score,
            .time = buffer,
        };
    }

    fn update(_: @This()) ?View {
        if (rl.isKeyPressed(.enter)) {
            return View{ .run = Run.init() };
        }
        return null;
    }

    fn draw(self: @This()) void {
        rl.drawText("GAME OVER", 270, 250, 40, rl.Color.red);
        const scoreText = rl.textFormat(
            "Final Score: %d with time Time: %s",
            .{
                self.score,
                &self.time,
            },
        );
        rl.drawText(scoreText, 100, 310, 30, rl.Color.white);
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
    total: i32,
    value: i32,

    fn init() Score {
        return .{
            .total = 0,
            .value = 10,
        };
    }

    fn incrementByCount(self: *@This(), count: i32) void {
        self.total += self.value * count;
    }
};

const Player = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    lives: i32,

    fn init() @This() {
        const playerWidth: f32 = 50;
        const playerHeight: f32 = 30;

        return .{
            .position_x = @as(f32, @floatFromInt(screenWidth)) / 2 - playerWidth / 2,
            .position_y = @as(f32, @floatFromInt(screenHeight)) - 60,
            .width = playerWidth,
            .height = playerHeight,
            .speed = 5.0,
            .lives = 3,
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

    fn getHittedAndReturnIsDead(self: *@This()) bool {
        self.decrementLive();
        self.reduceSize();

        if (self.lives == 0) {
            return true;
        }
        return false;
    }

    fn reduceSize(self: *@This()) void {
        self.width = self.width * 0.66;
        self.height = self.height * 0.66;
    }

    fn decrementLive(self: *@This()) void {
        self.lives -= 1;
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

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
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

    fn draw(self: @This()) void {
        for (self.bullets) |bullet| {
            bullet.draw();
        }
    }

    fn checkCollision(
        self: *@This(),
        invaders: *Invaders,
    ) i32 {
        var count: i32 = 0;

        for (&self.bullets) |*bullet| {
            if (bullet.active and invaders.checkCollision(bullet)) {
                count += 1;
            }
        }

        return count;
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

    fn draw(self: @This()) void {
        for (self.invaders) |row| {
            for (row) |invader| {
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

    fn checkHit(self: *@This(), player: Player) bool {
        for (&self.enemyBullets) |*bullet| {
            if (bullet.active) {
                if (bullet.getRect().intersects(player.getRect())) {
                    bullet.active = false;
                    return true;
                }
            }
        }
        return false;
    }

    fn shoot(self: *@This(), invaders: Invaders) void {
        self.enemyShootTimer += 1;
        if (self.enemyShootTimer >= self.enemyShootDelay) {
            self.enemyShootTimer = 0;
            for (invaders.invaders) |row| {
                for (row) |invader| {
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

    fn draw(self: @This()) void {
        for (self.enemyBullets) |bullet| {
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
    displayBuffer: [8:0]u8,

    fn init() @This() {
        return .{
            .start_ms = get_now_ms(),
            .displayBuffer = std.mem.zeroes([8:0]u8),
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

    fn update(self: *Timer) void {
        const time = self.get_time_parts();
        writeDisplayTimeIntoBuffer(&self.displayBuffer, time);
    }

    fn draw(self: Timer) void {
        rl.drawText(&self.displayBuffer, screenWidth - 80, 20, 20, rl.Color.yellow);
    }
};

fn writeDisplayTimeIntoBuffer(buffer: *[8:0]u8, time: struct { u64, u64 }) void {
    _ = std.fmt.bufPrintZ(
        buffer,
        "{d:0>2}:{d:0>2}",
        .{ time[0], time[1] },
    ) catch {};
}

fn updateDrawFrame(arg: ?*anyopaque) callconv(.c) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.black);

    @as(*Game, @ptrCast(@alignCast(arg.?))).cycle();
}

pub fn main() !void {
    rl.initWindow(800, 600, title);
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    game = Game.init();

    if (builtin.os.tag == .emscripten) {
        emscripten_set_main_loop_arg(updateDrawFrame, &game, 0, 1);
    } else {
        while (!rl.windowShouldClose()) {
            updateDrawFrame(&game);
        }
    }
}
