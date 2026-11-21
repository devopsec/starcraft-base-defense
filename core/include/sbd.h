/* sbd.h - C ABI of the engine-agnostic Starcraft Base Defense core (sbd_core).
 *
 * Frame flow:  sbd_world_push -> sbd_world_tick -> sbd_world_poll
 * or, with engine-side parallelism:
 *   sbd_world_push -> sbd_world_begin(dt) -> sbd_world_step_enemies(ranges...) -> sbd_world_resolve -> sbd_world_poll
 *
 * Threading: a world is not thread-safe, except that sbd_world_step_enemies may be called
 * concurrently for DISJOINT [begin,end) ranges between begin and resolve. The core never spawns threads.
 * All structs are POD, little-endian, 4-byte aligned, and have no padding.
 */
#ifndef SBD_H
#define SBD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SBD_ABI_VERSION 1u

typedef struct sbd_world sbd_world;
typedef uint32_t sbd_entity; /* (generation << 16) | index ; 0 is never valid */

typedef struct sbd_vec3 {
    float x, y, z;
} sbd_vec3;

typedef struct sbd_config {
    uint32_t enemy_start_health;
    uint32_t enemy_score;
    uint32_t player_start_health;
    uint32_t enemy_attack_damage;
    float enemy_attack_cooldown;
    float spawn_interval;
    float sink_speed;
    float sink_duration;
    float fire_rate;
    uint32_t weapon_damage;
    uint32_t seed;
    uint32_t max_enemies; /* 0 = default (64), capped at 65535 */
} sbd_config;

typedef enum sbd_cmd_kind {
    SBD_CMD_SPAWN_REQUEST = 0, /* point = spawn position, forces an extra spawn */
    SBD_CMD_HIT = 1,           /* target = enemy, amount = damage (<=0 -> weapon_damage), point = hit point */
    SBD_CMD_ENEMY_IN_RANGE = 2,/* target = enemy, amount = 1 in attack range / 0 out of range */
    SBD_CMD_FIRE = 3,          /* trigger pulled; gated by fire_rate; emits SBD_EV_SHOT */
    SBD_CMD_PAUSE_TOGGLE = 4,
    SBD_CMD_RESTART = 5
} sbd_cmd_kind;

typedef struct sbd_cmd {
    uint32_t kind;
    sbd_entity target;
    int32_t amount;
    sbd_vec3 point;
} sbd_cmd;

typedef enum sbd_ev_kind {
    SBD_EV_ENEMY_SPAWNED = 0, /* entity, value = random roll (use modulo spawn point count), pos */
    SBD_EV_ENEMY_HURT = 1,    /* entity, value = damage, pos = hit point */
    SBD_EV_ENEMY_DIED = 2,    /* entity, value = score awarded */
    SBD_EV_ENEMY_SINK = 3,    /* entity: start sinking at config.sink_speed */
    SBD_EV_ENEMY_DESPAWN = 4, /* entity: remove the view; handle is now stale */
    SBD_EV_PLAYER_HURT = 5,   /* value = remaining health */
    SBD_EV_PLAYER_DIED = 6,
    SBD_EV_SCORE = 7,         /* value = new score */
    SBD_EV_STATE = 8,         /* value = sbd_state */
    SBD_EV_EFFECT = 9,        /* effect_id = sbd_fx, entity (may be 0), value = param, pos */
    SBD_EV_SHOT = 10          /* value = damage per shot, pos = muzzle/aim point */
} sbd_ev_kind;

typedef enum sbd_state {
    SBD_STATE_PLAYING = 0,
    SBD_STATE_PAUSED = 1,
    SBD_STATE_GAME_OVER = 2,
    SBD_STATE_RESTARTING = 3 /* transient: followed by SBD_STATE_PLAYING in the same batch */
} sbd_state;

typedef enum sbd_fx {
    SBD_FX_HIT = 1,
    SBD_FX_DEATH = 2,
    SBD_FX_DEATH_SINK = 3,
    SBD_FX_PLAYER_HURT = 4,
    SBD_FX_MUZZLE = 5,
    SBD_FX_SPAWN = 6
} sbd_fx;

typedef struct sbd_event {
    uint32_t kind;
    sbd_entity entity;
    int32_t value;
    uint32_t effect_id;
    sbd_vec3 pos;
} sbd_event;

typedef enum sbd_save_err {
    SBD_SAVE_TRUNCATED = -1,
    SBD_SAVE_BAD_MAGIC = -2,
    SBD_SAVE_BAD_VERSION = -3,
    SBD_SAVE_BAD_VALUE = -4
} sbd_save_err;

#define SBD_SAVE_SIZE 12u /* SaveV1: u32 magic 'SBDS', u32 version, i32 high_score, little-endian */

uint32_t sbd_abi_version(void);
void sbd_config_default(sbd_config *out);

sbd_world *sbd_world_create(const sbd_config *cfg); /* NULL cfg = defaults; NULL on OOM */
void sbd_world_destroy(sbd_world *w);

/* Returns the number of commands accepted (queue holds 1024). */
uint32_t sbd_world_push(sbd_world *w, const sbd_cmd *cmds, uint32_t n);

/* Simple default: begin + step all enemies + resolve. dt is clamped to [0, 0.25]; NaN/negative -> 0. */
void sbd_world_tick(sbd_world *w, float dt);

/* Parallel flow. */
void sbd_world_begin(sbd_world *w, float dt);
uint32_t sbd_world_enemy_count(const sbd_world *w); /* slot range upper bound for step_enemies */
void sbd_world_step_enemies(sbd_world *w, uint32_t begin, uint32_t end, float dt); /* parallel-safe on disjoint ranges */
void sbd_world_resolve(sbd_world *w);

/* Drains up to cap events in FIFO order; call repeatedly until it returns 0. */
uint32_t sbd_world_poll(sbd_world *w, sbd_event *out, uint32_t cap);

int32_t sbd_world_score(const sbd_world *w);
int32_t sbd_world_high_score(const sbd_world *w);
int32_t sbd_world_player_health(const sbd_world *w);
uint32_t sbd_world_state(const sbd_world *w);

/* Returns bytes written (SBD_SAVE_SIZE) or 0 if cap is too small. */
uint32_t sbd_save_write(const sbd_world *w, uint8_t *buf, uint32_t cap);
/* Returns 0 on success (high score loaded) or a negative sbd_save_err. */
int32_t sbd_save_read(sbd_world *w, const uint8_t *buf, uint32_t len);

#ifdef __cplusplus
}
#endif

#endif /* SBD_H */
