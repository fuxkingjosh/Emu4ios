// E4Achievements — RetroAchievements for every console, built on rcheevos' rc_client.
// The app does the networking (URLSession) and shows the pop-ups; this file talks to rc_client.
#ifndef E4_ACHIEVEMENTS_H
#define E4_ACHIEVEMENTS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "E4Emulator.h"
#include "E4Libretro.h"

#ifdef __cplusplus
extern "C" {
#endif

/// The app performs an HTTP request and later calls e4ra_http_response with the same id.
typedef void (*e4ra_http_fn)(int32_t requestID, const char* url, const char* postData, const char* contentType);
/// Something happened (see E4RAEvent). Strings may be empty; copy them before returning.
typedef void (*e4ra_event_fn)(int32_t type, uint32_t id, const char* title, const char* detail, const char* badgeURL, uint32_t points);
/// A login (kind 0) or game load (kind 1) finished. result 0 = success.
typedef void (*e4ra_done_fn)(int32_t kind, int32_t result, const char* message);

enum {
    E4RAEventUnlocked = 1,
    E4RAEventLeaderboardStarted = 2,
    E4RAEventLeaderboardFailed = 3,
    E4RAEventLeaderboardSubmitted = 4,
    E4RAEventChallengeShow = 5,
    E4RAEventChallengeHide = 6,
    E4RAEventProgressShow = 7,
    E4RAEventProgressHide = 8,
    E4RAEventProgressUpdate = 9,
    E4RAEventTrackerShow = 10,
    E4RAEventTrackerHide = 11,
    E4RAEventTrackerUpdate = 12,
    E4RAEventReset = 14,
    E4RAEventGameCompleted = 15,
    E4RAEventServerError = 16,
    E4RAEventDisconnected = 17,
    E4RAEventReconnected = 18,
};

void e4ra_setup(e4ra_http_fn http, e4ra_event_fn event, e4ra_done_fn done, const char* userAgent);
void e4ra_http_response(int32_t requestID, int32_t httpStatus, const char* body, size_t length);

void e4ra_login_password(const char* user, const char* password);
void e4ra_login_token(const char* user, const char* token);
void e4ra_logout(void);
bool e4ra_logged_in(void);
/// Copies the signed-in user's name / API token / score into the buffers.
void e4ra_user(char* name, size_t nameSize, char* token, size_t tokenSize, uint32_t* score);

void e4ra_set_hardcore(bool enabled);
bool e4ra_hardcore(void);

/// Console ID for an Emu4ios system name ("gba", "snes"…); 0 if RetroAchievements doesn't cover it.
uint32_t e4ra_console_id(const char* system);
/// Identifies the game by hashing its file and downloads its achievements. Call after the emulator is created.
void e4ra_load_game_mgba(uint32_t consoleID, const char* path, E4Emulator* emulator);
void e4ra_load_game_libretro(uint32_t consoleID, const char* path, E4Libretro* core);
void e4ra_unload_game(void);
bool e4ra_game_loaded(void);
void e4ra_game_title(char* out, size_t size);
void e4ra_game_badge_url(char* out, size_t size);
/// Unlocked / total achievements and points for the loaded game.
void e4ra_summary(uint32_t* unlocked, uint32_t* total, uint32_t* pointsUnlocked, uint32_t* pointsTotal);
void e4ra_rich_presence(char* out, size_t size);

/// Achievement list for the pause menu.
typedef struct {
    uint32_t id;
    char title[128];
    char description[256];
    char badgeURL[256];
    char progress[32];
    float progressPercent;
    uint32_t points;
    bool unlocked;
} E4RAAchievement;
size_t e4ra_achievement_count(void);
bool e4ra_achievement_at(size_t index, E4RAAchievement* out);

/// Call once per emulated frame on the emulation thread (and e4ra_idle while paused).
void e4ra_do_frame(void);
void e4ra_idle(void);
void e4ra_reset(void);
/// Hardcore mode forbids rewinding and loading save states.
bool e4ra_allows_state_load(void);
/// "rcheevos/x.y" — appended to the app's User-Agent as RetroAchievements asks.
void e4ra_user_agent(char* out, size_t size);

#ifdef __cplusplus
}
#endif

#endif
