// Imitação do SwiftUI, só para conferir os tipos do código do app fora de um Mac.
// Não desenha nada: só tem os nomes e as assinaturas que o app usa.
@_exported import Foundation
@_exported import UIKit
import UniformTypeIdentifiers

// MARK: - View

@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency var body: Body { get }
}

extension Never: View {
    public var body: Never { fatalError() }
}

public protocol _PrimitiveView: View where Body == Never {}
extension _PrimitiveView {
    public var body: Never { fatalError() }
}

public struct EmptyView: _PrimitiveView {
    public init() {}
}

public struct TupleView<T>: _PrimitiveView {
    public init(_ value: T) {}
}

public struct _ConditionalContent<TrueContent: View, FalseContent: View>: _PrimitiveView {}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
    public var body: Never { fatalError() }
}

public struct AnyView: _PrimitiveView {
    public init<V: View>(_ view: V) {}
}

public struct _Modified<Content>: _PrimitiveView {
    init() {}
}

@resultBuilder
public enum ViewBuilder {
    public static func buildExpression<Content: View>(_ content: Content) -> Content { content }
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<Content: View>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: View>(_ content: repeat each Content) -> TupleView<(repeat each Content)> {
        TupleView((repeat each content))
    }
    public static func buildIf<Content: View>(_ content: Content?) -> Content? { content }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildLimitedAvailability<Content: View>(_ content: Content) -> AnyView { AnyView(content) }
}

// MARK: - App e cenas

@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Body { get }
    @MainActor @preconcurrency init()
}

extension App {
    @MainActor public static func main() {}
}

@MainActor @preconcurrency
public protocol Scene {}

@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
}

public struct WindowGroup<Content: View>: Scene {
    public init(@ViewBuilder content: () -> Content) {}
}

public enum ScenePhase: Comparable, Sendable {
    case background, inactive, active
}

// MARK: - Estado

@propertyWrapper
public struct State<Value> {
    public init(wrappedValue: Value) { stored = wrappedValue }
    public init(initialValue: Value) { stored = initialValue }
    private var stored: Value
    public var wrappedValue: Value {
        get { stored }
        nonmutating set {}
    }
    public var projectedValue: Binding<Value> { Binding(get: { self.stored }, set: { _ in }) }
}

@propertyWrapper @dynamicMemberLookup
public struct Binding<Value> {
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }
    private let getter: () -> Value
    private let setter: (Value) -> Void
    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public var projectedValue: Binding<Value> { self }
    public static func constant(_ value: Value) -> Binding<Value> { Binding(get: { value }, set: { _ in }) }
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(get: { self.wrappedValue[keyPath: keyPath] }, set: { _ in })
    }
}

public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public init(wrappedValue: Value) { stored = wrappedValue }
    public init(initialValue: Value) { stored = initialValue }
    private var stored: Value
    public var wrappedValue: Value {
        get { stored }
        set { stored = newValue }
    }
}

@propertyWrapper @MainActor @preconcurrency
public struct ObservedObject<ObjectType: ObservableObject> {
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public var wrappedValue: ObjectType
    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            Binding(get: { self.object[keyPath: keyPath] }, set: { self.object[keyPath: keyPath] = $0 })
        }
    }
    public var projectedValue: Wrapper { Wrapper(object: wrappedValue) }
}

@propertyWrapper @MainActor @preconcurrency
public struct StateObject<ObjectType: ObservableObject> {
    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { make = thunk }
    private let make: () -> ObjectType
    public var wrappedValue: ObjectType { make() }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject(wrappedValue: wrappedValue).projectedValue }
}

@propertyWrapper
public struct FocusState<Value: Hashable> {
    public init() where Value == Bool { stored = false }
    public init<T: Hashable>() where Value == T? { stored = nil }
    private var stored: Value
    public var wrappedValue: Value {
        get { stored }
        nonmutating set {}
    }
    public struct Binding {
        public var wrappedValue: Value
    }
    public var projectedValue: Binding { Binding(wrappedValue: stored) }
}

