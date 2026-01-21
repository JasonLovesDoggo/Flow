//! Self-learning typo correction engine
//!
//! Learns from user corrections when they edit transcribed text.
//! Uses Jaro-Winkler similarity for fuzzy matching and logarithmic confidence scaling.

use parking_lot::RwLock;
use std::collections::HashMap;
use strsim::jaro_winkler;
use tracing::{debug, info};

use crate::error::Result;
use crate::storage::Storage;
use crate::types::{Correction, CorrectionSource};

/// Minimum similarity threshold for considering a word pair as a typo correction
const MIN_SIMILARITY: f64 = 0.7;

/// Minimum similarity for word alignment (lower threshold for pairing)
const MIN_ALIGNMENT_SIMILARITY: f64 = 0.5;

/// Minimum confidence to auto-apply a correction (lowered to 0.55 to trigger at ~3 occurrences instead of ~5)
const MIN_AUTO_APPLY_CONFIDENCE: f32 = 0.55;

/// Maximum word length difference to consider a correction (set to 1 for exact wrong words like "there"/"their")
const MAX_LENGTH_DIFF: usize = 1;

/// Engine for learning and applying typo corrections
pub struct LearningEngine {
    /// In-memory cache of high-confidence corrections (original -> corrected)
    corrections: RwLock<HashMap<String, CachedCorrection>>,
    /// Minimum confidence for auto-applying corrections
    min_confidence: f32,
}

#[derive(Debug, Clone)]
struct CachedCorrection {
    corrected: String,
    confidence: f32,
}

impl LearningEngine {
    /// Create a new learning engine
    pub fn new() -> Self {
        Self {
            corrections: RwLock::new(HashMap::new()),
            min_confidence: MIN_AUTO_APPLY_CONFIDENCE,
        }
    }

    /// Create engine and load corrections from storage
    pub fn from_storage(storage: &Storage) -> Result<Self> {
        let engine = Self::new();
        let corrections = storage.get_corrections(MIN_AUTO_APPLY_CONFIDENCE)?;

        let mut cache = engine.corrections.write();
        for correction in corrections {
            cache.insert(
                correction.original.to_lowercase(),
                CachedCorrection {
                    corrected: correction.corrected,
                    confidence: correction.confidence,
                },
            );
        }
        drop(cache);

        info!(
            "Loaded {} corrections into learning engine",
            engine.corrections.read().len()
        );

        Ok(engine)
    }

    /// Set the minimum confidence threshold for auto-applying corrections
    pub fn set_min_confidence(&mut self, confidence: f32) {
        self.min_confidence = confidence.clamp(0.0, 1.0);
    }

    /// Learn from a before/after text comparison
    /// Detects word-level changes and records them as potential corrections
    pub fn learn_from_edit(
        &self,
        original: &str,
        edited: &str,
        storage: &Storage,
    ) -> Result<Vec<LearnedCorrection>> {
        let original_words: Vec<&str> = original.split_whitespace().collect();
        let edited_words: Vec<&str> = edited.split_whitespace().collect();

        let mut learned = Vec::new();

        // use edit distance alignment to find corresponding words
        let pairs = align_words(&original_words, &edited_words);

        for (orig, edit) in pairs {
            // skip if same
            if orig.eq_ignore_ascii_case(edit) {
                continue;
            }

            // check if this looks like a typo correction (high similarity)
            let similarity = jaro_winkler(orig, edit);

            if similarity >= MIN_SIMILARITY {
                // check length difference
                let len_diff = (orig.len() as isize - edit.len() as isize).unsigned_abs();
                if len_diff > MAX_LENGTH_DIFF {
                    continue;
                }

                // this looks like a typo correction
                let mut correction = Correction::new(
                    orig.to_lowercase(),
                    edit.to_string(),
                    CorrectionSource::UserEdit,
                );

                // save or update in storage (will increment occurrences if exists)
                storage.save_correction(&correction)?;

                // update cache if confidence is high enough
                correction.update_confidence();
                if correction.confidence >= self.min_confidence {
                    let mut cache = self.corrections.write();
                    cache.insert(
                        correction.original.clone(),
                        CachedCorrection {
                            corrected: correction.corrected.clone(),
                            confidence: correction.confidence,
                        },
                    );
                }

                debug!(
                    "Learned correction: '{}' -> '{}' (similarity: {:.2})",
                    orig, edit, similarity
                );

                learned.push(LearnedCorrection {
                    original: orig.to_string(),
                    corrected: edit.to_string(),
                    similarity,
                });
            }
        }

        Ok(learned)
    }

