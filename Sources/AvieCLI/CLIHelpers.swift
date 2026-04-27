import AvieCore
import AvieResolver

// Shared helpers used by AuditCommand and SnapshotCommand to avoid duplication.

func targetKind(from typeString: String) -> TargetDeclaration.TargetKind {
    switch typeString {
    case "executable": return .executable
    case "test": return .test
    case "plugin": return .plugin
    case "macro": return .macro
    case "system": return .system
    default: return .regular
    }
}

func buildTargets(
    from manifestData: ManifestReader.ManifestData,
    rootIdentity: PackageIdentity
) -> [TargetDeclaration] {
    manifestData.targets.map { targetData in
        TargetDeclaration(
            id: targetData.name,
            kind: targetKind(from: targetData.type),
            packageIdentity: rootIdentity,
            packageDependencies: targetData.dependencies.compactMap { dep in
                dep.product?.package.lowercased()
            }.map(PackageIdentity.init)
        )
    }
}
