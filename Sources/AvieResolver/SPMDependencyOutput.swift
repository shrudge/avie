import AvieCore

public struct SPMDependencyOutput: Codable {
    public let name: String
    public let url: String
    public let version: String
    public let path: String
    public let dependencies: [SPMDependencyOutput]

    public init(
        name: String,
        url: String,
        version: String,
        path: String,
        dependencies: [SPMDependencyOutput]
    ) {
        self.name = name
        self.url = url
        self.version = version
        self.path = path
        self.dependencies = dependencies
    }
}
