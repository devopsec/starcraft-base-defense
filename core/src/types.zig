//! ABI-visible POD types shared by the whole core. Layout must match include/sbd.h.
const std = @import("std");

pub const abi_version: u32 = 1;

pub const Entity = u32; // (generation << 16) | index ; 0 is never valid
pub const invalid_entity: Entity = 0;

pub const Vec3 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const Config = extern struct {
    enemy_start_health: u32,
    enemy_score: u32,
    player_start_health: u32,
    enemy_attack_damage: u32,
    enemy_attack_cooldown: f32,
    spawn_interval: f32,
    sink_speed: f32,
    sink_duration: f32,
    fire_rate: f32,
    weapon_damage: u32,
    seed: u32,
    max_enemies: u32,

    pub const default: Config = .{
        .enemy_start_health = 100,
        .enemy_score = 10,
        .player_start_health = 100,
        .enemy_attack_damage = 10,
        .enemy_attack_cooldown = 0.5,
        .spawn_interval = 3.0,
        .sink_speed = 2.5,
        .sink_duration = 2.0,
        .fire_rate = 0.15,
        .weapon_damage = 20,
        .seed = 1,
        .max_enemies = 64,
    };
};

pub const CmdKind = struct {
    pub const spawn_request: u32 = 0;
    pub const hit: u32 = 1;
    pub const enemy_in_range: u32 = 2;
    pub const fire: u32 = 3;
    pub const pause_toggle: u32 = 4;
    pub const restart: u32 = 5;
};

pub const Cmd = extern struct {
    kind: u32,
    target: Entity,
    amount: i32,
    point: Vec3,
};

pub const EvKind = struct {
    pub const enemy_spawned: u32 = 0;
    pub const enemy_hurt: u32 = 1;
    pub const enemy_died: u32 = 2;
    pub const enemy_sink: u32 = 3;
    pub const enemy_despawn: u32 = 4;
    pub const player_hurt: u32 = 5;
    pub const player_died: u32 = 6;
    pub const score: u32 = 7;
    pub const state: u32 = 8;
    pub const effect: u32 = 9;
    pub const shot: u32 = 10;
};

pub const Fx = struct {
    pub const hit: u32 = 1;
    pub const death: u32 = 2;
    pub const death_sink: u32 = 3;
    pub const player_hurt: u32 = 4;
    pub const muzzle: u32 = 5;
    pub const spawn: u32 = 6;
};

pub const Event = extern struct {
    kind: u32,
    entity: Entity,
    value: i32,
    effect_id: u32,
    pos: Vec3,
};

pub const State = struct {
    pub const playing: u32 = 0;
    pub const paused: u32 = 1;
    pub const game_over: u32 = 2;
    pub const restarting: u32 = 3;
};

pub const SaveErr = struct {
    pub const truncated: i32 = -1;
    pub const bad_magic: i32 = -2;
    pub const bad_version: i32 = -3;
    pub const bad_value: i32 = -4;
};

comptime {
    std.debug.assert(@sizeOf(Vec3) == 12);
    std.debug.assert(@sizeOf(Config) == 48);
    std.debug.assert(@sizeOf(Cmd) == 24);
    std.debug.assert(@sizeOf(Event) == 28);
    std.debug.assert(@alignOf(Event) == 4);
}