public struct EnvironmentValues {
    public var scenePhase: ScenePhase { .active }
    public var colorScheme: ColorScheme { .dark }
    public var horizontalSizeClass: UserInterfaceSizeClass? { nil }
    public var verticalSizeClass: UserInterfaceSizeClass? { nil }
    public var displayScale: CGFloat { 2 }
    public var accessibilityReduceMotion: Bool { false }
}

public enum UserInterfaceSizeClass: Sendable { case compact, regular }

@propertyWrapper
public struct Environment<Value> {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
    private let keyPath: KeyPath<EnvironmentValues, Value>
    public var wrappedValue: Value { EnvironmentValues()[keyPath: keyPath] }
}

// MARK: - Medidas

public struct Edge {
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
    }
}

public enum EdgeKind: Sendable { case top, leading, bottom, trailing }

public struct EdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public struct HorizontalAlignment: Equatable, Sendable {
    let id: Int
    public static let leading = HorizontalAlignment(id: 0)
    public static let center = HorizontalAlignment(id: 1)
    public static let trailing = HorizontalAlignment(id: 2)
}

public struct VerticalAlignment: Equatable, Sendable {
    let id: Int
    public static let top = VerticalAlignment(id: 0)
    public static let center = VerticalAlignment(id: 1)
    public static let bottom = VerticalAlignment(id: 2)
    public static let firstTextBaseline = VerticalAlignment(id: 3)
    public static let lastTextBaseline = VerticalAlignment(id: 4)
}

public struct Alignment: Equatable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

public enum TextAlignment: Sendable { case leading, center, trailing }

public struct UnitPoint: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

public enum ColorScheme: Sendable { case light, dark }

public enum Axis: Sendable {
    case horizontal, vertical
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let container = SafeAreaRegions(rawValue: 1)
    public static let keyboard = SafeAreaRegions(rawValue: 2)
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

public enum Visibility: Sendable { case automatic, visible, hidden }

// MARK: - Cores, estilos e formas

public protocol ShapeStyle {}

public struct Color: ShapeStyle, _PrimitiveView, Hashable, Sendable {
    public enum RGBColorSpace: Sendable { case sRGB, sRGBLinear, displayP3 }
    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) {}
    public init(_ name: String, bundle: Bundle? = nil) {}
    public init(_ uiColor: UIColor) {}
    public func opacity(_ opacity: Double) -> Color { self }
    public static let white = Color(white: 1)
    public static let black = Color(white: 0)
    public static let clear = Color(white: 0, opacity: 0)
    public static let red = Color(white: 0)
    public static let gray = Color(white: 0.5)
    public static let primary = Color(white: 0)
    public static let secondary = Color(white: 0)
    public static let accentColor = Color(white: 0)
}

extension ShapeStyle where Self == Color {
    public static var white: Color { Color.white }
    public static var black: Color { Color.black }
    public static var clear: Color { Color.clear }
}

public struct Gradient: Equatable, Sendable {
    public struct Stop: Equatable, Sendable {
        public var color: Color
        public var location: CGFloat
        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }
    public init(colors: [Color]) {}
    public init(stops: [Stop]) {}
}

public struct LinearGradient: ShapeStyle, _PrimitiveView, Sendable {
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {}
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {}
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {}
}

public struct FillStyle: Equatable, Sendable {
    public init(eoFill: Bool = false, antialiased: Bool = true) {}
}

public struct StrokeStyle: Equatable, Sendable {
    public init(lineWidth: CGFloat = 1) {}
}

public struct Path: Sendable {
    public init() {}
}

@MainActor @preconcurrency
public protocol Shape: View, Sendable {
    nonisolated func path(in rect: CGRect) -> Path
}

extension Shape {
    public nonisolated func path(in rect: CGRect) -> Path { Path() }
    public var body: Never { fatalError() }
    public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> some View { _Modified<Self>() }
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View { _Modified<Self>() }
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle) -> some View { _Modified<Self>() }
}

