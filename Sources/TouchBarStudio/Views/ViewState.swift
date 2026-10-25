import SwiftUI

/// Wrapper around SwiftUI's `State` storage.
///
/// In the macOS 27 SDK `@State` is an attached macro whose plugin ships only with
/// Xcode, so `@State` fails to compile with the Command Line Tools alone. The
/// underlying `State<Value>` struct is still public; nesting it inside a
/// `DynamicProperty` gives identical behaviour and builds with either toolchain.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
