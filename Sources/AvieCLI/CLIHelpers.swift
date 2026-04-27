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

/// Converts ManifestReader.ManifestData into TargetDeclaration objects.
///
/// Bug 7 Fix: ManifestTargetDependency is now a proper enum (discriminated union).
/// The packageIdentity computed property on each case returns the cross-package
/// identity string, or nil for intra-package target dependencies.
func buildTargets(
    from manifestData: ManifestReader.ManifestData,
    rootIdentity: PackageIdentity
) -> [TargetDeclaration] {
    manifestData.targets.map { targetData in
        TargetDeclaration(
            id: targetData.name,
            kind: targetKind(from: targetData.type),
            packageIdentity: rootIdentity,
            // Use the packageIdentity computed property from the new enum model.
            // This correctly returns the cross-package reference for .product and
            // .byName cases, and nil for .target (intra-package) cases.
            packageDependencies: targetData.dependencies.compactMap { dep in
                dep.packageIdentity
            }.map(PackageIdentity.init)
        )
    }
}
