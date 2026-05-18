import Foundation

@usableFromInline
func isRunningInSimulator() -> Bool {
#if targetEnvironment(simulator)
    true
#else
    false
#endif
}

/// Describes a feature that can be enabled or disabled by the flag system.
///
/// A feature defines its stable storage key, a human-readable description,
/// and the fallback value that should be used when no source provides
/// an explicit state for that key.
public protocol Feature: Sendable {
    /// A stable, non-localized identifier used for storage and lookup.
    var key: String { get }

    /// A human-readable description intended for debugging, QA, or documentation.
    var description: String { get }

    /// The value returned when no configured source contains this feature.
    var defaultValue: Bool { get }
}

/// Provides convenient defaults for string-backed feature enums.
///
/// When a feature is declared as a `RawRepresentable` enum with `String` raw values,
/// the raw value becomes the storage key and the default description.
public extension Feature where Self: RawRepresentable, RawValue == String {
    var key: String { rawValue }
    var description: String { rawValue }
}

/// Represents the enabled or disabled state of a specific feature.
///
/// This value is primarily used by the configuration DSL and by in-memory sources.
public struct FeatureState<FeatureType: Feature>: Sendable {
    /// The feature whose state is being described.
    public let feature: FeatureType

    /// Indicates whether the feature is enabled.
    public let isEnabled: Bool

    /// Creates a typed feature state.
    ///
    /// - Parameters:
    ///   - feature: The feature definition.
    ///   - isEnabled: The boolean state associated with the feature.
    public init(feature: FeatureType, isEnabled: Bool) {
        self.feature = feature
        self.isEnabled = isEnabled
    }
}

extension FeatureState: Equatable where FeatureType: Equatable {}

/// Defines the precedence of a feature flag source.
///
/// Larger values win over smaller ones during resolution.
public enum FeatureFlagPriority: Int, CaseIterable, Comparable, Sendable {
    /// Base application configuration.
    case business = 0

    /// Test-specific configuration available in non-production environments.
    case testing = 100

    /// Simulator-only configuration available in non-production environments.
    case simulator = 200

    /// Developer or QA overrides persisted locally on the device.
    case localOverrides = 300

    /// A non-overridable configuration that always wins.
    case forced = 400

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A source capable of returning a value for a feature key.
///
/// Sources are resolved by priority. The first source in descending priority order
/// that knows a key wins.
public protocol FeatureFlagSource: Sendable {
    /// The source precedence used during conflict resolution.
    var priority: FeatureFlagPriority { get }

    /// Returns the value for the provided key, or `nil` when the source does not know it.
    ///
    /// - Parameter key: A stable feature key.
    func value(forKey key: String) -> Bool?
}

/// Abstraction used by clients that only need to read feature states.
public protocol FeatureFlagReadable: Sendable {
    /// Returns the effective state for the given feature.
    ///
    /// Resolution walks all configured sources in priority order and falls back
    /// to `feature.defaultValue` when no source contains a value.
    func isEnabled<FeatureType: Feature>(_ feature: FeatureType) -> Bool
}

/// Central facade used by application code to resolve feature states.
///
/// This type keeps a thread-safe snapshot of configured sources and performs
/// synchronous, in-memory reads suitable for UI code.
public final class FeatureFlags: FeatureFlagReadable, @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [any FeatureFlagSource]

    /// Creates the resolver with an optional list of sources.
    ///
    /// Sources are sorted once during initialization so reads can remain fast.
    public init(sources: [any FeatureFlagSource] = []) {
        self.sources = Self.sortedSources(sources)
    }

    /// Resolves the effective state for a feature.
    ///
    /// - Parameter feature: The feature to resolve.
    /// - Returns: The first matching source value, or `feature.defaultValue`
    ///   when no source knows the feature key.
    public func isEnabled<FeatureType: Feature>(_ feature: FeatureType) -> Bool {
        let snapshot = snapshotSources()

        for source in snapshot {
            if let value = source.value(forKey: feature.key) {
                return value
            }
        }

        return feature.defaultValue
    }

    /// Replaces the currently configured sources.
    ///
    /// The new sources are sorted by priority before becoming visible to readers.
    public func replaceSources(with sources: [any FeatureFlagSource]) {
        lock.lock()
        self.sources = Self.sortedSources(sources)
        lock.unlock()
    }

    private func snapshotSources() -> [any FeatureFlagSource] {
        lock.lock()
        let snapshot = sources
        lock.unlock()
        return snapshot
    }

    private static func sortedSources(
        _ sources: [any FeatureFlagSource]
    ) -> [any FeatureFlagSource] {
        sources
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.priority == rhs.element.priority {
                    return lhs.offset < rhs.offset
                }
                
                return lhs.element.priority > rhs.element.priority
            }
            .map(\.element)
    }

    private static func areSourcesOrdered(_ lhs: any FeatureFlagSource, _ rhs: any FeatureFlagSource) -> Bool {
        lhs.priority > rhs.priority
    }
}

