//! Provider abstraction layer for transcription and completion services
//!
//! Supports pluggable providers for cloud (OpenAI, ElevenLabs, Anthropic) and local services.

mod completion;
mod openai;
mod transcription;

pub use completion::{CompletionProvider, CompletionRequest, CompletionResponse};
pub use openai::{OpenAICompletionProvider, OpenAITranscriptionProvider};
pub use transcription::{TranscriptionProvider, TranscriptionRequest, TranscriptionResponse};
