#if canImport(SwiftUI)
import SwiftUI

public extension EnvironmentValues {
    /// The feature flag resolver available to the current SwiftUI view hierarchy.
    ///
    /// When no explicit value is injected, SwiftUI uses an empty `FeatureFlags`
    /// instance, so all lookups fall back to each feature's `defaultValue`.
    @Entry var featureFlags: FeatureFlags = FeatureFlags()
}

@available(iOS 14.0, *)
public extension View {
    /// Injects a `FeatureFlags` resolver into the view hierarchy.
    ///
    /// Descendant views can read the resolver with:
    ///
    /// ```swift
    /// @Environment(\.featureFlags) private var featureFlags
    /// ```
    ///
    /// - Parameter featureFlags: The resolver to expose to the view hierarchy.
    /// - Returns: A view configured with the provided resolver in its environment.
    func featureFlags(_ featureFlags: FeatureFlags) -> some View {
        environment(\.featureFlags, featureFlags)
    }
}

@available(iOS 14.0, *)
public extension Scene {
    /// Injects a `FeatureFlags` resolver into the scene environment.
    ///
    /// This is useful when the same resolver should be shared by the entire app scene.
    ///
    /// - Parameter featureFlags: The resolver to expose to the scene hierarchy.
    /// - Returns: A scene configured with the provided resolver in its environment.
    func featureFlags(_ featureFlags: FeatureFlags) -> some Scene {
        environment(\.featureFlags, featureFlags)
    }
}
#endif
