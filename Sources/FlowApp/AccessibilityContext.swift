//
// AccessibilityContext.swift
// Flow
//
// Extracts context from the currently focused text field via macOS Accessibility APIs.
// Provides surrounding text context to improve transcription accuracy.
// Based on Wispr Flow's FocusChangeDetector + AX API pattern.
//
// Requires "Accessibility" permission in System Settings > Privacy & Security.
//

import ApplicationServices
import AppKit
import Foundation

/// Context extracted from the focused text element
struct TextFieldContext {
    /// Text currently selected (highlighted) in the field
    let selectedText: String?

    /// Text before the cursor/selection
    let beforeText: String?

    /// Text after the cursor/selection
    let afterText: String?

    /// The full value of the text field
    let fullText: String?

    /// Placeholder/label of the field if available
    let placeholder: String?

    /// Role description (e.g., "text field", "text area")
    let roleDescription: String?

    /// Bundle ID of the app containing this field
    let appBundleId: String?

    /// Human-readable context summary for transcription prompt
    var contextSummary: String? {
        var parts: [String] = []

        if let before = beforeText, !before.isEmpty {
            // Take last ~100 chars of context before cursor
            let trimmed = before.count > 100 ? "..." + String(before.suffix(100)) : before
            parts.append("Text before cursor: \"\(trimmed)\"")
        }

        if let selected = selectedText, !selected.isEmpty {
            parts.append("Selected text: \"\(selected)\"")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    static let empty = TextFieldContext(
        selectedText: nil,
        beforeText: nil,
        afterText: nil,
        fullText: nil,
        placeholder: nil,
        roleDescription: nil,
        appBundleId: nil
    )
}

final class AccessibilityContext {
    /// Extract context from the currently focused text element
    static func extractFocusedTextContext() -> TextFieldContext {
        guard let focusedElement = getFocusedElement() else {
            return .empty
        }

        let role = getStringAttribute(focusedElement, kAXRoleAttribute as CFString)

        // Only extract from text-input elements
        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]

        guard let role, textRoles.contains(role) else {
            return .empty
        }

        let fullText = getStringAttribute(focusedElement, kAXValueAttribute as CFString)
        let selectedText = getSelectedText(focusedElement)
        let placeholder = getStringAttribute(focusedElement, kAXPlaceholderValueAttribute as CFString)
        let roleDescription = getStringAttribute(focusedElement, kAXRoleDescriptionAttribute as CFString)

        // Get text before and after selection
        var beforeText: String?
        var afterText: String?

        if let fullText, let range = getSelectedTextRange(focusedElement) {
            let startIndex = range.location
            let endIndex = range.location + range.length

            if startIndex > 0 && startIndex <= fullText.count {
                let idx = fullText.index(fullText.startIndex, offsetBy: min(startIndex, fullText.count))
                beforeText = String(fullText[..<idx])
            }

            if endIndex < fullText.count {
                let idx = fullText.index(fullText.startIndex, offsetBy: min(endIndex, fullText.count))
                afterText = String(fullText[idx...])
            }
        }

        // Get the app bundle ID
        var appBundleId: String?
        if let app = NSWorkspace.shared.frontmostApplication {
            appBundleId = app.bundleIdentifier
        }

        return TextFieldContext(
            selectedText: selectedText,
            beforeText: beforeText,
            afterText: afterText,
            fullText: fullText,
            placeholder: placeholder,
            roleDescription: roleDescription,
            appBundleId: appBundleId
        )
    }

    // MARK: - Private Helpers

    private static func getFocusedElement() -> AXUIElement? {
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let element = focusedElement else { return nil }
        return (element as! AXUIElement)
    }

    private static func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue
    }

    private static func getSelectedText(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard result == .success, let text = value as? String else { return nil }
        return text
    }

    private static func getSelectedTextRange(_ element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let rangeValue = value else { return nil }

        // AXValue contains a CFRange
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }

        return NSRange(location: range.location, length: range.length)
    }
}
