//! Writing modes engine for per-app mode customization
//!
//! The WritingMode enum is defined in types.rs, this module provides
//! the engine for managing modes per-app and the style analyzer.

use std::collections::HashMap;
use tracing::debug;

use crate::error::Result;
use crate::storage::Storage;

// Re-export WritingMode from types for convenience
pub use crate::types::WritingMode;

/// Engine for managing writing modes per app
pub struct WritingModeEngine {
    /// Default mode when no app-specific mode is set
    default_mode: WritingMode,
    /// In-memory cache of app modes
    app_modes: HashMap<String, WritingMode>,
}

impl WritingModeEngine {
    /// Create a new engine with the given default mode
    pub fn new(default_mode: WritingMode) -> Self {
        Self {
            default_mode,
            app_modes: HashMap::new(),
        }
    }

    /// Create engine and load app modes from storage
    pub fn from_storage(_storage: &Storage, default_mode: WritingMode) -> Result<Self> {
        let engine = Self::new(default_mode);
        // load modes would need a get_all_app_modes method
        // for now we lazily load on demand
        Ok(engine)
    }

    /// Get the writing mode for an app
    pub fn get_mode(&self, app_name: &str) -> WritingMode {
        self.app_modes
            .get(app_name)
            .copied()
            .unwrap_or(self.default_mode)
    }

    /// Get mode for app, loading from storage if not cached
    pub fn get_mode_with_storage(&mut self, app_name: &str, storage: &Storage) -> WritingMode {
        if let Some(&mode) = self.app_modes.get(app_name) {
            return mode;
        }

        // try loading from storage
        if let Ok(Some(mode)) = storage.get_app_mode(app_name) {
            self.app_modes.insert(app_name.to_string(), mode);
            return mode;
        }

        self.default_mode
    }

    /// Set the writing mode for an app
    pub fn set_mode(&mut self, app_name: &str, mode: WritingMode) {
        debug!("Setting mode for {} to {:?}", app_name, mode);
        self.app_modes.insert(app_name.to_string(), mode);
    }

    /// Set mode and persist to storage
    pub fn set_mode_with_storage(
        &mut self,
        app_name: &str,
        mode: WritingMode,
        storage: &Storage,
    ) -> Result<()> {
        self.set_mode(app_name, mode);
        storage.save_app_mode(app_name, mode)?;
        Ok(())
    }

    /// Get the default mode
    pub fn default_mode(&self) -> WritingMode {
        self.default_mode
    }

    /// Set the default mode
    pub fn set_default_mode(&mut self, mode: WritingMode) {
        self.default_mode = mode;
    }

    /// Clear the mode for an app (reverts to default)
    pub fn clear_mode(&mut self, app_name: &str) {
        self.app_modes.remove(app_name);
    }

    /// Get all app-specific mode overrides
    pub fn get_all_overrides(&self) -> &HashMap<String, WritingMode> {
        &self.app_modes
    }
}

/// Style analyzer for learning user preferences from their edits
pub struct StyleAnalyzer;

impl StyleAnalyzer {
    /// Analyze a text sample and suggest a writing mode
    pub fn analyze_style(text: &str) -> WritingMode {
        let has_caps = text.chars().any(|c| c.is_uppercase());
        let has_punctuation = text.chars().any(|c| matches!(c, '.' | '!' | '?' | ','));
        let has_exclamation = text.contains('!');
        let all_lower = text == text.to_lowercase();
        let word_count = text.split_whitespace().count();

        // detect excited style
        if has_exclamation && text.matches('!').count() >= 2 {
            return WritingMode::Excited;
        }

        // detect very casual (all lowercase, no/minimal punctuation)
        if all_lower && !has_punctuation && word_count > 0 {
            return WritingMode::VeryCasual;
        }

        // detect formal (proper caps, punctuation, longer sentences)
        let sentences: Vec<&str> = text
            .split(['.', '!', '?'])
            .filter(|s| !s.trim().is_empty())
            .collect();
        let num_sentences = sentences.len().max(1);
        let avg_sentence_length = word_count / num_sentences;

        if has_caps && has_punctuation && avg_sentence_length >= 8 {
            return WritingMode::Formal;
        }

        // default to casual
        WritingMode::Casual
    }

    /// Analyze multiple samples and return the most common style
    pub fn analyze_samples(samples: &[String]) -> WritingMode {
        if samples.is_empty() {
            return WritingMode::default();
        }

        let mut counts: HashMap<WritingMode, usize> = HashMap::new();

        for sample in samples {
            let mode = Self::analyze_style(sample);
            *counts.entry(mode).or_insert(0) += 1;
        }

        counts
            .into_iter()
            .max_by_key(|(_, count)| *count)
            .map(|(mode, _)| mode)
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::AppCategory;

    #[test]
    fn test_mode_suggestions() {
        assert_eq!(
            WritingMode::suggested_for_category(AppCategory::Email),
            WritingMode::Formal
        );
        assert_eq!(
            WritingMode::suggested_for_category(AppCategory::Slack),
            WritingMode::Casual
        );
        assert_eq!(
            WritingMode::suggested_for_category(AppCategory::Social),
            WritingMode::VeryCasual
        );
    }

    #[test]
    fn test_style_analysis() {
        assert_eq!(
            StyleAnalyzer::analyze_style("hello how r u"),
            WritingMode::VeryCasual
        );

        assert_eq!(
            StyleAnalyzer::analyze_style("This is amazing!! So excited!!!"),
            WritingMode::Excited
        );

        assert_eq!(
            StyleAnalyzer::analyze_style(
                "I would like to schedule a meeting to discuss the quarterly results."
            ),
            WritingMode::Formal
        );
    }

    #[test]
    fn test_engine() {
        let mut engine = WritingModeEngine::new(WritingMode::Casual);

        assert_eq!(engine.get_mode("Slack"), WritingMode::Casual);

        engine.set_mode("Mail", WritingMode::Formal);
        assert_eq!(engine.get_mode("Mail"), WritingMode::Formal);

        engine.clear_mode("Mail");
        assert_eq!(engine.get_mode("Mail"), WritingMode::Casual);
    }
}
