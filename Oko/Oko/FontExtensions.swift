import SwiftUI

extension Font {
    // MARK: - Standard Text Fonts
    
    /// Use this for bold text (Titles, Buttons, Headers)
    static func okoBold(size: CGFloat) -> Font {
        return Font.custom("Ladislav-Bold", size: size)
    }
    
    /// Use this for italic/subtle text
    static func okoItalic(size: CGFloat) -> Font {
        return Font.custom("Ladislav", size: size).italic()
    }

    // MARK: - Brand Font
    
    /// ONLY use this for the word "OKO"
    static func okoBrand(size: CGFloat) -> Font {
        return Font.custom("Ladislav-Bold", size: size)
    }
}
