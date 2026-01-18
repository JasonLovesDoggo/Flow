//! Provider abstraction layer for transcription and completion services
//!
//! Supports pluggable providers for cloud (OpenAI, ElevenLabs, Anthropic, Base10) and local services.
mod base10;
mod completion;
mod gemini;
mod local_whisper;
mod openai;
mod openrouter;
mod streaming;
mod transcription;

pub use base10::Base10TranscriptionProvider;
pub use completion::{CompletionProvider, CompletionRequest, CompletionResponse, TokenUsage};
pub use gemini::{GeminiCompletionProvider, GeminiTranscriptionProvider};
pub use local_whisper::{LocalWhisperTranscriptionProvider, WhisperModel};
pub use openai::{OpenAICompletionProvider, OpenAITranscriptionProvider};
pub use openrouter::OpenRouterCompletionProvider;
pub use streaming::{
    CompletionChunk, CompletionStream, StreamingCompletionProvider, collect_stream,
};
pub use transcription::{TranscriptionProvider, TranscriptionRequest, TranscriptionResponse};