@MainActor @preconcurrency
public protocol InsettableShape: Shape {}

extension InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View { _Modified<Self>() }
    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View { _Modified<Self>() }
}

public enum RoundedCornerStyle: Sendable { case circular, continuous }

public struct RoundedRectangle: InsettableShape {
    public typealias Body = Never
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {}
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .circular) {}
}

public struct Rectangle: InsettableShape {
    public typealias Body = Never
    public init() {}
}

public struct Circle: InsettableShape {
    public typealias Body = Never
    public init() {}
}

public struct Capsule: InsettableShape {
    public typealias Body = Never
    public init(style: RoundedCornerStyle = .circular) {}
}

// MARK: - Letra e texto

public struct Font: Hashable, Sendable {
    public struct Weight: Hashable, Sendable {
        let value: Int
        public static let ultraLight = Weight(value: 1)
        public static let thin = Weight(value: 2)
        public static let light = Weight(value: 3)
        public static let regular = Weight(value: 4)
        public static let medium = Weight(value: 5)
        public static let semibold = Weight(value: 6)
        public static let bold = Weight(value: 7)
        public static let heavy = Weight(value: 8)
        public static let black = Weight(value: 9)
    }
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public static func system(size: CGFloat, weight: Weight? = nil, design: Design? = nil) -> Font { Font() }
    public static let body = Font()
    public static let caption = Font()
    public static let headline = Font()
    public func monospacedDigit() -> Font { self }
    public func weight(_ weight: Weight) -> Font { self }
}

public struct Text: _PrimitiveView, Equatable, Sendable {
    public init<S: StringProtocol>(_ content: S) {}
    public init(verbatim content: String) {}
    public func font(_ font: Font?) -> Text { self }
    public func fontWeight(_ weight: Font.Weight?) -> Text { self }
    public func foregroundColor(_ color: Color?) -> Text { self }
    public func tracking(_ tracking: CGFloat) -> Text { self }
    public func kerning(_ kerning: CGFloat) -> Text { self }
    public func bold() -> Text { self }
    public func monospacedDigit() -> Text { self }
    public static func + (lhs: Text, rhs: Text) -> Text { lhs }
}

public struct Image: _PrimitiveView, Equatable, Sendable {
    public enum TemplateRenderingMode: Sendable { case template, original }
    public enum ResizingMode: Sendable { case tile, stretch }
    public init(_ name: String, bundle: Bundle? = nil) {}
    public init(systemName: String) {}
    public init(uiImage: UIImage) {}
    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image { self }
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image { self }
}

public struct Label<Title: View, Icon: View>: _PrimitiveView {
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {}
}

extension Label where Title == Text, Icon == Image {
    public init<S: StringProtocol>(_ title: S, systemImage name: String) {}
    public init<S: StringProtocol>(_ title: S, image name: String) {}
}

// MARK: - Pilhas e recipientes

