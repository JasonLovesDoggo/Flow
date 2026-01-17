//! FFI layer for Swift integration
//!
//! Provides C-compatible functions that can be called from Swift.
//! Uses opaque pointers and C strings for cross-language compatibility.

// FFI functions necessarily work with raw pointers - this is expected behavior
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;

use parking_lot::Mutex;
use tokio::runtime::Runtime;
use tracing::{debug, error};

use crate::apps::AppTracker;
use crate::audio::{AudioCapture, CaptureState};
use crate::learning::LearningEngine;
use crate::modes::{StyleLearner, WritingMode, WritingModeEngine};
use crate::providers::{
    AnthropicCompletionProvider, CompletionProvider, CompletionRequest, OpenAICompletionProvider,
    OpenAITranscriptionProvider, TranscriptionProvider, TranscriptionRequest,
};
use crate::shortcuts::ShortcutsEngine;
use crate::storage::Storage;
use crate::types::Shortcut;

/// Opaque handle to the FlowWhispr engine
pub struct FlowWhisprHandle {
    runtime: Runtime,
    storage: Storage,
    audio: Mutex<Option<AudioCapture>>,
    transcription: Arc<dyn TranscriptionProvider>,
    completion: Arc<dyn CompletionProvider>,
    shortcuts: ShortcutsEngine,
    learning: LearningEngine,
    modes: Mutex<WritingModeEngine>,
    app_tracker: AppTracker,
    style_learner: Mutex<StyleLearner>,
}

/// Result callback type for async operations
pub type ResultCallback = extern "C" fn(success: bool, result: *const c_char, context: *mut c_void);

// ============ Lifecycle ============

/// Initialize the FlowWhispr engine
/// Returns an opaque handle that must be passed to all other functions
/// Returns null on failure
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_init(db_path: *const c_char) -> *mut FlowWhisprHandle {
    let db_path = if db_path.is_null() {
        // default to app support directory
        dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("flowwhispr")
            .join("flowwhispr.db")
    } else {
        let path_str = match unsafe { CStr::from_ptr(db_path) }.to_str() {
            Ok(s) => s,
            Err(_) => return ptr::null_mut(),
        };
        PathBuf::from(path_str)
    };

    // ensure parent directory exists
    if let Some(parent) = db_path.parent()
        && let Err(e) = std::fs::create_dir_all(parent)
    {
        error!("Failed to create data directory: {}", e);
        return ptr::null_mut();
    }

    let runtime = match Runtime::new() {
        Ok(rt) => rt,
        Err(e) => {
            error!("Failed to create async runtime: {}", e);
            return ptr::null_mut();
        }
    };

    let storage = match Storage::open(&db_path) {
        Ok(s) => s,
        Err(e) => {
            error!("Failed to open storage: {}", e);
            return ptr::null_mut();
        }
    };

    let shortcuts =
        ShortcutsEngine::from_storage(&storage).unwrap_or_else(|_| ShortcutsEngine::new());
    let learning = LearningEngine::from_storage(&storage).unwrap_or_else(|_| LearningEngine::new());
    let modes = WritingModeEngine::new(WritingMode::Casual);
    let app_tracker = AppTracker::new();
    let style_learner = StyleLearner::new();

    let handle = FlowWhisprHandle {
        runtime,
        storage,
        audio: Mutex::new(None),
        transcription: Arc::new(OpenAITranscriptionProvider::new(None)),
        completion: Arc::new(OpenAICompletionProvider::new(None)),
        shortcuts,
        learning,
        modes: Mutex::new(modes),
        app_tracker,
        style_learner: Mutex::new(style_learner),
    };

    debug!("FlowWhispr engine initialized");

    Box::into_raw(Box::new(handle))
}

/// Destroy the FlowWhispr engine and free resources
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_destroy(handle: *mut FlowWhisprHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
        debug!("FlowWhispr engine destroyed");
    }
}

// ============ Audio ============

