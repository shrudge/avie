import ArgumentParser
import AvieCore

@main
struct Avie: ParsableCommand {
    private static let logo: String = "\n\n         \\033[38;2;122;178;211m\\033[1mavie@sentinel\\033[0m\n─────────\u{1B}[38;2;160;175;185m──────────────────────────────────────────────────────────────\u{1B}[0m\n\n         \u{1B}[48;2;76;93;109m\u{1B}[38;2;55;70;84m· · · · · · · · · · · · \u{1B}[0m   \n         \u{1B}[48;2;76;93;109m\u{1B}[38;2;55;70;84m· · · · · · · · · · · · \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mOS:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         \u{1B}[48;2;19;28;75m                        \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mKernel:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         \u{1B}[48;2;19;28;75m                        \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mUptime:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         11726FB\u{1B}[38;2;55;70;84m                        \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mShell:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         \u{1B}[48;2;122;178;211m\u{1B}[38;2;88;145;175m· · · · · · · · · · · · \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mPackages:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         11726FB\u{1B}[38;2;55;70;84m                        \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mProject:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         \u{1B}[48;2;19;28;75m                        \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mRank:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         \u{1B}[48;2;19;28;75m                        \u{1B}[0m   \u{1B}[38;2;122;178;211m\u{1B}[1mStatus:\u{1B}[0m \u{1B}[97mplaceholder\u{1B}[0m\n         \u{1B}[48;2;76;93;109m\u{1B}[38;2;55;70;84m· · · · · · · · · · · · \u{1B}[0m   \n         \u{1B}[48;2;76;93;109m\u{1B}[38;2;55;70;84m· · · · · · · · · · · · \u{1B}[0m   \n\n─────────\u{1B}[38;2;160;175;185m──────────────────────────────────────────────────────────────\u{1B}[0m\n\n\n"

    static let configuration = CommandConfiguration(
        commandName: "avie",
        abstract: "Swift package graph diagnostics tool.",
        version: logo,
        subcommands: [
            AuditCommand.self,
            SuppressCommand.self,
            ExplainCommand.self,
            SnapshotCommand.self,
            DiffCommand.self,
        ],
        defaultSubcommand: AuditCommand.self
    )
}
