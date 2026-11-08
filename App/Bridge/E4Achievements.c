#include "E4Achievements.h"
#include "rc_client.h"
#include "rc_consoles.h"
#include "rc_api_request.h"
#include "rcheevos/src/libretro/rc_libretro.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// MARK: - State

static rc_client_t* client = NULL;
static e4ra_http_fn httpFn = NULL;
static e4ra_event_fn eventFn = NULL;
static e4ra_done_fn doneFn = NULL;

// What memory the loaded game reads from.
static E4Emulator* mgba = NULL;
static const rc_memory_regions_t* mgbaRegions = NULL;
static rc_libretro_memory_regions_t lrRegions;
static bool lrRegionsReady = false;

// Requests waiting for the app's URLSession.
#define MAX_PENDING 64
typedef struct {
    int32_t id;
    rc_client_server_callback_t callback;
    void* data;
} Pending;
static Pending pending[MAX_PENDING];
static int32_t nextRequestID = 1;
static pthread_mutex_t pendingLock = PTHREAD_MUTEX_INITIALIZER;

// The achievement list for the menu, rebuilt on demand.
static rc_client_achievement_list_t* cachedList = NULL;

// MARK: - Memory

static uint32_t read_mgba(uint32_t address, uint8_t* buffer, uint32_t count, rc_client_t* c) {
    (void) c;
    if (!mgba || !mgbaRegions) return 0;
    for (uint32_t i = 0; i < mgbaRegions->num_regions; i++) {
        const rc_memory_region_t* r = &mgbaRegions->region[i];
        if (address < r->start_address || address > r->end_address) continue;
        uint32_t avail = r->end_address - address + 1;
        uint32_t n = count < avail ? count : avail;
        for (uint32_t j = 0; j < n; j++) buffer[j] = e4_peek(mgba, r->real_address + (address - r->start_address) + j);
        return n;
    }
    return 0;
}

static uint32_t read_libretro(uint32_t address, uint8_t* buffer, uint32_t count, rc_client_t* c) {
    (void) c;
    if (!lrRegionsReady) return 0;
    return rc_libretro_memory_read(&lrRegions, address, buffer, count);
}

static void core_memory_info(uint32_t id, rc_libretro_core_memory_info_t* info) {
    size_t size = 0;
    info->data = e4lr_memory(id, &size);
    info->size = info->data ? size : 0;
}

// MARK: - Networking

static void server_call(const rc_api_request_t* request, rc_client_server_callback_t callback, void* data, rc_client_t* c) {
    (void) c;
    pthread_mutex_lock(&pendingLock);
    int slot = -1;
    for (int i = 0; i < MAX_PENDING; i++) if (pending[i].id == 0) { slot = i; break; }
    int32_t id = nextRequestID++;
    if (slot >= 0) { pending[slot].id = id; pending[slot].callback = callback; pending[slot].data = data; }
    pthread_mutex_unlock(&pendingLock);
    if (slot < 0 || !httpFn) {
        rc_api_server_response_t response = { "", 0, RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR };
        callback(&response, data);
        return;
    }
    httpFn(id, request->url, request->post_data, request->content_type);
}

void e4ra_http_response(int32_t requestID, int32_t httpStatus, const char* body, size_t length) {
    rc_client_server_callback_t callback = NULL;
    void* data = NULL;
    pthread_mutex_lock(&pendingLock);
    for (int i = 0; i < MAX_PENDING; i++) {
        if (pending[i].id == requestID) {
            callback = pending[i].callback; data = pending[i].data;
            pending[i].id = 0;
            break;
        }
    }
    pthread_mutex_unlock(&pendingLock);
    if (!callback) return;
    rc_api_server_response_t response;
    response.body = body ? body : "";
    response.body_length = body ? length : 0;
    // Network failures (no status) are retried by rc_client.
    response.http_status_code = httpStatus > 0 ? httpStatus : RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR;
    callback(&response, data);
}

// MARK: - Events

static void send_event(int32_t type, uint32_t id, const char* title, const char* detail, const char* badge, uint32_t points) {
    if (eventFn) eventFn(type, id, title ? title : "", detail ? detail : "", badge ? badge : "", points);
}

