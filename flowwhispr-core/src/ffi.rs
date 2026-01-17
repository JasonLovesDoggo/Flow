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

use crate::audio::{AudioCapture, CaptureState};
use crate::learning::LearningEngine;
use crate::modes::{WritingMode, WritingModeEngine};
use crate::providers::{
    CompletionProvider, CompletionRequest, OpenAICompletionProvider, OpenAITranscriptionProvider,
    TranscriptionProvider, TranscriptionRequest,
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

    let handle = FlowWhisprHandle {
        runtime,
        storage,
        audio: Mutex::new(None),
        transcription: Arc::new(OpenAITranscriptionProvider::new(None)),
        completion: Arc::new(OpenAICompletionProvider::new(None)),
        shortcuts,
        learning,
        modes: Mutex::new(modes),
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