    /// Apply learned corrections to text
    /// Only applies corrections above the confidence threshold
    pub fn apply_corrections(&self, text: &str) -> (String, Vec<AppliedCorrection>) {
        let cache = self.corrections.read();

        if cache.is_empty() {
            return (text.to_string(), Vec::new());
        }

        let words: Vec<&str> = text.split_whitespace().collect();

        // Early exit if no words
        if words.is_empty() {
            return (text.to_string(), Vec::new());
        }

        // Pre-allocate with reasonable capacity
        let mut applied = Vec::with_capacity(4);
        let mut result_words: Vec<String> = Vec::with_capacity(words.len());
        let min_conf = self.min_confidence;

        for (i, word) in words.iter().enumerate() {
            let word_lower = word.to_lowercase();

            if let Some(correction) = cache.get(&word_lower) {
                if correction.confidence >= min_conf {
                    // preserve case pattern if possible
                    let corrected = match_case(&correction.corrected, word);

                    applied.push(AppliedCorrection {
                        original: word.to_string(),
                        corrected: corrected.clone(),
                        confidence: correction.confidence,
                        position: i,
                    });

                    result_words.push(corrected);
                    continue;
                }
            }
            result_words.push(word.to_string());
        }

        let result = result_words.join(" ");

        if !applied.is_empty() {
            debug!("Applied {} corrections to text", applied.len());
        }

        (result, applied)
    }

    /// Check if we have a correction for a word
    pub fn has_correction(&self, word: &str) -> bool {
        let cache = self.corrections.read();
        cache.contains_key(&word.to_lowercase())
    }

    /// Get the correction for a word if available
    pub fn get_correction(&self, word: &str) -> Option<String> {
        let cache = self.corrections.read();
        cache
            .get(&word.to_lowercase())
            .filter(|c| c.confidence >= self.min_confidence)
            .map(|c| c.corrected.clone())
    }

    /// Get all cached corrections
    pub fn get_all_corrections(&self) -> Vec<(String, String, f32)> {
        self.corrections
            .read()
            .iter()
            .map(|(orig, c)| (orig.clone(), c.corrected.clone(), c.confidence))
            .collect()
    }

    /// Clear all cached corrections
    pub fn clear_cache(&self) {
        self.corrections.write().clear();
    }

    /// Get the number of cached corrections
    pub fn cache_size(&self) -> usize {
        self.corrections.read().len()
    }

    /// Remove a correction from the cache by original word
    pub fn remove_from_cache(&self, original: &str) {
        self.corrections.write().remove(&original.to_lowercase());
    }

    /// Reload corrections from storage (useful after deleting)
    pub fn reload_from_storage(
        &self,
        storage: &crate::storage::Storage,
    ) -> crate::error::Result<()> {
        let corrections = storage.get_corrections(self.min_confidence)?;

        let mut cache = self.corrections.write();
        cache.clear();
        for correction in corrections {
            cache.insert(
                correction.original.to_lowercase(),
                CachedCorrection {
                    corrected: correction.corrected,
                    confidence: correction.confidence,
                },
            );
        }

        info!("Reloaded {} corrections into learning engine", cache.len());

        Ok(())
    }
}

impl Default for LearningEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// A correction that was learned from user edits
#[derive(Debug, Clone)]
pub struct LearnedCorrection {
    pub original: String,
    pub corrected: String,
    pub similarity: f64,
}

/// A correction that was applied to text
#[derive(Debug, Clone)]
pub struct AppliedCorrection {
    pub original: String,
    pub corrected: String,
    pub confidence: f32,
    pub position: usize,
}