static void event_handler(const rc_client_event_t* e, rc_client_t* c) {
    (void) c;
    const rc_client_achievement_t* a = e->achievement;
    switch (e->type) {
    case RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED:
    case RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_SHOW:
    case RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_HIDE:
        if (a) send_event((int32_t) e->type, a->id, a->title, a->description, a->badge_url, a->points);
        break;
    case RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_SHOW:
    case RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_UPDATE:
        if (a) send_event((int32_t) e->type, a->id, a->title, a->measured_progress, a->badge_url, a->points);
        break;
    case RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_HIDE:
        send_event((int32_t) e->type, 0, "", "", "", 0);
        break;
    case RC_CLIENT_EVENT_LEADERBOARD_STARTED:
    case RC_CLIENT_EVENT_LEADERBOARD_FAILED:
    case RC_CLIENT_EVENT_LEADERBOARD_SUBMITTED:
        if (e->leaderboard) send_event((int32_t) e->type, e->leaderboard->id, e->leaderboard->title,
                                       e->leaderboard->tracker_value ? e->leaderboard->tracker_value : e->leaderboard->description, "", 0);
        break;
    case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_SHOW:
    case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_UPDATE:
    case RC_CLIENT_EVENT_LEADERBOARD_TRACKER_HIDE:
        if (e->leaderboard_tracker) send_event((int32_t) e->type, e->leaderboard_tracker->id, "", e->leaderboard_tracker->display, "", 0);
        break;
    case RC_CLIENT_EVENT_GAME_COMPLETED: {
        const rc_client_game_t* g = rc_client_get_game_info(client);
        send_event((int32_t) e->type, g ? g->id : 0, g ? g->title : "", "", g ? g->badge_url : "", 0);
        break;
    }
    case RC_CLIENT_EVENT_SERVER_ERROR:
        send_event((int32_t) e->type, 0, "Server error", e->server_error ? e->server_error->error_message : "", "", 0);
        break;
    case RC_CLIENT_EVENT_RESET:
    case RC_CLIENT_EVENT_DISCONNECTED:
    case RC_CLIENT_EVENT_RECONNECTED:
        send_event((int32_t) e->type, 0, "", "", "", 0);
        break;
    default:
        break;
    }
}

// MARK: - Setup & login

void e4ra_setup(e4ra_http_fn http, e4ra_event_fn event, e4ra_done_fn done, const char* userAgent) {
    (void) userAgent;
    httpFn = http; eventFn = event; doneFn = done;
    if (client) return;
    client = rc_client_create(read_mgba, server_call);
    rc_client_set_event_handler(client, event_handler);
    rc_client_set_hardcore_enabled(client, 0);
}

static void login_done(int result, const char* message, rc_client_t* c, void* userdata) {
    (void) c; (void) userdata;
    if (doneFn) doneFn(0, result, message ? message : "");
}

void e4ra_login_password(const char* user, const char* password) {
    if (client) rc_client_begin_login_with_password(client, user, password, login_done, NULL);
}

void e4ra_login_token(const char* user, const char* token) {
    if (client) rc_client_begin_login_with_token(client, user, token, login_done, NULL);
}

void e4ra_logout(void) { if (client) rc_client_logout(client); }

bool e4ra_logged_in(void) { return client && rc_client_get_user_info(client) != NULL; }

void e4ra_user(char* name, size_t nameSize, char* token, size_t tokenSize, uint32_t* score) {
    const rc_client_user_t* u = client ? rc_client_get_user_info(client) : NULL;
    if (name && nameSize) snprintf(name, nameSize, "%s", u && u->display_name ? u->display_name : "");
    if (token && tokenSize) snprintf(token, tokenSize, "%s", u && u->token ? u->token : "");
    if (score) *score = u ? u->score : 0;
}

void e4ra_set_hardcore(bool enabled) { if (client) rc_client_set_hardcore_enabled(client, enabled ? 1 : 0); }
bool e4ra_hardcore(void) { return client && rc_client_get_hardcore_enabled(client); }

