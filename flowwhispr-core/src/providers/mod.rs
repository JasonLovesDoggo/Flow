//! Provider abstraction layer for transcription and completion services
//!
//! Supports pluggable providers for cloud (OpenAI, ElevenLabs, Anthropic) and local services.

mod anthropic;
mod completion;
mod openai;
mod streaming;
mod transcription;

pub use anthropic::AnthropicCompletionProvider;
pub use completion::{CompletionProvider, CompletionRequest, CompletionResponse, TokenUsage};
pub use openai::{OpenAICompletionProvider, OpenAITranscriptionProvider};
pub use streaming::{
    CompletionChunk, CompletionStream, StreamingCompletionProvider, collect_stream,
};
pub use transcription::{TranscriptionProvider, TranscriptionRequest, TranscriptionResponse};