public struct VStack<Content: View>: _PrimitiveView {
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct HStack<Content: View>: _PrimitiveView {
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct ZStack<Content: View>: _PrimitiveView {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
}

public struct LazyHStack<Content: View>: _PrimitiveView {
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct LazyVStack<Content: View>: _PrimitiveView {
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct Group<Content: View>: _PrimitiveView {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct Spacer: _PrimitiveView {
    public init(minLength: CGFloat? = nil) {}
}

public struct Divider: _PrimitiveView {
    public init() {}
}

public struct ScrollView<Content: View>: _PrimitiveView {
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {}
}

public struct GeometryProxy {
    public var size: CGSize { .zero }
    public var safeAreaInsets: EdgeInsets { EdgeInsets() }
    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect { .zero }
}

public enum CoordinateSpace: Sendable {
    case global, local
    case named(String)
}

public struct GeometryReader<Content: View>: _PrimitiveView {
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {}
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: _PrimitiveView {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {}
}

public struct TimelineView<Schedule: TimelineSchedule, Content> {
    public struct Context {
        public let date: Date
    }
}

extension TimelineView: View, _PrimitiveView where Content: View {
    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {}
}

public typealias TimelineViewDefaultContext = TimelineView<EveryMinuteTimelineSchedule, Never>.Context

public protocol TimelineSchedule {}
public struct EveryMinuteTimelineSchedule: TimelineSchedule {}
public struct PeriodicTimelineSchedule: TimelineSchedule {}
extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    public static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule { PeriodicTimelineSchedule() }
}

// MARK: - Controles

public struct ButtonStyleConfiguration {
    public struct Label: _PrimitiveView {}
    public let label: Label
    public let isPressed: Bool
}

@MainActor @preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration
    @ViewBuilder @MainActor @preconcurrency func makeBody(configuration: Configuration) -> Body
}

public struct PlainButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.label }
}

extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

public struct ButtonRole: Equatable, Sendable {
    public static let destructive = ButtonRole()
    public static let cancel = ButtonRole()
}

public struct Button<Label: View>: _PrimitiveView {
    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {}
    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {}
}

extension Button where Label == Text {
    public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {}
}

public struct TextField<Label: View>: _PrimitiveView {}

extension TextField where Label == Text {
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {}
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {}
}

public struct Menu<Label: View, Content: View>: _PrimitiveView {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
}

extension Menu where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
}

public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: _PrimitiveView {
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
}

extension Picker where Label == Text {
    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {}
}

public struct Section<Parent: View, Content: View, Footer: View>: _PrimitiveView {}

extension Section where Parent == Text, Footer == EmptyView {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
}

extension Section where Parent == EmptyView, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct ProgressView<Label: View, CurrentValueLabel: View>: _PrimitiveView {}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() {}
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {}
}

public protocol ProgressViewStyle {}
public struct CircularProgressViewStyle: ProgressViewStyle {
    public init() {}
}
public struct LinearProgressViewStyle: ProgressViewStyle {
    public init() {}
}
extension ProgressViewStyle where Self == CircularProgressViewStyle {
    public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() }
}
extension ProgressViewStyle where Self == LinearProgressViewStyle {
    public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() }
}

public enum ControlSize: Sendable { case mini, small, regular, large }

public struct TextInputAutocapitalization: Sendable {
    public static var never: TextInputAutocapitalization { TextInputAutocapitalization() }
    public static var words: TextInputAutocapitalization { TextInputAutocapitalization() }
    public static var sentences: TextInputAutocapitalization { TextInputAutocapitalization() }
    public static var characters: TextInputAutocapitalization { TextInputAutocapitalization() }
}

public struct SubmitLabel: Sendable {
    public static var done: SubmitLabel { SubmitLabel() }
    public static var go: SubmitLabel { SubmitLabel() }
    public static var send: SubmitLabel { SubmitLabel() }
    public static var search: SubmitLabel { SubmitLabel() }
    public static var next: SubmitLabel { SubmitLabel() }
    public static var `continue`: SubmitLabel { SubmitLabel() }
    public static var `return`: SubmitLabel { SubmitLabel() }
}

public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1)
    public static let search = SubmitTriggers(rawValue: 2)
}

// MARK: - Gestos

@MainActor @preconcurrency
public protocol Gesture<Value> {
    associatedtype Value
}

extension Gesture {
    public func onEnded(_ action: @escaping (Value) -> Void) -> _EndedGesture<Self> { _EndedGesture() }
    public func onChanged(_ action: @escaping (Value) -> Void) -> _ChangedGesture<Self> where Value: Equatable { _ChangedGesture() }
}

public struct _EndedGesture<Child: Gesture>: Gesture {
    public typealias Value = Child.Value
}

public struct _ChangedGesture<Child: Gesture>: Gesture {
    public typealias Value = Child.Value
}

public struct DragGesture: Gesture {
    public struct Value: Equatable, Sendable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize
        public var predictedEndLocation: CGPoint
        public var predictedEndTranslation: CGSize
    }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {}
}

