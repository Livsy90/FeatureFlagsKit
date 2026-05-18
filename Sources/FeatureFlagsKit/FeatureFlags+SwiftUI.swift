import SwiftUI

enum SwiftUIAppFeature: String, Feature {
    case newOnboarding
    case redesignedCheckout
    case debugBanner

    var description: String {
        switch self {
        case .newOnboarding:
            "Enables the new onboarding flow"
        case .redesignedCheckout:
            "Enables the redesigned checkout flow"
        case .debugBanner:
            "Shows a debug banner in non-production builds"
        }
    }

    var defaultValue: Bool {
        switch self {
        case .newOnboarding, .redesignedCheckout, .debugBanner:
            false
        }
    }
}

private let appFeatureFlags: FeatureFlags = {
    let configurator = FeatureFlagsConfigurator<SwiftUIAppFeature>(
        environment: .nonProduction,
        isSimulator: true,
        businessConfiguration: FlagConfiguration<SwiftUIAppFeature> {
            enable(.newOnboarding)
            disable(.redesignedCheckout)
        },
        testingConfiguration: FlagConfiguration<SwiftUIAppFeature> {
            enable(.debugBanner)
        },
        simulatorConfiguration: .empty,
        forcedConfiguration: .empty
    )

    return configurator.makeFeatureFlags()
}()

@available(iOS 14.0, *)
struct RootView: View {
    var body: some View {
        NavigationView {
            OnboardingView()
        }
        .featureFlags(appFeatureFlags)
    }
}

@available(iOS 14.0, *)
struct OnboardingView: View {
    @Environment(\.featureFlags) private var flags

    var body: some View {
        VStack(spacing: 20) {
            if flags.isEnabled(SwiftUIAppFeature.debugBanner) {
                Text("Debug banner is enabled")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.2))
                    .clipShape(.capsule)
            }

            if flags.isEnabled(SwiftUIAppFeature.newOnboarding) {
                NewOnboardingView()
            } else {
                LegacyOnboardingView()
            }
        }
        .padding()
        .navigationTitle("Feature Flags")
    }
}

private struct NewOnboardingView: View {
    var body: some View {
        Text("New onboarding")
    }
}

private struct LegacyOnboardingView: View {
    var body: some View {
        Text("Legacy onboarding")
    }
}

#Preview {
    if #available(iOS 14.0, *) {
        RootView()
    }
}
