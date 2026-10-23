import SwiftUI
import UIKit

@MainActor @Observable final class EditorPreferences {
    var tool: DrawingTool = .pen
    var color: Color = .blue
    var width: Double = 3 { didSet { UserDefaults.standard.set(width, forKey: "inkWidth") } }
    var penStyle: PenStyle = .fountain { didSet { UserDefaults.standard.set(penStyle.rawValue, forKey: "penStyle") } }
    var scribbleToErase = true { didSet { UserDefaults.standard.set(scribbleToErase, forKey: "scribbleToErase") } }
    var scribbleIncludesHighlighter = false { didSet { UserDefaults.standard.set(scribbleIncludesHighlighter, forKey: "scribbleIncludesHighlighter") } }
    var pageScrollDirection: PageScrollDirection = .vertical { didSet { UserDefaults.standard.set(pageScrollDirection.rawValue, forKey: "pageScrollDirection") } }
    var pagePresentation: PagePresentation = .paged { didSet { UserDefaults.standard.set(pagePresentation.rawValue, forKey: "pagePresentation") } }
    var precisionEraser = false
    var pencilOnly = false { didSet { UserDefaults.standard.set(pencilOnly, forKey: "pencilOnly") } }
    init() {
        let defaults = UserDefaults.standard
        pencilOnly = defaults.object(forKey: "pencilOnly") as? Bool ?? UIPencilInteraction.prefersPencilOnlyDrawing
        penStyle = PenStyle(rawValue: defaults.string(forKey: "penStyle") ?? "") ?? .fountain
        if let width = defaults.object(forKey: "inkWidth") as? Double { self.width = min(12, max(0.5, width)) }
        scribbleToErase = defaults.object(forKey: "scribbleToErase") as? Bool ?? true
        scribbleIncludesHighlighter = defaults.bool(forKey: "scribbleIncludesHighlighter")
        pagePresentation = PagePresentation(rawValue: defaults.string(forKey: "pagePresentation") ?? "") ?? .paged
        pageScrollDirection = PageScrollDirection(rawValue: defaults.string(forKey: "pageScrollDirection") ?? "") ?? .vertical
    }
}