/// Start audio recording
/// Returns true on success
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_start_recording(handle: *mut FlowWhisprHandle) -> bool {
    let handle = unsafe { &*handle };

    let mut audio_lock = handle.audio.lock();

    // create new audio capture if needed
    if audio_lock.is_none() {
        match AudioCapture::new() {
            Ok(capture) => *audio_lock = Some(capture),
            Err(e) => {
                error!("Failed to create audio capture: {}", e);
                return false;
            }
        }
    }

    if let Some(ref mut capture) = *audio_lock {
        match capture.start() {
            Ok(_) => true,
            Err(e) => {
                error!("Failed to start recording: {}", e);
                false
            }
        }
    } else {
        false
    }
}

/// Stop audio recording and get the duration
/// Returns duration in milliseconds, or 0 on failure
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_stop_recording(handle: *mut FlowWhisprHandle) -> u64 {
    let handle = unsafe { &*handle };
    let mut audio_lock = handle.audio.lock();

    if let Some(ref mut capture) = *audio_lock {
        let duration = capture.buffer_duration_ms();
        match capture.stop() {
            Ok(_) => duration,
            Err(e) => {
                error!("Failed to stop recording: {}", e);
                0
            }
        }
    } else {
        0
    }
}

/// Check if currently recording
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_is_recording(handle: *mut FlowWhisprHandle) -> bool {
    let handle = unsafe { &*handle };
    let audio_lock = handle.audio.lock();

    if let Some(ref capture) = *audio_lock {
        capture.state() == CaptureState::Recording
    } else {
        false
    }
}

// ============ Transcription ============

/// Transcribe the recorded audio and process it
/// Returns the processed text (caller must free with flowwhispr_free_string)
/// Returns null on failure
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_transcribe(
    handle: *mut FlowWhisprHandle,
    app_name: *const c_char,
) -> *mut c_char {
    let handle = unsafe { &*handle };

    // get audio data
    let audio_data = {
        let mut audio_lock = handle.audio.lock();
        if let Some(ref mut capture) = *audio_lock {
            match capture.stop() {
                Ok(data) => data,
                Err(e) => {
                    error!("Failed to get audio data: {}", e);
                    return ptr::null_mut();
                }
            }
        } else {
            error!("No audio capture available");
            return ptr::null_mut();
        }
    };

    if audio_data.is_empty() {
        return ptr::null_mut();
    }

    // get app name
    let app = if !app_name.is_null() {
        unsafe { CStr::from_ptr(app_name) }
            .to_str()
            .ok()
            .map(String::from)
    } else {
        None
    };

    // get writing mode for app
    let mode = if let Some(ref name) = app {
        let mut modes = handle.modes.lock();
        modes.get_mode_with_storage(name, &handle.storage)
    } else {
        WritingMode::Casual
    };

    // transcribe
    let transcription_provider = Arc::clone(&handle.transcription);
    let completion_provider = Arc::clone(&handle.completion);

    let result = handle.runtime.block_on(async {
        // transcribe audio
        let request = TranscriptionRequest::new(audio_data, 16000);
        let transcription = transcription_provider.transcribe(request).await?;

        // process shortcuts
        let (text_with_shortcuts, _triggered) = handle.shortcuts.process(&transcription.text);

        // apply learned corrections
        let (text_with_corrections, _applied) =
            handle.learning.apply_corrections(&text_with_shortcuts);

        // format with completion provider
        let completion_request = CompletionRequest::new(text_with_corrections, mode)
            .with_app_context(app.unwrap_or_default());
        let completion = completion_provider.complete(completion_request).await?;

        Ok::<String, crate::error::Error>(completion.text)
    });

    match result {
        Ok(text) => match CString::new(text) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        Err(e) => {
            error!("Transcription failed: {}", e);
            ptr::null_mut()
        }
    }
}

// ============ Shortcuts ============