// MARK: - Games

uint32_t e4ra_console_id(const char* s) {
    static const struct { const char* name; uint32_t id; } map[] = {
        {"gb", RC_CONSOLE_GAMEBOY}, {"gbc", RC_CONSOLE_GAMEBOY_COLOR}, {"gba", RC_CONSOLE_GAMEBOY_ADVANCE},
        {"nes", RC_CONSOLE_NINTENDO}, {"snes", RC_CONSOLE_SUPER_NINTENDO}, {"n64", RC_CONSOLE_NINTENDO_64},
        {"nds", RC_CONSOLE_NINTENDO_DS}, {"vb", RC_CONSOLE_VIRTUAL_BOY}, {"pokemini", RC_CONSOLE_POKEMON_MINI},
        {"genesis", RC_CONSOLE_MEGA_DRIVE}, {"segacd", RC_CONSOLE_SEGA_CD}, {"sms", RC_CONSOLE_MASTER_SYSTEM},
        {"gamegear", RC_CONSOLE_GAME_GEAR}, {"sg1000", RC_CONSOLE_SG1000}, {"ps1", RC_CONSOLE_PLAYSTATION},
        {"psp", RC_CONSOLE_PSP}, {"pce", RC_CONSOLE_PC_ENGINE}, {"pcecd", RC_CONSOLE_PC_ENGINE_CD},
        {"supergrafx", RC_CONSOLE_PC_ENGINE}, {"ngp", RC_CONSOLE_NEOGEO_POCKET}, {"ngpc", RC_CONSOLE_NEOGEO_POCKET},
        {"wswan", RC_CONSOLE_WONDERSWAN}, {"wswanc", RC_CONSOLE_WONDERSWAN}, {"atari2600", RC_CONSOLE_ATARI_2600},
        {"atari5200", RC_CONSOLE_ATARI_5200}, {"atari7800", RC_CONSOLE_ATARI_7800}, {"lynx", RC_CONSOLE_ATARI_LYNX},
        {"jaguar", RC_CONSOLE_ATARI_JAGUAR}, {"c64", RC_CONSOLE_COMMODORE_64}, {"amiga", RC_CONSOLE_AMIGA},
        {"dos", RC_CONSOLE_MS_DOS},
    };
    for (size_t i = 0; i < sizeof map / sizeof map[0]; i++) if (!strcmp(map[i].name, s)) return map[i].id;
    return 0;
}

static void load_done(int result, const char* message, rc_client_t* c, void* userdata) {
    (void) c; (void) userdata;
    if (doneFn) doneFn(1, result, message ? message : "");
}

static void release_memory(void) {
    if (lrRegionsReady) { rc_libretro_memory_destroy(&lrRegions); lrRegionsReady = false; }
    mgba = NULL;
    mgbaRegions = NULL;
}

void e4ra_load_game_mgba(uint32_t consoleID, const char* path, E4Emulator* emulator) {
    if (!client || !consoleID) return;
    e4ra_unload_game();
    mgba = emulator;
    mgbaRegions = rc_console_memory_regions(consoleID);
    rc_client_set_read_memory_function(client, read_mgba);
    rc_client_begin_identify_and_load_game(client, consoleID, path, NULL, 0, load_done, NULL);
}

void e4ra_load_game_libretro(uint32_t consoleID, const char* path, E4Libretro* core) {
    if (!client || !consoleID) return;
    e4ra_unload_game();
    const struct retro_memory_map* mmap = NULL;
    struct retro_memory_map map;
    if (core && e4lr_memory_map_count(core) > 0) {
        map.descriptors = (const struct retro_memory_descriptor*) e4lr_memory_map(core);
        map.num_descriptors = (unsigned) e4lr_memory_map_count(core);
        mmap = &map;
    }
    memset(&lrRegions, 0, sizeof lrRegions);
    lrRegionsReady = rc_libretro_memory_init(&lrRegions, mmap, core_memory_info, consoleID) != 0;
    rc_client_set_read_memory_function(client, read_libretro);
    rc_client_begin_identify_and_load_game(client, consoleID, path, NULL, 0, load_done, NULL);
}

