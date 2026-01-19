//
// VolumeManager.swift
// Flow
//
// Manages system volume during recording to prevent audio feedback/echo.
// Mutes system audio when recording starts, restores when recording stops.
// Based on Wispr Flow's VolumeManager pattern.
//

import AudioToolbox
import CoreAudio
import Foundation

final class VolumeManager {
    private var wasMutedBeforeRecording = false
    private var previousVolume: Float32 = 0.0
    private var isCurrentlyMuting = false

    // MARK: - Public API

    /// Call when recording starts to mute system audio
    func muteForRecording() {
        guard !isCurrentlyMuting else { return }

        // Save current state before muting
        wasMutedBeforeRecording = isMuted()
        previousVolume = getVolume()

        // Mute the system
        if !wasMutedBeforeRecording {
            setMuted(true)
        }

        isCurrentlyMuting = true
    }

    /// Call when recording stops to restore previous audio state
    func restoreAfterRecording() {
        guard isCurrentlyMuting else { return }

        // Only unmute if it wasn't muted before we started
        if !wasMutedBeforeRecording {
            setMuted(false)
        }

        isCurrentlyMuting = false
    }

    // MARK: - CoreAudio Helpers

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else { return nil }
        return deviceID
    }

    private func isMuted() -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { return false }

        return muted != 0
    }

    private func setMuted(_ muted: Bool) {
        guard let deviceID = getDefaultOutputDevice() else { return }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
    }

    private func getVolume() -> Float32 {
        guard let deviceID = getDefaultOutputDevice() else { return 0.0 }

        var volume: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else { return 0.0 }

        return volume
    }
}