/// Align words from two texts using a simple diff algorithm
/// Optimized with early exits and reduced redundant similarity calculations
fn align_words<'a>(original: &[&'a str], edited: &[&'a str]) -> Vec<(&'a str, &'a str)> {
    // Early exit for empty inputs
    if original.is_empty() || edited.is_empty() {
        return Vec::new();
    }

    // Pre-allocate with expected capacity (most words will pair)
    let mut pairs = Vec::with_capacity(original.len().min(edited.len()));

    let mut orig_idx = 0;
    let mut edit_idx = 0;
    let orig_len = original.len();
    let edit_len = edited.len();

    while orig_idx < orig_len && edit_idx < edit_len {
        let orig = original[orig_idx];
        let edit = edited[edit_idx];

        // Quick check: if strings are equal, no need to compute similarity
        if orig.eq_ignore_ascii_case(edit) {
            pairs.push((orig, edit));
            orig_idx += 1;
            edit_idx += 1;
            continue;
        }

        // Compute similarity for current pair
        let sim = jaro_winkler(orig, edit);

        if sim >= MIN_ALIGNMENT_SIMILARITY {
            pairs.push((orig, edit));
            orig_idx += 1;
            edit_idx += 1;
        } else {
            // Only compute lookahead similarities if needed
            let has_next_orig = orig_idx + 1 < orig_len;
            let has_next_edit = edit_idx + 1 < edit_len;

            let skip_orig = has_next_orig && jaro_winkler(original[orig_idx + 1], edit) > sim;
            let skip_edit = has_next_edit && jaro_winkler(orig, edited[edit_idx + 1]) > sim;

            match (skip_orig, skip_edit) {
                (true, false) => orig_idx += 1,
                (false, true) => edit_idx += 1,
                _ => {
                    orig_idx += 1;
                    edit_idx += 1;
                }
            }
        }
    }

    pairs
}

/// Try to match the case pattern of the original word
/// Optimized to minimize allocations and iterations
#[inline]
fn match_case(corrected: &str, original: &str) -> String {
    // Early exit for empty strings
    if original.is_empty() || corrected.is_empty() {
        return corrected.to_string();
    }

    let mut chars = original.chars();
    let first_char = chars.next().unwrap();

    // Check case pattern with single pass
    if first_char.is_uppercase() {
        let rest_lowercase = chars.all(|c| !c.is_alphabetic() || c.is_lowercase());

        if rest_lowercase {
            // Title case: capitalize first letter only
            let mut result = String::with_capacity(corrected.len());
            let mut corrected_chars = corrected.chars();

            if let Some(first) = corrected_chars.next() {
                for c in first.to_uppercase() {
                    result.push(c);
                }
                for c in corrected_chars {
                    for lc in c.to_lowercase() {
                        result.push(lc);
                    }
                }
            }
            result
        } else {
            // Check if ALL CAPS
            let all_upper = original.chars().all(|c| !c.is_alphabetic() || c.is_uppercase());
            if all_upper {
                corrected.to_uppercase()
            } else {
                corrected.to_string()
            }
        }
    } else {
        // Original starts with lowercase, preserve corrected case
        corrected.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apply_corrections() {
        let engine = LearningEngine::new();

        // manually add a correction to cache
        {
            let mut cache = engine.corrections.write();
            cache.insert(
                "teh".to_string(),
                CachedCorrection {
                    corrected: "the".to_string(),
                    confidence: 0.95,
                },
            );

            cache.insert(
                "recieve".to_string(),
                CachedCorrection {
                    corrected: "receive".to_string(),
                    confidence: 0.9,
                },
            );
        }

        let (result, applied) = engine.apply_corrections("I will recieve teh package");

        assert_eq!(result, "I will receive the package");
        assert_eq!(applied.len(), 2);
    }

    #[test]
    fn test_case_matching() {
        assert_eq!(match_case("the", "TEH"), "THE");
        assert_eq!(match_case("the", "Teh"), "The");
        assert_eq!(match_case("the", "teh"), "the");
    }

    #[test]
    fn test_word_alignment() {
        let original = vec!["I", "recieve", "teh", "mail"];
        let edited = vec!["I", "receive", "the", "mail"];

        let pairs = align_words(&original, &edited);

        assert_eq!(pairs.len(), 4);
        assert_eq!(pairs[1], ("recieve", "receive"));
        assert_eq!(pairs[2], ("teh", "the"));
    }

    #[test]
    fn test_similarity_threshold() {
        // "hello" and "world" are very different
        let sim = jaro_winkler("hello", "world");
        assert!(sim < MIN_SIMILARITY);

        // "recieve" and "receive" are similar
        let sim = jaro_winkler("recieve", "receive");
        assert!(sim >= MIN_SIMILARITY);
    }

    #[test]
    fn test_confidence_below_threshold() {
        let mut engine = LearningEngine::new();
        engine.set_min_confidence(0.9);

        // add a low-confidence correction
        {
            let mut cache = engine.corrections.write();
            cache.insert(
                "foo".to_string(),
                CachedCorrection {
                    corrected: "bar".to_string(),
                    confidence: 0.5, // below threshold
                },
            );
        }

        let (result, applied) = engine.apply_corrections("test foo here");

        // should not be applied
        assert_eq!(result, "test foo here");
        assert!(applied.is_empty());
    }
}
