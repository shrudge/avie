import Foundation
import AvieCore

struct Banner {
    private static let R = "\u{001B}[0m"
    private static let FB = "\u{001B}[48;2;76;93;109m"    // Fabric: Blue-Grey
    private static let FF = "\u{001B}[38;2;55;70;84m"
    private static let NB = "\u{001B}[48;2;19;28;75m"    // Dark Navy Stripe
    private static let SB = "\u{001B}[48;2;122;178;211m"  // Sky Blue Stripe
    private static let SF = "\u{001B}[38;2;88;145;175m"
    private static let BOLD = "\u{001B}[1m"
    private static let NAVY = "\u{001B}[38;2;19;28;75m"   // Navy Blue foreground
    private static let WHITE = "\u{001B}[97m"
    private static let GRAY = "\u{001B}[38;2;160;175;185m"
    
    private static let W_SOLID = String(repeating: " ", count: 24)
    
    private static let wordMarkLines = [
        "  █████   █     █  █████  ███████ ",
        " █     █  █     █    █    █       ",
        " █     █  █     █    █    █       ",
        " ███████  █     █    █    ██████  ",
        " █     █   █   █     █    █       ",
        " █     █    █ █      █    █       ",
        " █     █     █     █████  ███████ "
    ]
    
    static func render() -> String {
        let insignia = [
            "\(FB)\(FF)\(W_SOLID)\(R)",
            "\(FB)\(FF)\(W_SOLID)\(R)",
            "\(NB)\(W_SOLID)\(R)",
            "\(NB)\(W_SOLID)\(R)",
            "\(FB)\(FF)\(W_SOLID)\(R)",
            "\(SB)\(SF)\(W_SOLID)\(R)",
            "\(FB)\(FF)\(W_SOLID)\(R)",
            "\(NB)\(W_SOLID)\(R)",
            "\(NB)\(W_SOLID)\(R)",
            "\(FB)\(FF)\(W_SOLID)\(R)",
            "\(FB)\(FF)\(W_SOLID)\(R)"
        ]
        
        var output = "\n"
        let pad = "               "
        
        for i in 0..<insignia.count {
            output += pad + insignia[i]
            
            // Vertically center the 7-line word mark in the 11-line insignia
            let wordMarkIndex = i - 2
            if wordMarkIndex >= 0 && wordMarkIndex < wordMarkLines.count {
                output += "    \(NAVY)\(BOLD)\(wordMarkLines[wordMarkIndex])\(R)\n"
            } else {
                output += "    \n"
            }
        }
        
        output += "\n"
        output += "\(pad)                   \(GRAY)Swift package graph diagnostics & audit tool.\(R)\n"
        output += "\(pad)                   \(GRAY)Version \(WHITE)\(avieToolVersion)\(R)\(GRAY) • Graph-provable findings.\(R)\n\n"
        
        return output
    }
}
