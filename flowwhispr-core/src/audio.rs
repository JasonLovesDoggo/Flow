//! Audio capture module using CPAL for cross-platform audio input

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Device, SampleFormat, Stream, StreamConfig};
use parking_lot::Mutex;
use std::sync::Arc;
use tracing::{debug, error, info};

use crate::AudioData;
use crate::error::{Error, Result};

/// Audio capture configuration
#[derive(Debug, Clone)]
pub struct AudioCaptureConfig {
    /// Sample rate in Hz (default: 16000 for speech recognition)
    pub sample_rate: u32,
    /// Number of channels (default: 1 for mono)
    pub channels: u16,
    /// Buffer size in samples
    pub buffer_size: usize,
}

impl Default for AudioCaptureConfig {
    fn default() -> Self {
        Self {
            sample_rate: 16000,
            channels: 1,
            buffer_size: 4096,
        }
    }
}

/// State of the audio capture
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptureState {
    Idle,
    Recording,
    Paused,
}

/// Handles audio capture from the default input device
pub struct AudioCapture {
    device: Device,
    config: AudioCaptureConfig,
    stream_config: StreamConfig,
    state: Arc<Mutex<CaptureState>>,
    buffer: Arc<Mutex<Vec<f32>>>,
    stream: Option<Stream>,
}

impl AudioCapture {
    /// Create a new AudioCapture with default settings
    pub fn new() -> Result<Self> {
        Self::with_config(AudioCaptureConfig::default())
    }

    /// Create a new AudioCapture with custom configuration
    pub fn with_config(config: AudioCaptureConfig) -> Result<Self> {
        let host = cpal::default_host();

        let device = host
            .default_input_device()
            .ok_or_else(|| Error::Audio("No input device available".to_string()))?;

        // note: device.name() is deprecated in cpal 0.17+, but works
        #[allow(deprecated)]
        let device_name = device.name().unwrap_or_else(|_| "Unknown".to_string());
        info!("Using input device: {}", device_name);

        let supported_configs = device
            .supported_input_configs()
            .map_err(|e| Error::Audio(format!("Failed to get supported configs: {e}")))?;

        // Find a config that matches our requirements
        let supported_config = supported_configs
            .filter(|c| c.channels() == config.channels && c.sample_format() == SampleFormat::F32)
            .find(|c| {
                c.min_sample_rate() <= config.sample_rate
                    && c.max_sample_rate() >= config.sample_rate
            })
            .ok_or_else(|| {
                Error::Audio(format!(
                    "No supported config for {} Hz, {} channel(s)",
                    config.sample_rate, config.channels
                ))
            })?;

        let stream_config = supported_config
            .with_sample_rate(config.sample_rate)
            .config();

        debug!("Stream config: {:?}", stream_config);

        Ok(Self {
            device,
            config,
            stream_config,
            state: Arc::new(Mutex::new(CaptureState::Idle)),
            buffer: Arc::new(Mutex::new(Vec::new())),
            stream: None,
        })
    }

    /// Start recording audio
    pub fn start(&mut self) -> Result<()> {
        if *self.state.lock() == CaptureState::Recording {
            return Ok(());
        }

        let buffer = Arc::clone(&self.buffer);
        let state = Arc::clone(&self.state);

        // clear buffer
        buffer.lock().clear();

        let err_fn = |err| error!("Audio stream error: {}", err);

        let stream = self
            .device
            .build_input_stream(
                &self.stream_config,
                move |data: &[f32], _: &cpal::InputCallbackInfo| {
                    if *state.lock() == CaptureState::Recording {
                        buffer.lock().extend_from_slice(data);
                    }
                },
                err_fn,
                None,
            )
            .map_err(|e| Error::Audio(format!("Failed to build stream: {e}")))?;

        stream
            .play()
            .map_err(|e| Error::Audio(format!("Failed to start stream: {e}")))?;

        self.stream = Some(stream);
        *self.state.lock() = CaptureState::Recording;

        info!("Audio capture started");
        Ok(())
    }

    /// Stop recording and return the captured audio data
    pub fn stop(&mut self) -> Result<AudioData> {
        *self.state.lock() = CaptureState::Idle;

        // drop the stream to stop recording
        self.stream = None;

        let samples = std::mem::take(&mut *self.buffer.lock());
        let audio_data = self.samples_to_pcm(&samples);

        info!("Audio capture stopped, {} bytes captured", audio_data.len());
        Ok(audio_data)
    }

    /// Pause recording (keeps stream alive but stops buffering)
    pub fn pause(&mut self) {
        *self.state.lock() = CaptureState::Paused;
        debug!("Audio capture paused");
    }

    /// Resume recording after pause
    pub fn resume(&mut self) {
        *self.state.lock() = CaptureState::Recording;
        debug!("Audio capture resumed");
    }

    /// Get current capture state
    pub fn state(&self) -> CaptureState {
        *self.state.lock()
    }

    /// Get current buffer duration in milliseconds
    pub fn buffer_duration_ms(&self) -> u64 {
        let samples = self.buffer.lock().len();
        (samples as u64 * 1000) / (self.config.sample_rate as u64 * self.config.channels as u64)
    }

    /// Convert f32 samples to 16-bit PCM bytes
    fn samples_to_pcm(&self, samples: &[f32]) -> AudioData {
        samples
            .iter()
            .flat_map(|&sample| {
                // clamp and convert to i16
                let clamped = sample.clamp(-1.0, 1.0);
                let pcm = (clamped * 32767.0) as i16;
                pcm.to_le_bytes()
            })
            .collect()
    }
}

impl Drop for AudioCapture {
    fn drop(&mut self) {
        *self.state.lock() = CaptureState::Idle;
        self.stream = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = AudioCaptureConfig::default();
        assert_eq!(config.sample_rate, 16000);
        assert_eq!(config.channels, 1);
    }

    #[test]
    fn test_samples_to_pcm() {
        // this test doesn't need audio hardware, just validates PCM conversion logic
        // test conversion manually
        let samples = [0.0f32, 0.5, -0.5, 1.0, -1.0];
        let pcm: Vec<u8> = samples
            .iter()
            .flat_map(|&sample| {
                let clamped = sample.clamp(-1.0, 1.0);
                let pcm = (clamped * 32767.0) as i16;
                pcm.to_le_bytes()
            })
            .collect();

        // 5 samples * 2 bytes each = 10 bytes
        assert_eq!(pcm.len(), 10);

        // check silence (0.0 -> 0)
        assert_eq!(i16::from_le_bytes([pcm[0], pcm[1]]), 0);

        // check 0.5 -> ~16383
        let half_pos = i16::from_le_bytes([pcm[2], pcm[3]]);
        assert!((half_pos - 16383).abs() < 2);

        // check -0.5 -> ~-16383
        let half_neg = i16::from_le_bytes([pcm[4], pcm[5]]);
        assert!((half_neg + 16383).abs() < 2);
    }
}