public struct TapGesture: Gesture {
    public typealias Value = Void
    public init(count: Int = 1) {}
}

public struct GestureMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let all = GestureMask(rawValue: 3)
}

// MARK: - Animação e transição

public struct Animation: Equatable, Sendable {
    public static let `default` = Animation()
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func easeIn(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
    public static var easeInOut: Animation { Animation() }
    public static var easeOut: Animation { Animation() }
    public static var linear: Animation { Animation() }
}

public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result { try body() }

public struct AnyTransition {
    public static let opacity = AnyTransition()
    public static let identity = AnyTransition()
    public static let slide = AnyTransition()
    public static func move(edge: EdgeKind) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
}

// MARK: - Acessibilidade

public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let isButton = AccessibilityTraits(rawValue: 1)
    public static let isHeader = AccessibilityTraits(rawValue: 2)
    public static let isSelected = AccessibilityTraits(rawValue: 4)
    public static let isModal = AccessibilityTraits(rawValue: 8)
    public static let isImage = AccessibilityTraits(rawValue: 16)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 32)
}

public enum AccessibilityChildBehavior: Sendable { case ignore, contain, combine }

public enum AccessibilityAdjustmentDirection: Sendable { case increment, decrement }

// MARK: - Ligação com o UIKit

@MainActor @preconcurrency
public protocol UIViewRepresentable: View where Body == Never {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    typealias Context = UIViewRepresentableContext<Self>
    @MainActor @preconcurrency func makeUIView(context: Context) -> UIViewType
    @MainActor @preconcurrency func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor @preconcurrency static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
    @MainActor @preconcurrency func makeCoordinator() -> Coordinator
}

extension UIViewRepresentable {
    public var body: Never { fatalError() }
    public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}
}

extension UIViewRepresentable where Coordinator == Void {
    public func makeCoordinator() {}
}

@MainActor @preconcurrency
public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
    public let coordinator: Representable.Coordinator
}

@propertyWrapper @MainActor @preconcurrency
public struct UIApplicationDelegateAdaptor<DelegateType: NSObject & UIApplicationDelegate> {
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {}
    public var wrappedValue: DelegateType { fatalError() }
}

// MARK: - Modificadores

