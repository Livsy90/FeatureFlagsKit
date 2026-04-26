import Foundation

enum AppFeature: String, Feature {
    case newOnboarding
    case redesignedCheckout
    case debugLogging

    var description: String {
        switch self {
        case .newOnboarding:
            "Enables the new onboarding flow"
        case .redesignedCheckout:
            "Enables the redesigned checkout flow"
        case .debugLogging:
            "Enables additional debug logging"
        }
    }

    var defaultValue: Bool {
        switch self {
        case .newOnboarding, .redesignedCheckout, .debugLogging:
            false
        }
    }
}

let businessConfiguration = FlagConfiguration<AppFeature> {
    enable(AppFeature.newOnboarding)
    disable(AppFeature.redesignedCheckout)
}

let testingConfiguration = FlagConfiguration<AppFeature> {
    enable(AppFeature.redesignedCheckout)
}

let localOverrides = PersistentOverrideFeatureFlagSource(
    defaults: .standard,
    storageKey: "feature_flags.local_overrides"
)

let configurator = FeatureFlagsConfigurator(
    environment: .nonProduction,
    isSimulator: true,
    localOverridesSource: localOverrides,
    businessConfiguration: businessConfiguration,
    testingConfiguration: testingConfiguration,
    simulatorConfiguration: .empty,
    forcedConfiguration: FlagConfiguration<AppFeature> {
        disable(AppFeature.debugLogging)
    }
)

func runUsageExample() {
    let flags = configurator.makeFeatureFlags()

    if flags.isEnabled(AppFeature.newOnboarding) {
        print("Show new onboarding")
    } else {
        print("Show legacy onboarding")
    }

    localOverrides.setOverride(true, for: AppFeature.debugLogging)

    if flags.isEnabled(AppFeature.debugLogging) {
        print("Verbose logs are enabled")
    }
}
