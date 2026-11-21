/* Compiles against include/sbd.h and links the built library; fails if layout or behaviour drifts. */
#include <stdio.h>
#include <stdlib.h>
#include "sbd.h"

_Static_assert(sizeof(sbd_vec3) == 12, "sbd_vec3");
_Static_assert(sizeof(sbd_config) == 48, "sbd_config");
_Static_assert(sizeof(sbd_cmd) == 24, "sbd_cmd");
_Static_assert(sizeof(sbd_event) == 28, "sbd_event");

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, #c); return 1; } } while (0)

int main(void) {
    CHECK(sbd_abi_version() == SBD_ABI_VERSION);

    sbd_config cfg;
    sbd_config_default(&cfg);
    CHECK(cfg.enemy_start_health == 100 && cfg.enemy_score == 10);
    cfg.spawn_interval = 1000.0f;

    sbd_world *w = sbd_world_create(&cfg);
    CHECK(w != NULL);

    sbd_cmd spawn = {SBD_CMD_SPAWN_REQUEST, 0, 0, {1, 2, 3}};
    CHECK(sbd_world_push(w, &spawn, 1) == 1);
    sbd_world_tick(w, 0.016f);

    sbd_event ev[32];
    uint32_t n = sbd_world_poll(w, ev, 32);
    CHECK(n >= 1 && ev[0].kind == SBD_EV_ENEMY_SPAWNED);
    CHECK(ev[0].pos.x == 1.0f && ev[0].pos.z == 3.0f);
    sbd_entity enemy = ev[0].entity;
    CHECK(enemy != 0 && sbd_world_enemy_count(w) == 1);

    sbd_cmd hit = {SBD_CMD_HIT, enemy, 100, {0, 0, 0}};
    sbd_world_push(w, &hit, 1);
    sbd_world_begin(w, 0.016f);
    sbd_world_step_enemies(w, 0, sbd_world_enemy_count(w), 0.016f);
    sbd_world_resolve(w);
    CHECK(sbd_world_score(w) == 10);

    n = sbd_world_poll(w, ev, 32);
    int died = 0;
    for (uint32_t i = 0; i < n; i++) died |= ev[i].kind == SBD_EV_ENEMY_DIED;
    CHECK(died);

    uint8_t buf[SBD_SAVE_SIZE];
    CHECK(sbd_save_write(w, buf, sizeof buf) == SBD_SAVE_SIZE);
    CHECK(sbd_save_read(w, buf, 3) == SBD_SAVE_TRUNCATED);
    buf[0] ^= 0xff;
    CHECK(sbd_save_read(w, buf, sizeof buf) == SBD_SAVE_BAD_MAGIC);
    buf[0] ^= 0xff;
    CHECK(sbd_save_read(w, buf, sizeof buf) == 0);

    sbd_cmd pause = {SBD_CMD_PAUSE_TOGGLE, 0, 0, {0, 0, 0}};
    sbd_world_push(w, &pause, 1);
    sbd_world_tick(w, 0.016f);
    CHECK(sbd_world_state(w) == SBD_STATE_PAUSED);

    sbd_world_destroy(w);
    puts("abi_test OK");
    return 0;
}