extension View {
    // Espaço e tamanho
    public func padding(_ insets: EdgeInsets) -> some View { _Modified<Self>() }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { _Modified<Self>() }
    public func padding(_ length: CGFloat) -> some View { _Modified<Self>() }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { _Modified<Self>() }
    public func frame(
        minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View { _Modified<Self>() }
    public func fixedSize() -> some View { _Modified<Self>() }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View { _Modified<Self>() }
    public func layoutPriority(_ value: Double) -> some View { _Modified<Self>() }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { _Modified<Self>() }
    public func offset(_ offset: CGSize) -> some View { _Modified<Self>() }
    public func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View { _Modified<Self>() }
    public func scaledToFit() -> some View { _Modified<Self>() }
    public func scaledToFill() -> some View { _Modified<Self>() }
    public func zIndex(_ value: Double) -> some View { _Modified<Self>() }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View { _Modified<Self>() }

    // Aparência
    public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View { _Modified<Self>() }
    public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { _Modified<Self>() }
    public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View { _Modified<Self>() }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { _Modified<Self>() }
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View { _Modified<Self>() }
    public func clipped(antialiased: Bool = false) -> some View { _Modified<Self>() }
    public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View { _Modified<Self>() }
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View { _Modified<Self>() }
    public func opacity(_ opacity: Double) -> some View { _Modified<Self>() }
    public func shadow(color: Color = Color(white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { _Modified<Self>() }
    public func foregroundColor(_ color: Color?) -> some View { _Modified<Self>() }
    public func tint(_ tint: Color?) -> some View { _Modified<Self>() }
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View { _Modified<Self>() }
    public func scaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some View { _Modified<Self>() }
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View { _Modified<Self>() }
    public func hidden() -> some View { _Modified<Self>() }
    public func mask<Mask: View>(_ mask: Mask) -> some View { _Modified<Self>() }
    public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View { _Modified<Self>() }
    public func blendMode(_ blendMode: BlendMode) -> some View { _Modified<Self>() }
    public func compositingGroup() -> some View { _Modified<Self>() }
    public func statusBarHidden(_ hidden: Bool = true) -> some View { _Modified<Self>() }
    public func persistentSystemOverlays(_ visibility: Visibility) -> some View { _Modified<Self>() }
    public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View { _Modified<Self>() }
    public func controlSize(_ controlSize: ControlSize) -> some View { _Modified<Self>() }

    // Texto
    public func font(_ font: Font?) -> some View { _Modified<Self>() }
    public func lineLimit(_ number: Int?) -> some View { _Modified<Self>() }
    public func lineSpacing(_ lineSpacing: CGFloat) -> some View { _Modified<Self>() }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { _Modified<Self>() }
    public func minimumScaleFactor(_ factor: CGFloat) -> some View { _Modified<Self>() }
    public func truncationMode(_ mode: Text.TruncationMode) -> some View { _Modified<Self>() }
    public func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View { _Modified<Self>() }
    public func disableAutocorrection(_ disable: Bool?) -> some View { _Modified<Self>() }
    public func autocorrectionDisabled(_ disable: Bool = true) -> some View { _Modified<Self>() }
    public func keyboardType(_ type: UIKeyboardType) -> some View { _Modified<Self>() }
    public func textContentType(_ textContentType: UITextContentType?) -> some View { _Modified<Self>() }
    public func submitLabel(_ submitLabel: SubmitLabel) -> some View { _Modified<Self>() }
    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping (() -> Void)) -> some View { _Modified<Self>() }
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View { _Modified<Self>() }

    // Toques e estado
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View { _Modified<Self>() }
    public func disabled(_ disabled: Bool) -> some View { _Modified<Self>() }
    public func allowsHitTesting(_ enabled: Bool) -> some View { _Modified<Self>() }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { _Modified<Self>() }
    public func gesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { _Modified<Self>() }
    public func simultaneousGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { _Modified<Self>() }
    public func highPriorityGesture<T: Gesture>(_ gesture: T, including mask: GestureMask = .all) -> some View { _Modified<Self>() }
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View { _Modified<Self>() }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { _Modified<Self>() }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { _Modified<Self>() }
    public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View { _Modified<Self>() }
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> some View { _Modified<Self>() }
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View { _Modified<Self>() }
    public func transition(_ t: AnyTransition) -> some View { _Modified<Self>() }
    public func id<ID: Hashable>(_ id: ID) -> some View { _Modified<Self>() }
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void
    ) -> some View { _Modified<Self>() }
    public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void
    ) -> some View { _Modified<Self>() }

    // Acessibilidade
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { _Modified<Self>() }
    public func accessibilityValue<S: StringProtocol>(_ value: S) -> some View { _Modified<Self>() }
    public func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View { _Modified<Self>() }
    public func accessibilityHidden(_ hidden: Bool) -> some View { _Modified<Self>() }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View { _Modified<Self>() }
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View { _Modified<Self>() }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { _Modified<Self>() }
    public func accessibilityAdjustableAction(_ handler: @escaping (AccessibilityAdjustmentDirection) -> Void) -> some View { _Modified<Self>() }
    public func accessibilityAction(_ handler: @escaping () -> Void) -> some View { _Modified<Self>() }
}

public enum ContentMode: Sendable { case fit, fill }

public enum BlendMode: Sendable {
    case normal, multiply, screen, overlay, darken, lighten, sourceAtop, destinationOver, destinationOut, plusDarker, plusLighter
}

public struct Angle: Equatable, Sendable {
    public static func degrees(_ degrees: Double) -> Angle { Angle() }
    public static func radians(_ radians: Double) -> Angle { Angle() }
}

extension Text {
    public enum TruncationMode: Sendable { case head, tail, middle }
}