/// A simple thread-safe in-memory source backed by a dictionary.
///
/// This source is useful for business defaults, tests, simulator configuration,
/// and any other static local setup.
public final class DictionaryFeatureFlagSource: FeatureFlagSource, @unchecked Sendable {
    /// The precedence of this source during conflict resolution.
    public let priority: FeatureFlagPriority

    private let lock = NSLock()
    private var values: [String: Bool]

    /// Creates an in-memory source from raw key/value pairs.
    ///
    /// - Parameters:
    ///   - values: A dictionary keyed by feature identifiers.
    ///   - priority: The source precedence.
    public init(values: [String: Bool] = [:], priority: FeatureFlagPriority) {
        self.values = values
        self.priority = priority
    }

    /// Creates an in-memory source from typed feature states.
    ///
    /// Duplicate keys are resolved with a `last wins` policy so the builder DSL
    /// remains safe even when the same feature appears multiple times.
    public convenience init<FeatureType: Feature>(
        states: [FeatureState<FeatureType>],
        priority: FeatureFlagPriority
    ) {
        let values = states.reduce(into: [String: Bool]()) { result, state in
            result[state.feature.key] = state.isEnabled
        }

        self.init(
            values: values,
            priority: priority
        )
    }

    /// Returns the value for the provided feature key.
    public func value(forKey key: String) -> Bool? {
        lock.lock()
        let value = values[key]
        lock.unlock()
        return value
    }

    /// Stores or replaces a value for the provided raw key.
    public func setValue(_ value: Bool, forKey key: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    /// Stores or replaces a value for the provided typed feature.
    public func setValue<FeatureType: Feature>(_ value: Bool, for feature: FeatureType) {
        setValue(value, forKey: feature.key)
    }
}

/// A thread-safe source that persists local overrides in `UserDefaults`.
///
/// This source is intended for development and QA workflows where overrides
/// should survive application relaunches.
public final class PersistentOverrideFeatureFlagSource: FeatureFlagSource, @unchecked Sendable {
    /// The precedence of this source during conflict resolution.
    public let priority: FeatureFlagPriority

    /// The `UserDefaults` key used to store the override dictionary.
    public let storageKey: String

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var values: [String: Bool]

    /// Creates a persistent override source.
    ///
    /// - Parameters:
    ///   - defaults: The `UserDefaults` instance used for persistence.
    ///   - storageKey: The key used to read and write the override dictionary.
    ///   - priority: The source precedence.
    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "feature_flags.local_overrides",
        priority: FeatureFlagPriority = .localOverrides
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.priority = priority
        self.values = defaults.dictionary(forKey: storageKey) as? [String: Bool] ?? [:]
    }

    /// Returns the locally overridden value for the provided key, if any.
    public func value(forKey key: String) -> Bool? {
        lock.lock()
        let value = values[key]
        lock.unlock()
        return value
    }

    /// Stores or replaces an override for a typed feature.
    public func setOverride<FeatureType: Feature>(_ isEnabled: Bool, for feature: FeatureType) {
        setOverride(isEnabled, forKey: feature.key)
    }

    /// Stores or replaces an override for a raw key and immediately persists it.
    public func setOverride(_ isEnabled: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        values[key] = isEnabled
        defaults.set(values, forKey: storageKey)
    }

    /// Removes an override for a typed feature and immediately persists the change.
    public func removeOverride<FeatureType: Feature>(for feature: FeatureType) {
        removeOverride(forKey: feature.key)
    }

    /// Removes an override for a raw key and immediately persists the change.
    public func removeOverride(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }

        values.removeValue(forKey: key)
        defaults.set(values, forKey: storageKey)
    }
}

/// Result builder used to declare feature configurations in a compact DSL.
@resultBuilder
public enum FeatureFlagBuilder<FeatureType: Feature> {
    public static func buildBlock(
        _ components: [FeatureState<FeatureType>]...
    ) -> [FeatureState<FeatureType>] {
        components.flatMap { $0 }
    }

    public static func buildExpression(
        _ expression: FeatureState<FeatureType>
    ) -> [FeatureState<FeatureType>] {
        [expression]
    }

    public static func buildExpression(
        _ expression: [FeatureState<FeatureType>]
    ) -> [FeatureState<FeatureType>] {
        expression
    }

    public static func buildOptional(
        _ component: [FeatureState<FeatureType>]?
    ) -> [FeatureState<FeatureType>] {
        component ?? []
    }

    public static func buildEither(
        first component: [FeatureState<FeatureType>]
    ) -> [FeatureState<FeatureType>] {
        component
    }

    public static func buildEither(
        second component: [FeatureState<FeatureType>]
    ) -> [FeatureState<FeatureType>] {
        component
    }

