import Foundation

public struct ConfigurationLoader {
    public static let fileName = ".avie.json"

    public static func load(from directory: URL) throws -> AvieConfiguration {
        let fileURL = directory.appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AvieConfiguration()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AvieConfiguration.self, from: data)
    }
}
