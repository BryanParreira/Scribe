import ApplicationServices
import Foundation

/// File overview:
/// Extracts readable text from browser webpages via the macOS Accessibility tree, bypassing
/// screenshot OCR entirely. AX-based extraction is instant (no image capture, no Vision pipeline)
/// and produces clean, structured text rather than raw OCR output that can include UI chrome.
///
/// Why AX over OCR for browsers:
/// Modern browsers expose their rendered DOM as an `AXWebArea` subtree. Walking that tree and
/// collecting `AXStaticText` values gives the article/page body without menu bars, tab strips, or
/// decorative images that pollute screenshot-derived text. The result is a much higher signal-to-noise
/// ratio for the prompt's "nearby on screen" section.
///
/// Limitations:
/// - Only works for apps that publish an AXWebArea (Safari, Chrome, Firefox, Arc, Brave, Edge).
/// - Pages that render entirely via canvas or WebGL have no AX text nodes.
/// - The walk is bounded by depth and character limit to keep it sub-millisecond.
nonisolated enum AXWebContentReader {
    private static let maxDepth = 12
    private static let maxCharacters = 2_000
    private static let minUsableCharacters = 80

    /// Attempts to read readable webpage text from the AX tree rooted at `element`.
    /// Climbs toward the window looking for an `AXWebArea`, then depth-first collects
    /// `AXStaticText` leaf values. Returns `nil` when the element is not inside a web view,
    /// when permissions are missing, or when the extracted text is too short to be useful.
    static func readWebContent(nearElement element: AXUIElement) -> String? {
        guard let webArea = findWebArea(startingFrom: element) else { return nil }
        var collected = ""
        collectText(from: webArea, depth: 0, into: &collected)
        let cleaned = cleanExtractedText(collected)
        return cleaned.count >= minUsableCharacters ? cleaned : nil
    }

    // MARK: - AX tree walking

    /// Climbs the AX parent chain (max 8 hops) looking for a node with role AXWebArea.
    private static func findWebArea(startingFrom element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement = element
        for _ in 0..<8 {
            if role(of: current) == "AXWebArea" { return current }
            guard let parent = parentElement(of: current) else { break }
            current = parent
        }
        return nil
    }

    /// Depth-first text collection. Prefers `AXValue` on leaf nodes; recurses into children
    /// for container nodes. Stops when the character budget is exhausted.
    private static func collectText(from element: AXUIElement, depth: Int, into result: inout String) {
        guard depth < maxDepth, result.count < maxCharacters else { return }

        let nodeRole = role(of: element)

        // Skip navigation, toolbar, and form elements — they carry UI labels not article text.
        let skippedRoles: Set<String> = [
            "AXToolbar", "AXMenuBar", "AXMenu", "AXMenuItem",
            "AXTabGroup", "AXTab", "AXScrollBar", "AXSplitter",
            "AXImage", "AXButton", "AXCheckBox", "AXRadioButton",
            "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton"
        ]
        if let r = nodeRole, skippedRoles.contains(r) { return }

        // Collect text value from leaf-like nodes.
        if nodeRole == "AXStaticText" || nodeRole == "AXHeading" || nodeRole == "AXLink" {
            if let text = stringAttribute(kAXValueAttribute as CFString, of: element), !text.isEmpty {
                if !result.isEmpty { result += " " }
                result += text
                return // Don't recurse into text nodes
            }
        }

        // Recurse into children.
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return }

        for child in children {
            guard result.count < maxCharacters else { break }
            collectText(from: child, depth: depth + 1, into: &result)
        }
    }

    // MARK: - AX attribute helpers

    private static func role(of element: AXUIElement) -> String? {
        stringAttribute(kAXRoleAttribute as CFString, of: element)
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let string = value as? String, !string.isEmpty
        else { return nil }
        return string
    }

    // MARK: - Text cleanup

    /// Collapses runs of whitespace and newlines, trims, and caps to maxCharacters.
    private static func cleanExtractedText(_ raw: String) -> String {
        var result = raw
        // Collapse multiple spaces/newlines into a single space.
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maxCharacters {
            result = String(result.prefix(maxCharacters))
        }
        return result
    }
}