    public static func buildArray(
        _ components: [[FeatureState<FeatureType>]]
    ) -> [FeatureState<FeatureType>] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(
        _ component: [FeatureState<FeatureType>]
    ) -> [FeatureState<FeatureType>] {
        component
    }
}

/// A declarative collection of feature states.
///
/// Configurations can be turned into in-memory sources with an explicit priority
/// and are intended to describe business, test, simulator, or forced setups.
public struct FlagConfiguration<FeatureType: Feature>: Sendable {
    /// The typed feature states contained in the configuration.
    public let states: [FeatureState<FeatureType>]

    /// Creates a configuration from a prebuilt list of states.
    public init(states: [FeatureState<FeatureType>]) {
        self.states = states
    }

    /// Creates a configuration using the feature flag result builder DSL.
    public init(@FeatureFlagBuilder<FeatureType> _ builder: () -> [FeatureState<FeatureType>]) {
        self.states = builder()
    }

    /// An empty configuration that contributes no feature states.
    public static var empty: Self {
        Self(states: [])
    }

    /// Converts the configuration into an in-memory source with the provided priority.
    public func makeSource(priority: FeatureFlagPriority) -> DictionaryFeatureFlagSource {
        DictionaryFeatureFlagSource(states: states, priority: priority)
    }
}

/// Creates an enabled state for the provided feature.
public func enable<FeatureType: Feature>(_ feature: FeatureType) -> FeatureState<FeatureType> {
    FeatureState(feature: feature, isEnabled: true)
}

/// Creates a disabled state for the provided feature.
public func disable<FeatureType: Feature>(_ feature: FeatureType) -> FeatureState<FeatureType> {
    FeatureState(feature: feature, isEnabled: false)
}

/// Describes the application environment used to build the final source list.
public enum FeatureFlagsEnvironment: Sendable, Equatable {
    /// Production configuration with no debug-only sources attached.
    case production

    /// Non-production configuration that may include test, simulator, and local override sources.
    case nonProduction
}

/// Composes environment-specific configurations into a ready-to-use `FeatureFlags` instance.
///
/// This type centralizes the rules for which sources are active in production
/// and non-production environments.
public struct FeatureFlagsConfigurator<FeatureType: Feature>: Sendable {
    /// The environment that controls which sources are attached.
    public let environment: FeatureFlagsEnvironment

    /// Indicates whether simulator-only configuration should be included.
    public let isSimulator: Bool

    /// Optional locally persisted overrides.
    public let localOverridesSource: PersistentOverrideFeatureFlagSource?

    /// Base business configuration shared by all environments.
    public let businessConfiguration: FlagConfiguration<FeatureType>

    /// Additional test configuration available in non-production environments.
    public let testingConfiguration: FlagConfiguration<FeatureType>

    /// Additional simulator-only configuration available in non-production environments.
    public let simulatorConfiguration: FlagConfiguration<FeatureType>

    /// Non-overridable configuration that always wins when active.
    public let forcedConfiguration: FlagConfiguration<FeatureType>

    /// Creates a configurator with environment-specific inputs.
    public init(
        environment: FeatureFlagsEnvironment,
        isSimulator: Bool = isRunningInSimulator(),
        localOverridesSource: PersistentOverrideFeatureFlagSource? = nil,
        businessConfiguration: FlagConfiguration<FeatureType> = .empty,
        testingConfiguration: FlagConfiguration<FeatureType> = .empty,
        simulatorConfiguration: FlagConfiguration<FeatureType> = .empty,
        forcedConfiguration: FlagConfiguration<FeatureType> = .empty
    ) {
        self.environment = environment
        self.isSimulator = isSimulator
        self.localOverridesSource = localOverridesSource
        self.businessConfiguration = businessConfiguration
        self.testingConfiguration = testingConfiguration
        self.simulatorConfiguration = simulatorConfiguration
        self.forcedConfiguration = forcedConfiguration
    }

    /// Builds the final resolver from the currently configured sources.
    public func makeFeatureFlags() -> FeatureFlags {
        FeatureFlags(sources: makeSources())
    }

    /// Builds the ordered source list for the current environment.
    ///
    /// Production includes only the business configuration.
    /// Non-production additionally includes testing, simulator, local override,
    /// and forced configurations in deterministic priority order.
    public func makeSources() -> [any FeatureFlagSource] {
        var sources: [any FeatureFlagSource] = [
            businessConfiguration.makeSource(priority: .business)
        ]

        guard environment == .nonProduction else {
            return sources
        }

        sources.append(testingConfiguration.makeSource(priority: .testing))

        if isSimulator {
            sources.append(simulatorConfiguration.makeSource(priority: .simulator))
        }

        if let localOverridesSource {
            sources.append(localOverridesSource)
        }

        sources.append(forcedConfiguration.makeSource(priority: .forced))

        return sources
    }
}
