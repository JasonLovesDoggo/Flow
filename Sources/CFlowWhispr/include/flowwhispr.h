//
// flowwhispr.h
// FlowWhispr C Interface
//
// Auto-generated header for the FlowWhispr Rust FFI layer.
// This header provides C-compatible function declarations for Swift interop.
//

#ifndef FLOWWHISPR_H
#define FLOWWHISPR_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to the FlowWhispr engine
typedef struct FlowWhisprHandle FlowWhisprHandle;

// ============ Lifecycle ============

/// Initialize the FlowWhispr engine
/// @param db_path Path to the SQLite database file, or NULL for default location
/// @return Opaque handle to the engine, or NULL on failure
FlowWhisprHandle* flowwhispr_init(const char* db_path);

/// Destroy the FlowWhispr engine and free resources
/// @param handle Handle returned by flowwhispr_init
void flowwhispr_destroy(FlowWhisprHandle* handle);

// ============ Audio ============

/// Start audio recording
/// @param handle Engine handle
/// @return true on success
bool flowwhispr_start_recording(FlowWhisprHandle* handle);

/// Stop audio recording and get the duration
/// @param handle Engine handle
/// @return Duration in milliseconds, or 0 on failure
uint64_t flowwhispr_stop_recording(FlowWhisprHandle* handle);

/// Check if currently recording
/// @param handle Engine handle
/// @return true if recording
bool flowwhispr_is_recording(FlowWhisprHandle* handle);

// ============ Transcription ============

/// Transcribe the recorded audio and process it
/// @param handle Engine handle
/// @param app_name Name of the current app (for mode selection), or NULL
/// @return Processed text (caller must free with flowwhispr_free_string), or NULL on failure
char* flowwhispr_transcribe(FlowWhisprHandle* handle, const char* app_name);

// ============ Shortcuts ============

/// Add a voice shortcut
/// @param handle Engine handle
/// @param trigger Trigger phrase
/// @param replacement Replacement text
/// @return true on success
bool flowwhispr_add_shortcut(FlowWhisprHandle* handle, const char* trigger, const char* replacement);

/// Remove a voice shortcut
/// @param handle Engine handle
/// @param trigger Trigger phrase to remove
/// @return true on success
bool flowwhispr_remove_shortcut(FlowWhisprHandle* handle, const char* trigger);

/// Get the number of shortcuts
/// @param handle Engine handle
/// @return Number of shortcuts
size_t flowwhispr_shortcut_count(FlowWhisprHandle* handle);

// ============ Writing Modes ============

/// Writing mode constants
/// 0 = Formal, 1 = Casual, 2 = VeryCasual, 3 = Excited

/// Set the writing mode for an app
/// @param handle Engine handle
/// @param app_name Name of the app
/// @param mode Writing mode (0-3)
/// @return true on success
bool flowwhispr_set_app_mode(FlowWhisprHandle* handle, const char* app_name, uint8_t mode);

/// Get the writing mode for an app
/// @param handle Engine handle
/// @param app_name Name of the app
/// @return Writing mode (0-3)
uint8_t flowwhispr_get_app_mode(FlowWhisprHandle* handle, const char* app_name);

// ============ Learning ============

/// Report a user edit to learn from
/// @param handle Engine handle
/// @param original Original transcribed text
/// @param edited Text after user edits
/// @return true on success
bool flowwhispr_learn_from_edit(FlowWhisprHandle* handle, const char* original, const char* edited);

/// Get the number of learned corrections
/// @param handle Engine handle
/// @return Number of corrections
size_t flowwhispr_correction_count(FlowWhisprHandle* handle);

// ============ Stats ============

/// Get total transcription time in minutes
/// @param handle Engine handle
/// @return Total minutes
uint64_t flowwhispr_total_transcription_minutes(FlowWhisprHandle* handle);

/// Get total transcription count
/// @param handle Engine handle
/// @return Total count
uint64_t flowwhispr_transcription_count(FlowWhisprHandle* handle);

// ============ Utilities ============

/// Free a string returned by flowwhispr functions
/// @param s String to free
void flowwhispr_free_string(char* s);

/// Check if the transcription provider is configured
/// @param handle Engine handle
/// @return true if configured
bool flowwhispr_is_configured(FlowWhisprHandle* handle);

/// Set the OpenAI API key
/// @param handle Engine handle
/// @param api_key OpenAI API key
/// @return true on success
bool flowwhispr_set_api_key(FlowWhisprHandle* handle, const char* api_key);

#ifdef __cplusplus
}
#endif

#endif // FLOWWHISPR_H
