import Foundation
import Testing
@testable import FeatureFlagsKit

private enum TestFeature: String, Feature {
    case newOnboarding
    case redesignedCheckout
    case internalExperiment

    var defaultValue: Bool {
        switch self {
        case .newOnboarding:
            false
        case .redesignedCheckout:
            true
        case .internalExperiment:
            false
        }
    }
}
@Test func businessConfigurationEnablesFeature() {
    let flags = FeatureFlags(
        sources: [
            FlagConfiguration<TestFeature> {
                enable(TestFeature.newOnboarding)
                disable(TestFeature.redesignedCheckout)
            }
            .makeSource(priority: .business)
        ]
    )

    #expect(flags.isEnabled(TestFeature.newOnboarding))
    #expect(!flags.isEnabled(TestFeature.redesignedCheckout))
}

@Test func unknownFeatureUsesFeatureDefaultValue() {
    let flags = FeatureFlags()

    #expect(!flags.isEnabled(TestFeature.internalExperiment))
    #expect(flags.isEnabled(TestFeature.redesignedCheckout))
}

@Test func localOverrideBeatsBusinessConfiguration() {
    let business = FlagConfiguration<TestFeature> {
        disable(TestFeature.newOnboarding)
    }
    .makeSource(priority: .business)

    let overrides = DictionaryFeatureFlagSource(
        states: [enable(TestFeature.newOnboarding)],
        priority: .localOverrides
    )

    let flags = FeatureFlags(sources: [business, overrides])

    #expect(flags.isEnabled(TestFeature.newOnboarding))
}

@Test func duplicateFeatureStatesUseLastValue() {
    let source = FlagConfiguration<TestFeature> {
        enable(TestFeature.newOnboarding)
        disable(TestFeature.newOnboarding)
    }
    .makeSource(priority: .business)

    let flags = FeatureFlags(sources: [source])

    #expect(!flags.isEnabled(TestFeature.newOnboarding))
}

@Test func forcedConfigurationBeatsLocalOverride() {
    let overrides = DictionaryFeatureFlagSource(
        states: [enable(TestFeature.newOnboarding)],
        priority: .localOverrides
    )

    let forced = FlagConfiguration<TestFeature> {
        disable(TestFeature.newOnboarding)
    }
    .makeSource(priority: .forced)

    let flags = FeatureFlags(sources: [overrides, forced])

    #expect(!flags.isEnabled(TestFeature.newOnboarding))
}

@Test func productionDoesNotIncludeDebugOverrides() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)

    let overrides = PersistentOverrideFeatureFlagSource(
        defaults: defaults,
        storageKey: "feature_flags.local_overrides",
        priority: .localOverrides
    )
    overrides.setOverride(true, for: TestFeature.newOnboarding)

    let configurator = FeatureFlagsConfigurator<TestFeature>(
        environment: .production,
        localOverridesSource: overrides,
        businessConfiguration: FlagConfiguration {
            disable(TestFeature.newOnboarding)
        },
        forcedConfiguration: .empty
    )

    let flags = configurator.makeFeatureFlags()

    #expect(!flags.isEnabled(TestFeature.newOnboarding))
}

@Test func localOverridesBeatTestingAndSimulatorConfigurations() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)

    let overrides = PersistentOverrideFeatureFlagSource(
        defaults: defaults,
        storageKey: "feature_flags.local_overrides",
        priority: .localOverrides
    )
    overrides.setOverride(false, for: TestFeature.internalExperiment)

    let configurator = FeatureFlagsConfigurator<TestFeature>(
        environment: .nonProduction,
        isSimulator: true,
        localOverridesSource: overrides,
        businessConfiguration: .empty,
        testingConfiguration: FlagConfiguration {
            enable(TestFeature.internalExperiment)
        },
        simulatorConfiguration: FlagConfiguration {
            enable(TestFeature.internalExperiment)
        },
        forcedConfiguration: .empty
    )

    let flags = configurator.makeFeatureFlags()

    #expect(!flags.isEnabled(TestFeature.internalExperiment))
}

@Test func simulatorConfigurationIsAppliedOnlyOnSimulator() {
    let configurator = FeatureFlagsConfigurator<TestFeature>(
        environment: .nonProduction,
        isSimulator: false,
        businessConfiguration: .empty,
        testingConfiguration: .empty,
        simulatorConfiguration: FlagConfiguration {
            enable(TestFeature.internalExperiment)
        },
        forcedConfiguration: .empty
    )

    let nonSimulatorFlags = configurator.makeFeatureFlags()
    #expect(!nonSimulatorFlags.isEnabled(TestFeature.internalExperiment))

    let simulatorConfigurator = FeatureFlagsConfigurator<TestFeature>(
        environment: .nonProduction,
        isSimulator: true,
        businessConfiguration: .empty,
        testingConfiguration: .empty,
        simulatorConfiguration: FlagConfiguration {
            enable(TestFeature.internalExperiment)
        },
        forcedConfiguration: .empty
    )

    let simulatorFlags = simulatorConfigurator.makeFeatureFlags()
    #expect(simulatorFlags.isEnabled(TestFeature.internalExperiment))
}

@Test func persistentOverridesAreLoadedFromUserDefaults() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defaults.set(["redesignedCheckout": true], forKey: "feature_flags.local_overrides")

    let source = PersistentOverrideFeatureFlagSource(
        defaults: defaults,
        storageKey: "feature_flags.local_overrides"
    )

    #expect(source.value(forKey: TestFeature.redesignedCheckout.key) == true)
}