void e4ra_unload_game(void) {
    if (cachedList) { rc_client_destroy_achievement_list(cachedList); cachedList = NULL; }
    if (client) rc_client_unload_game(client);
    release_memory();
}

bool e4ra_game_loaded(void) { return client && rc_client_is_game_loaded(client); }

void e4ra_game_title(char* out, size_t size) {
    const rc_client_game_t* g = client ? rc_client_get_game_info(client) : NULL;
    snprintf(out, size, "%s", g && g->title ? g->title : "");
}

void e4ra_game_badge_url(char* out, size_t size) {
    const rc_client_game_t* g = client ? rc_client_get_game_info(client) : NULL;
    snprintf(out, size, "%s", g && g->badge_url ? g->badge_url : "");
}

void e4ra_summary(uint32_t* unlocked, uint32_t* total, uint32_t* pointsUnlocked, uint32_t* pointsTotal) {
    rc_client_user_game_summary_t s;
    memset(&s, 0, sizeof s);
    if (client && rc_client_is_game_loaded(client)) rc_client_get_user_game_summary(client, &s);
    if (unlocked) *unlocked = s.num_unlocked_achievements;
    if (total) *total = s.num_promoted_achievements;
    if (pointsUnlocked) *pointsUnlocked = s.points_unlocked;
    if (pointsTotal) *pointsTotal = s.points_available;
}

void e4ra_rich_presence(char* out, size_t size) {
    out[0] = 0;
    if (client && rc_client_has_rich_presence(client)) rc_client_get_rich_presence_message(client, out, size);
}

// MARK: - Achievement list

static void rebuild_list(void) {
    if (cachedList) rc_client_destroy_achievement_list(cachedList);
    cachedList = client ? rc_client_create_achievement_list(client, RC_CLIENT_ACHIEVEMENT_CATEGORY_PROMOTED,
                                                            RC_CLIENT_ACHIEVEMENT_LIST_GROUPING_PROGRESS) : NULL;
}

size_t e4ra_achievement_count(void) {
    rebuild_list();
    if (!cachedList) return 0;
    size_t n = 0;
    for (uint32_t b = 0; b < cachedList->num_buckets; b++) n += cachedList->buckets[b].num_achievements;
    return n;
}

bool e4ra_achievement_at(size_t index, E4RAAchievement* out) {
    if (!cachedList) return false;
    for (uint32_t b = 0; b < cachedList->num_buckets; b++) {
        const rc_client_achievement_bucket_t* bucket = &cachedList->buckets[b];
        if (index >= bucket->num_achievements) { index -= bucket->num_achievements; continue; }
        const rc_client_achievement_t* a = bucket->achievements[index];
        memset(out, 0, sizeof *out);
        out->id = a->id;
        out->points = a->points;
        out->unlocked = a->unlocked != 0;
        out->progressPercent = a->measured_percent;
        snprintf(out->title, sizeof out->title, "%s", a->title ? a->title : "");
        snprintf(out->description, sizeof out->description, "%s", a->description ? a->description : "");
        snprintf(out->progress, sizeof out->progress, "%s", a->measured_progress);
        const char* url = a->unlocked ? a->badge_url : (a->badge_locked_url ? a->badge_locked_url : a->badge_url);
        snprintf(out->badgeURL, sizeof out->badgeURL, "%s", url ? url : "");
        return true;
    }
    return false;
}

// MARK: - Per frame

void e4ra_do_frame(void) { if (client && rc_client_is_game_loaded(client)) rc_client_do_frame(client); }
void e4ra_idle(void) { if (client) rc_client_idle(client); }
void e4ra_reset(void) { if (client && rc_client_is_game_loaded(client)) rc_client_reset(client); }
bool e4ra_allows_state_load(void) { return !(client && rc_client_get_hardcore_enabled(client) && rc_client_is_game_loaded(client)); }

void e4ra_user_agent(char* out, size_t size) {
    out[0] = 0;
    if (client) rc_client_get_user_agent_clause(client, out, size);
}