/// Add a voice shortcut
/// Returns true on success
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_add_shortcut(
    handle: *mut FlowWhisprHandle,
    trigger: *const c_char,
    replacement: *const c_char,
) -> bool {
    if trigger.is_null() || replacement.is_null() {
        return false;
    }

    let handle = unsafe { &*handle };

    let trigger_str = match unsafe { CStr::from_ptr(trigger) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return false,
    };

    let replacement_str = match unsafe { CStr::from_ptr(replacement) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return false,
    };

    let shortcut = Shortcut::new(trigger_str, replacement_str);

    if let Err(e) = handle.storage.save_shortcut(&shortcut) {
        error!("Failed to save shortcut: {}", e);
        return false;
    }

    handle.shortcuts.add_shortcut(shortcut);
    true
}

/// Remove a voice shortcut
/// Returns true on success
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_remove_shortcut(
    handle: *mut FlowWhisprHandle,
    trigger: *const c_char,
) -> bool {
    if trigger.is_null() {
        return false;
    }

    let handle = unsafe { &*handle };

    let trigger_str = match unsafe { CStr::from_ptr(trigger) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    handle.shortcuts.remove_shortcut(trigger_str);
    true
}

/// Get the number of shortcuts
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_shortcut_count(handle: *mut FlowWhisprHandle) -> usize {
    let handle = unsafe { &*handle };
    handle.shortcuts.count()
}

// ============ Writing Modes ============

/// Set the writing mode for an app
/// mode: 0 = Formal, 1 = Casual, 2 = VeryCasual, 3 = Excited
/// Returns true on success
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_set_app_mode(
    handle: *mut FlowWhisprHandle,
    app_name: *const c_char,
    mode: u8,
) -> bool {
    if app_name.is_null() {
        return false;
    }

    let handle = unsafe { &*handle };

    let app = match unsafe { CStr::from_ptr(app_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    let writing_mode = match mode {
        0 => WritingMode::Formal,
        1 => WritingMode::Casual,
        2 => WritingMode::VeryCasual,
        3 => WritingMode::Excited,
        _ => return false,
    };

    let mut modes = handle.modes.lock();
    if let Err(e) = modes.set_mode_with_storage(app, writing_mode, &handle.storage) {
        error!("Failed to save app mode: {}", e);
        return false;
    }

    true
}

/// Get the writing mode for an app
/// Returns: 0 = Formal, 1 = Casual, 2 = VeryCasual, 3 = Excited
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_app_mode(
    handle: *mut FlowWhisprHandle,
    app_name: *const c_char,
) -> u8 {
    if app_name.is_null() {
        return 1; // default to casual
    }

    let handle = unsafe { &*handle };

    let app = match unsafe { CStr::from_ptr(app_name) }.to_str() {
        Ok(s) => s,
        Err(_) => return 1,
    };

    let mut modes = handle.modes.lock();
    let mode = modes.get_mode_with_storage(app, &handle.storage);

    match mode {
        WritingMode::Formal => 0,
        WritingMode::Casual => 1,
        WritingMode::VeryCasual => 2,
        WritingMode::Excited => 3,
    }
}

// ============ Learning ============

/// Report a user edit to learn from
/// Returns true on success
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_learn_from_edit(
    handle: *mut FlowWhisprHandle,
    original: *const c_char,
    edited: *const c_char,
) -> bool {
    if original.is_null() || edited.is_null() {
        return false;
    }

    let handle = unsafe { &*handle };

    let original_str = match unsafe { CStr::from_ptr(original) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    let edited_str = match unsafe { CStr::from_ptr(edited) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    match handle
        .learning
        .learn_from_edit(original_str, edited_str, &handle.storage)
    {
        Ok(learned) => {
            debug!("Learned {} corrections from edit", learned.len());
            true
        }
        Err(e) => {
            error!("Failed to learn from edit: {}", e);
            false
        }
    }
}

/// Get the number of learned corrections
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_correction_count(handle: *mut FlowWhisprHandle) -> usize {
    let handle = unsafe { &*handle };
    handle.learning.cache_size()
}

// ============ Stats ============

/// Get total transcription time in minutes
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_total_transcription_minutes(handle: *mut FlowWhisprHandle) -> u64 {
    let handle = unsafe { &*handle };
    handle
        .storage
        .get_total_transcription_time_ms()
        .unwrap_or(0)
        / 60000
}

/// Get total transcription count
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_transcription_count(handle: *mut FlowWhisprHandle) -> u64 {
    let handle = unsafe { &*handle };
    handle.storage.get_transcription_count().unwrap_or(0)
}

// ============ Utilities ============

/// Free a string returned by flowwhispr functions
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Check if the transcription provider is configured
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_is_configured(handle: *mut FlowWhisprHandle) -> bool {
    let handle = unsafe { &*handle };
    handle.transcription.is_configured() && handle.completion.is_configured()
}

/// Set the OpenAI API key
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_set_api_key(
    handle: *mut FlowWhisprHandle,
    api_key: *const c_char,
) -> bool {
    if api_key.is_null() {
        return false;
    }

    let handle = unsafe { &mut *handle };

    let key = match unsafe { CStr::from_ptr(api_key) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return false,
    };

    // reinitialize providers with new key
    handle.transcription = Arc::new(OpenAITranscriptionProvider::new(Some(key.clone())));
    handle.completion = Arc::new(OpenAICompletionProvider::new(Some(key)));

    true
}

// ============ App Tracking ============

/// Set the currently active app (call from Swift when app switches)
/// Returns the suggested writing mode for the app
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_set_active_app(
    handle: *mut FlowWhisprHandle,
    app_name: *const c_char,
    bundle_id: *const c_char,
    window_title: *const c_char,
) -> u8 {
    if app_name.is_null() {
        return 1; // default to casual
    }

    let handle = unsafe { &*handle };

    let name = match unsafe { CStr::from_ptr(app_name) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 1,
    };

    let bid = if bundle_id.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(bundle_id) }
            .to_str()
            .ok()
            .map(String::from)
    };

    let title = if window_title.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(window_title) }
            .to_str()
            .ok()
            .map(String::from)
    };

    let _context = handle.app_tracker.set_active_app(name, bid, title);

    // return suggested mode
    match handle.app_tracker.suggested_mode() {
        WritingMode::Formal => 0,
        WritingMode::Casual => 1,
        WritingMode::VeryCasual => 2,
        WritingMode::Excited => 3,
    }
}

/// Get the current app's category
/// Returns: 0=Email, 1=Slack, 2=Code, 3=Documents, 4=Social, 5=Browser, 6=Terminal, 7=Unknown
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_app_category(handle: *mut FlowWhisprHandle) -> u8 {
    let handle = unsafe { &*handle };

    use crate::types::AppCategory;
    match handle.app_tracker.current_category() {
        AppCategory::Email => 0,
        AppCategory::Slack => 1,
        AppCategory::Code => 2,
        AppCategory::Documents => 3,
        AppCategory::Social => 4,
        AppCategory::Browser => 5,
        AppCategory::Terminal => 6,
        AppCategory::Unknown => 7,
    }
}

/// Get current app name (caller must free with flowwhispr_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_current_app(handle: *mut FlowWhisprHandle) -> *mut c_char {
    let handle = unsafe { &*handle };

    match handle.app_tracker.current_app() {
        Some(ctx) => match CString::new(ctx.app_name) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

// ============ Style Learning ============

/// Report edited text to learn user's style for current app
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_learn_style(
    handle: *mut FlowWhisprHandle,
    edited_text: *const c_char,
) -> bool {
    if edited_text.is_null() {
        return false;
    }

    let handle = unsafe { &*handle };

    let text = match unsafe { CStr::from_ptr(edited_text) }.to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };

    let app_name = match handle.app_tracker.current_app() {
        Some(ctx) => ctx.app_name,
        None => return false,
    };

    let mut learner = handle.style_learner.lock();
    learner.observe_with_storage(&app_name, text, &handle.storage);

    true
}

/// Get suggested mode based on learned style for current app
/// Returns: 0=Formal, 1=Casual, 2=VeryCasual, 3=Excited, 255=no suggestion
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_style_suggestion(handle: *mut FlowWhisprHandle) -> u8 {
    let handle = unsafe { &*handle };

    let app_name = match handle.app_tracker.current_app() {
        Some(ctx) => ctx.app_name,
        None => return 255,
    };

    let learner = handle.style_learner.lock();
    match learner.suggest_mode(&app_name) {
        Some(suggestion) => match suggestion.suggested_mode {
            WritingMode::Formal => 0,
            WritingMode::Casual => 1,
            WritingMode::VeryCasual => 2,
            WritingMode::Excited => 3,
        },
        None => 255,
    }
}

// ============ Extended Stats ============

/// Get user stats as JSON (caller must free with flowwhispr_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_stats_json(handle: *mut FlowWhisprHandle) -> *mut c_char {
    let handle = unsafe { &*handle };

    let stats = serde_json::json!({
        "total_transcriptions": handle.storage.get_transcription_count().unwrap_or(0),
        "total_duration_ms": handle.storage.get_total_transcription_time_ms().unwrap_or(0),
        "shortcut_count": handle.shortcuts.count(),
        "correction_count": handle.learning.cache_size(),
    });

    match CString::new(stats.to_string()) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ============ Provider Configuration ============

/// Set the Anthropic API key and switch to Anthropic for completion
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_set_anthropic_key(
    handle: *mut FlowWhisprHandle,
    api_key: *const c_char,
) -> bool {
    if api_key.is_null() {
        return false;
    }

    let handle = unsafe { &mut *handle };

    let key = match unsafe { CStr::from_ptr(api_key) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return false,
    };

    handle.completion = Arc::new(AnthropicCompletionProvider::new(Some(key)));
    debug!("Switched to Anthropic completion provider");

    true
}

/// Set completion provider
/// provider: 0 = OpenAI, 1 = Anthropic
/// api_key: The API key for the provider
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_set_completion_provider(
    handle: *mut FlowWhisprHandle,
    provider: u8,
    api_key: *const c_char,
) -> bool {
    if api_key.is_null() {
        return false;
    }

    let handle = unsafe { &mut *handle };

    let key = match unsafe { CStr::from_ptr(api_key) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return false,
    };

    match provider {
        0 => {
            handle.completion = Arc::new(OpenAICompletionProvider::new(Some(key)));
            debug!("Set completion provider to OpenAI");
        }
        1 => {
            handle.completion = Arc::new(AnthropicCompletionProvider::new(Some(key)));
            debug!("Set completion provider to Anthropic");
        }
        _ => return false,
    }

    true
}

/// Get the current completion provider name
/// Returns: 0 = OpenAI, 1 = Anthropic, 255 = Unknown
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_completion_provider(handle: *mut FlowWhisprHandle) -> u8 {
    let handle = unsafe { &*handle };

    match handle.completion.name() {
        "OpenAI GPT" => 0,
        "Anthropic Claude" => 1,
        _ => 255,
    }
}

/// Get all shortcuts as JSON (caller must free with flowwhispr_free_string)
#[unsafe(no_mangle)]
pub extern "C" fn flowwhispr_get_shortcuts_json(handle: *mut FlowWhisprHandle) -> *mut c_char {
    let handle = unsafe { &*handle };

    let shortcuts: Vec<serde_json::Value> = handle
        .shortcuts
        .get_all()
        .iter()
        .map(|s| {
            serde_json::json!({
                "trigger": s.trigger,
                "replacement": s.replacement,
                "use_count": s.use_count,
                "enabled": s.enabled,
            })
        })
        .collect();

    match CString::new(serde_json::to_string(&shortcuts).unwrap_or_default()) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}
