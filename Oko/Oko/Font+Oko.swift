import SwiftUI

extension Font {
    // MARK: - Standard System Fonts (Readable)
    
    /// Use this for almost everything (Titles, Buttons, Lists)
    static func okoBold(size: CGFloat) -> Font {
        return Font.system(size: size, weight: .bold, design: .default)
    }
    
    /// Use this for subtle text
    static func okoItalic(size: CGFloat) -> Font {
        return Font.system(size: size, weight: .medium, design: .default).italic()
    }

    // MARK: - The Brand Font (Only for "OKO")
    
    /// ONLY use this for the word "OKO"
    static func okoBrand(size: CGFloat) -> Font {
        // Uses your custom Ladislav-Bold.ttf
        return Font.custom("Ladislav-Bold", size: size)
    }
}
