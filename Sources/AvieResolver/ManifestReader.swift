import Foundation
import AvieCore

public final class ManifestReader {
    private let packageDirectory: URL

    public init(packageDirectory: URL) {
        self.packageDirectory = packageDirectory
    }

    public struct ManifestData: Codable {
        public let name: String
        public let targets: [ManifestTarget]
    }

    public struct ManifestTarget: Codable {
        public let name: String
        public let type: String
        public let dependencies: [ManifestTargetDependency]
    }

    public struct ManifestTargetDependency: Codable {
        public let product: ProductDependency?
        public let byName: [String?]?

        public struct ProductDependency: Codable {
            public let name: String
            public let package: String
        }

        enum CodingKeys: String, CodingKey {
            case product
            case byName
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let productArray = try? container.decode([String?].self, forKey: .product),
               productArray.count >= 2,
               let name = productArray[0],
               let package = productArray[1] {
                self.product = ProductDependency(name: name, package: package)
            } else {
                self.product = nil
            }

            self.byName = try container.decodeIfPresent([String?].self, forKey: .byName)
        }
    }



    public func read() throws -> ManifestData {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["package", "dump-package"]
        process.currentDirectoryURL = packageDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw NSError(domain: "AvieResolver", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "dump-package failed: \(err)"])
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return try JSONDecoder().decode(ManifestData.self, from: data)
    }
}
