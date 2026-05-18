# FeatureFlagsKit

`FeatureFlagsKit` is a lightweight Swift package for defining, composing, and resolving feature flags in iOS applications.

It is designed for local and in-app feature management, with explicit source precedence, environment-aware configuration, persistent local overrides, and SwiftUI integration.

## Features

- Typed feature definitions via Swift enums
- Per-feature default values
- Clear source precedence model
- Environment-based composition for production and non-production builds
- In-memory and persistent override sources
- Compact DSL for declaring flag states
- SwiftUI environment integration
- Support for QA and developer-facing override screens

## Requirements

- iOS 13.0+
- SwiftUI helpers are available where SwiftUI can be imported
- `View.featureFlags(_:)` and `Scene.featureFlags(_:)` require iOS 14.0+

## Installation

Add the package to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/Livsy90/FeatureFlagsKit.git", from: "1.0.0")
]
```

Then add `FeatureFlagsKit` to your target dependencies.

## Core Concepts

### 1. Define Features

Each feature conforms to `Feature`. In most cases, a `String`-backed enum is the simplest option.

```swift
import FeatureFlagsKit

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
```

For `String`-backed enums, `FeatureFlagsKit` provides default implementations for:

- `key`
- `description`

You only need to override `description` if you want something more readable than the raw value.

### 2. Resolve Flags

`FeatureFlags` is the main read API:

```swift
let flags = FeatureFlags()

if flags.isEnabled(AppFeature.newOnboarding) {
    // Show new onboarding
}
```

If no configured source contains a value for the feature, `FeatureFlags` falls back to `feature.defaultValue`.

### 3. Configure Sources

A feature can be resolved from one or more sources. Each source has a priority. Higher-priority sources win.

Built-in priorities:

| Priority | Meaning |
| --- | --- |
| `business` | Base app configuration |
| `testing` | Non-production test configuration |
| `simulator` | Simulator-only configuration |
| `localOverrides` | Local developer / QA overrides |
| `forced` | Non-overridable final value |

Resolution is deterministic: sources are sorted by descending priority, and the first source that knows a key wins.

## Declaring Configuration

Use `FlagConfiguration` with the result-builder DSL:

```swift
let businessConfiguration = FlagConfiguration<AppFeature> {
    enable(.newOnboarding)
    disable(.redesignedCheckout)
}

let testingConfiguration = FlagConfiguration<AppFeature> {
    enable(.redesignedCheckout)
}
```

You can convert a configuration into a source explicitly:

```swift
let source = businessConfiguration.makeSource(priority: .business)
let flags = FeatureFlags(sources: [source])
```

## Environment-Based Composition

`FeatureFlagsConfigurator` composes the source list for you.

```swift
let localOverrides = PersistentOverrideFeatureFlagSource(
    defaults: .standard,
    storageKey: "feature_flags.local_overrides"
)

