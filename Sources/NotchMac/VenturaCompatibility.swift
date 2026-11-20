import SwiftUI

extension View {
    @ViewBuilder func notchOnChange<Value: Equatable>(of value: Value, initial: Bool = false,
        _ action: @escaping (Value, Value) -> Void) -> some View {
        if #available(macOS 14.0, *) { onChange(of: value, initial: initial, action) }
        else { modifier(NotchChangeObserver(value: value, initial: initial, action: action)) }
    }
    @ViewBuilder func notchOnGeometryChange(for type: CGRect.Type, of transform: @escaping (GeometryProxy) -> CGRect,
                               action: @escaping (CGRect) -> Void) -> some View {
        if #available(macOS 14.0, *) { onGeometryChange(for: type, of: transform, action: action) }
        else {
            background(GeometryReader { proxy in Color.clear.preference(key: NotchFramePreference.self, value: transform(proxy)) })
                .onPreferenceChange(NotchFramePreference.self, perform: action)
        }
    }
}
private struct NotchChangeObserver<Value: Equatable>: ViewModifier {
    var value: Value
    var initial: Bool
    var action: (Value, Value) -> Void
    @State private var previous: Value
    init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
        self.value = value; self.initial = initial; self.action = action; _previous = State(initialValue: value)
    }
    func body(content: Content) -> some View {
        content.onChange(of: value) { next in let old = previous; previous = next; action(old, next) }
            .onAppear { previous = value; if initial { action(value, value) } }
    }
}
private struct NotchFramePreference: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
