import Foundation

public extension TabContextCoordinator {
    /// The stock chain, highest-value detector first.
    ///
    /// Order is a hint, not the decision — `ContextSource` priority and
    /// `TabNamingEngine` settle conflicts.
    static func defaultProviders() -> [any TerminalContextProvider] {
        [
            LLMSessionContextProvider.claude(),
            LLMSessionContextProvider.codex(),
            LLMSessionContextProvider.gemini(),
            LLMSessionContextProvider.openCode(),
            GenericProcessContextProvider()
        ]
    }

    /// A coordinator wired with the stock providers.
    static func standard(engine: TabNamingEngine = TabNamingEngine()) -> TabContextCoordinator {
        TabContextCoordinator(providers: defaultProviders(), engine: engine)
    }
}
