// Imitação mínima do UIKit, só para conferir os tipos do código do app fora de um Mac.
@_exported import Foundation

@MainActor open class UIResponder: NSObject {
    public nonisolated static let keyboardDidShowNotification = Notification.Name("keyboardDidShow")
    public nonisolated static let keyboardDidHideNotification = Notification.Name("keyboardDidHide")
    public nonisolated static let keyboardWillShowNotification = Notification.Name("keyboardWillShow")
    public nonisolated static let keyboardWillHideNotification = Notification.Name("keyboardWillHide")
    public nonisolated override init() { super.init() }
}

public struct UIRectEdge: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let top = UIRectEdge(rawValue: 1)
    public static let left = UIRectEdge(rawValue: 2)
    public static let bottom = UIRectEdge(rawValue: 4)
    public static let right = UIRectEdge(rawValue: 8)
    public static let all: UIRectEdge = [.top, .left, .bottom, .right]
}

@MainActor open class UIColor: NSObject {
    public nonisolated static let black = UIColor()
    public nonisolated static let white = UIColor()
    public nonisolated static let clear = UIColor()
    public nonisolated override init() { super.init() }
    public nonisolated convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init() }
}

open class UIImage: NSObject, @unchecked Sendable {
    public convenience init?(named name: String) { self.init() }
}

open class UIFont: NSObject, @unchecked Sendable {
    public struct Weight: Hashable, Sendable {
        public let rawValue: CGFloat
        public static let regular = Weight(rawValue: 0)
        public static let medium = Weight(rawValue: 0.23)
        public static let semibold = Weight(rawValue: 0.3)
        public static let bold = Weight(rawValue: 0.4)
    }
    public class func systemFont(ofSize fontSize: CGFloat) -> UIFont { UIFont() }
    public class func systemFont(ofSize fontSize: CGFloat, weight: Weight) -> UIFont { UIFont() }
    public class func monospacedSystemFont(ofSize fontSize: CGFloat, weight: Weight) -> UIFont { UIFont() }
    public var lineHeight: CGFloat { 0 }
}

public struct UIViewAutoresizing: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let flexibleWidth = UIViewAutoresizing(rawValue: 2)
    public static let flexibleHeight = UIViewAutoresizing(rawValue: 16)
}

@MainActor open class UIView: UIResponder {
    public typealias AutoresizingMask = UIViewAutoresizing
    public nonisolated convenience init(frame: CGRect) { self.init() }
    public var frame: CGRect = .zero
    public var bounds: CGRect = .zero
    public var backgroundColor: UIColor?
    public var isUserInteractionEnabled = true
    public var autoresizingMask: AutoresizingMask = []
    public var clipsToBounds = false
    public var isOpaque = true
    public var subviews: [UIView] { [] }
    public var superview: UIView? { nil }
    public var window: UIWindow? { nil }
    public var translatesAutoresizingMaskIntoConstraints = true
    public var accessibilityElementsHidden = false
    public var isAccessibilityElement = false
    public func addSubview(_ view: UIView) {}
    public func removeFromSuperview() {}
    public func setNeedsLayout() {}
    public func layoutIfNeeded() {}
    open func layoutSubviews() {}
}

@MainActor open class UIViewController: UIResponder {
    public var view: UIView! { nil }
    public var presentedViewController: UIViewController? { nil }
    open var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    public func setNeedsUpdateOfSupportedInterfaceOrientations() {}
    public func setNeedsUpdateOfHomeIndicatorAutoHidden() {}
    public func setNeedsStatusBarAppearanceUpdate() {}
}

@MainActor open class UIScene: UIResponder {
    public enum ActivationState: Int, Sendable { case unattached = -1, foregroundActive, foregroundInactive, background }
    public var activationState: ActivationState { .foregroundActive }
}

public enum UIInterfaceOrientation: Int, Sendable {
    case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
}

