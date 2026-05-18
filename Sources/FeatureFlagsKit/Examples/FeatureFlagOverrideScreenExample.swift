import SwiftUI

/// Feature set used by the grouped toggle screen example.
enum FeatureToggleExampleFlag: String, CaseIterable, Feature {
    case debugLogging
    case verboseNetworking
    case newOnboarding
    case redesignedCheckout

    var description: String {
        switch self {
        case .debugLogging:
            "Enables extra debug logs."
        case .verboseNetworking:
            "Prints network requests and responses."
        case .newOnboarding:
            "Enables the new onboarding flow."
        case .redesignedCheckout:
            "Enables the redesigned checkout flow."
        }
    }

    var defaultValue: Bool {
        false
    }
}

/// Two groups of flags shown on the example screen.
enum FeatureToggleCategory: String, CaseIterable {
    case technical = "Technical Flags"
    case business = "Business Flags"

    var features: [FeatureToggleExampleFlag] {
        switch self {
        case .technical:
            [.debugLogging, .verboseNetworking]
        case .business:
            [.newOnboarding, .redesignedCheckout]
        }
    }
}

/// Persistent store for local flag overrides.
private let featureToggleOverrideSource = PersistentOverrideFeatureFlagSource(
    defaults: .standard,
    storageKey: "feature_flags.grouped_toggle_overrides"
)

/// Resolver used by the example screen and preview.
private let featureToggleExampleFlags: FeatureFlags = {
    let configurator = FeatureFlagsConfigurator<FeatureToggleExampleFlag>(
        environment: .nonProduction,
        isSimulator: true,
        localOverridesSource: featureToggleOverrideSource,
        businessConfiguration: FlagConfiguration<FeatureToggleExampleFlag> {
            disable(.debugLogging)
            disable(.verboseNetworking)
            enable(.newOnboarding)
            disable(.redesignedCheckout)
        },
        testingConfiguration: .empty,
        simulatorConfiguration: .empty,
        forcedConfiguration: .empty
    )

    return configurator.makeFeatureFlags()
}()

/// Simple screen with two sections of toggles for technical and business flags.
@available(iOS 16.0, *)
struct FeatureFlagOverrideScreenExample: View {
    private let flags: FeatureFlags
    private let overrideSource: PersistentOverrideFeatureFlagSource

    init(
        flags: FeatureFlags = featureToggleExampleFlags,
        overrideSource: PersistentOverrideFeatureFlagSource = featureToggleOverrideSource
    ) {
        self.flags = flags
        self.overrideSource = overrideSource
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(FeatureToggleCategory.allCases, id: \.rawValue) { category in
                    Section(category.rawValue) {
                        ForEach(category.features, id: \.rawValue) { feature in
                            Toggle(feature.rawValue, isOn: binding(for: feature))
                        }
                    }
                }
            }
            .navigationTitle("Feature Flags")
        }
    }

    /// Creates a binding that reads the effective value and persists local changes.
    private func binding(for feature: FeatureToggleExampleFlag) -> Binding<Bool> {
        .init(
            get: { flags.isEnabled(feature) },
            set: { overrideSource.setOverride($0, for: feature) }
        )
    }
}

/// Canvas preview for the grouped toggle screen.
@available(iOS 17.0, *)
#Preview {
    FeatureFlagOverrideScreenExample()
}