let configurator = FeatureFlagsConfigurator<AppFeature>(
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

let flags = configurator.makeFeatureFlags()
```

### Production Behavior

In `.production`, only the `businessConfiguration` is applied.

This means:

- no `testingConfiguration`
- no `simulatorConfiguration`
- no `localOverridesSource`
- no `forcedConfiguration`

### Non-Production Behavior

In `.nonProduction`, the configurator applies:

1. `businessConfiguration`
2. `testingConfiguration`
3. `simulatorConfiguration` when `isSimulator == true`
4. `localOverridesSource` when provided
5. `forcedConfiguration`

That order matches the priority rules in the package.

## Built-In Sources

### DictionaryFeatureFlagSource

An in-memory source for static configuration, tests, and ad hoc overrides.

```swift
let source = DictionaryFeatureFlagSource(
    states: [
        enable(.newOnboarding),
        disable(.redesignedCheckout)
    ],
    priority: .business
)
```

You can also write values directly:

```swift
source.setValue(true, for: AppFeature.debugLogging)
```

### PersistentOverrideFeatureFlagSource

A `UserDefaults`-backed source intended for developers, QA, and local device testing.

```swift
let overrides = PersistentOverrideFeatureFlagSource(
    defaults: .standard,
    storageKey: "feature_flags.local_overrides"
)

overrides.setOverride(true, for: AppFeature.debugLogging)
overrides.removeOverride(for: AppFeature.debugLogging)
```

Overrides persist across launches and participate in normal priority resolution.

## Practical Example

```swift
func runUsageExample() {
    let businessConfiguration = FlagConfiguration<AppFeature> {
        enable(.newOnboarding)
        disable(.redesignedCheckout)
    }

    let testingConfiguration = FlagConfiguration<AppFeature> {
        enable(.redesignedCheckout)
    }

    let localOverrides = PersistentOverrideFeatureFlagSource(
        defaults: .standard,
        storageKey: "feature_flags.local_overrides"
    )

    let configurator = FeatureFlagsConfigurator<AppFeature>(
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

    let flags = configurator.makeFeatureFlags()

    if flags.isEnabled(AppFeature.newOnboarding) {
        print("Show new onboarding")
    } else {
        print("Show legacy onboarding")
    }
}
```

## SwiftUI Integration

When SwiftUI is available, the package adds `FeatureFlags` to `EnvironmentValues`.

### Inject Flags Into a View Hierarchy

```swift
import SwiftUI
import FeatureFlagsKit

@available(iOS 14.0, *)
struct RootView: View {
    let flags: FeatureFlags

    var body: some View {
        NavigationView {
            OnboardingView()
        }
        .featureFlags(flags)
    }
}
```

### Read Flags From the Environment

```swift
@available(iOS 14.0, *)
struct OnboardingView: View {
    @Environment(\.featureFlags) private var flags

    var body: some View {
        Group {
            if flags.isEnabled(AppFeature.newOnboarding) {
                Text("New onboarding")
            } else {
                Text("Legacy onboarding")
            }
        }
    }
}
```

### Scene-Level Injection

If you want the same resolver for the full app scene:

```swift
@available(iOS 14.0, *)
@main
struct DemoApp: App {
    let flags = FeatureFlags()

    var body: some Scene {
        WindowGroup {
            RootView(flags: flags)
        }
        .featureFlags(flags)
    }
}
```

## QA / Developer Override Screen

The package includes a SwiftUI example screen that demonstrates a simple internal flag panel:

- one section for technical flags
- one section for business flags
- toggles that write to `PersistentOverrideFeatureFlagSource`

This pattern is useful when you want:

- QA to verify flows without a new build
- developers to expose debug-only switches
- non-production builds to support local experimentation

The example lives in:

- `Sources/FeatureFlagsKit/Examples/FeatureFlagOverrideScreenExample.swift`

## Testing Strategy

The included test suite covers the main resolution rules:

- business configuration enables and disables flags correctly
- missing values fall back to `defaultValue`
- local overrides beat business configuration
- duplicate states use last-write-wins semantics
- forced configuration beats local overrides
- production excludes debug-only sources
- simulator configuration is only applied on simulator
- persistent overrides are loaded from `UserDefaults`

This makes the package suitable for deterministic unit testing.

## Thread Safety

The package is designed for synchronous in-memory reads and uses locking internally for mutable shared state.

Thread-safe types include:

- `FeatureFlags`
- `DictionaryFeatureFlagSource`
- `PersistentOverrideFeatureFlagSource`

This allows flags to be read from UI code while sources are updated from debug tools or test helpers.

## Design Notes

- The package is intentionally local-first. It does not include networking or remote config providers.
- Source precedence is explicit and encoded in `FeatureFlagPriority`.
- Features are typed rather than stringly-typed at call sites.
- `forced` configuration gives you a final safety layer when something must not be overridden.

## Example Use Cases

- rolling out a new onboarding flow
- keeping debug-only instrumentation behind internal switches
- enabling test features only in non-production builds
- exposing local overrides for QA on simulator or device
- forcing a feature off during a risky release