public struct UIInterfaceOrientationMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let portrait = UIInterfaceOrientationMask(rawValue: 2)
    public static let portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 4)
    public static let landscapeLeft = UIInterfaceOrientationMask(rawValue: 16)
    public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 8)
    public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
    public static let all: UIInterfaceOrientationMask = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
    public static let allButUpsideDown: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
}

@MainActor open class UIWindow: UIView {
    public var rootViewController: UIViewController?
    public var isKeyWindow: Bool { false }
}

@MainActor open class UIWindowScene: UIScene {
    public var interfaceOrientation: UIInterfaceOrientation { .portrait }
    public var windows: [UIWindow] { [] }
    public var keyWindow: UIWindow? { nil }
    open class GeometryPreferences: NSObject {
        open class iOS: GeometryPreferences {
            public init(interfaceOrientations: UIInterfaceOrientationMask) {}
        }
    }
    public func requestGeometryUpdate(_ preferences: GeometryPreferences, errorHandler: ((any Error) -> Void)? = nil) {}
}

@MainActor public protocol UIApplicationDelegate: NSObjectProtocol {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
}

extension UIApplicationDelegate {
    public func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { .all }
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
}

@MainActor open class UIApplication: UIResponder {
    public enum State: Int, Sendable { case active, inactive, background }
    public struct LaunchOptionsKey: Hashable, Sendable {
        public let rawValue: String
    }
    public static let shared = UIApplication()
    public var connectedScenes: Set<UIScene> { [] }
    public var applicationState: State { .active }
    public var isIdleTimerDisabled = false
    public nonisolated static let didEnterBackgroundNotification = Notification.Name("didEnterBackground")
    public nonisolated static let willResignActiveNotification = Notification.Name("willResignActive")
    public nonisolated static let didBecomeActiveNotification = Notification.Name("didBecomeActive")
}

public enum UIUserInterfaceIdiom: Int, Sendable { case unspecified = -1, phone, pad, tv, carPlay, mac, vision }

@MainActor open class UIDevice: NSObject {
    public static let current = UIDevice()
    public var userInterfaceIdiom: UIUserInterfaceIdiom { .phone }
    public var systemVersion: String { "18.0" }
    public var systemName: String { "iOS" }
}

open class UIPasteboard: NSObject, @unchecked Sendable {
    public static let general = UIPasteboard()
    public var string: String?
    public var hasStrings: Bool { false }
}

public enum UIKeyboardType: Int, Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

public struct UITextContentType: Hashable, Sendable {
    public let rawValue: String
    public static let URL = UITextContentType(rawValue: "url")
}

public enum UIAccessibility {
    public struct Notification: Hashable, Sendable {
        public let rawValue: UInt32
        public static let announcement = Notification(rawValue: 1)
        public static let screenChanged = Notification(rawValue: 2)
        public static let layoutChanged = Notification(rawValue: 3)
    }
    public static func post(notification: Notification, argument: Any?) {}
    public static var isVoiceOverRunning: Bool { false }
}

// O que o Foundation só tem nos aparelhos da Apple: acesso a arquivo de fora do app e marcadores.
extension URL {
    public struct BookmarkCreationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let minimalBookmark = BookmarkCreationOptions(rawValue: 1 << 9)
        public static let suitableForBookmarkFile = BookmarkCreationOptions(rawValue: 1 << 10)
    }

    public struct BookmarkResolutionOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withoutUI = BookmarkResolutionOptions(rawValue: 1 << 8)
        public static let withoutMounting = BookmarkResolutionOptions(rawValue: 1 << 9)
    }

    public func startAccessingSecurityScopedResource() -> Bool { false }
    public func stopAccessingSecurityScopedResource() {}

    public func bookmarkData(
        options: BookmarkCreationOptions = [],
        includingResourceValuesForKeys keys: Set<URLResourceKey>? = nil,
        relativeTo url: URL? = nil
    ) throws -> Data { Data() }

    public init(
        resolvingBookmarkData data: Data,
        options: BookmarkResolutionOptions = [],
        relativeTo url: URL? = nil,
        bookmarkDataIsStale: inout Bool
    ) throws { self.init(fileURLWithPath: "/") }
}
