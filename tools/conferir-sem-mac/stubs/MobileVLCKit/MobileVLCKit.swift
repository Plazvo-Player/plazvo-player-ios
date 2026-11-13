// Imitação do MobileVLCKit 3.7.5 (como o Swift enxerga os cabeçalhos dele), só para conferir os
// tipos do código do app fora de um Mac.
import Foundation

public enum VLCMediaPlayerState: Int, Sendable {
    case stopped, opening, buffering, ended, error, playing, paused, esAdded
}

open class VLCTime: NSObject {
    public convenience init(int aInt: Int32) { self.init() }
    public convenience init(number aNumber: NSNumber?) { self.init() }
    open var value: NSNumber? { nil }
    open var intValue: Int32 { 0 }
    open var stringValue: String { "" }
}

open class VLCLibrary: NSObject {
    open class func shared() -> VLCLibrary { VLCLibrary() }
    public convenience init(options: [Any]) { self.init() }
    open func setHumanReadableName(_ readableName: String, withHTTPUserAgent userAgent: String) {}
    open var version: String { "" }
}

open class VLCMedia: NSObject {
    public convenience init(url anURL: URL) { self.init() }
    public convenience init(path aPath: String) { self.init() }
    open var url: URL? { nil }
    open var length: VLCTime { VLCTime() }
    open func addOption(_ option: String) {}
    open func addOptions(_ options: [AnyHashable: Any]) {}
}

public protocol VLCMediaPlayerDelegate: NSObjectProtocol {
    func mediaPlayerStateChanged(_ aNotification: Notification)
    func mediaPlayerTimeChanged(_ aNotification: Notification)
}

extension VLCMediaPlayerDelegate {
    public func mediaPlayerStateChanged(_ aNotification: Notification) {}
    public func mediaPlayerTimeChanged(_ aNotification: Notification) {}
}

open class VLCMediaPlayer: NSObject {
    public convenience init(options: [Any]) { self.init() }
    public convenience init(library: VLCLibrary) { self.init() }
    open var libraryInstance: VLCLibrary { VLCLibrary() }
    open weak var delegate: (any VLCMediaPlayerDelegate)?
    open var drawable: Any?
    open var media: VLCMedia?
    open var state: VLCMediaPlayerState { .stopped }
    open var time: VLCTime = VLCTime()
    open var position: Float = 0
    open var rate: Float = 1
    open var isPlaying: Bool { false }
    open var isSeekable: Bool { false }
    open var videoSize: CGSize { .zero }
    open var hasVideoOut: Bool { false }
    open var scaleFactor: Float = 0
    open var videoAspectRatio: UnsafeMutablePointer<CChar>?
    open var currentVideoSubTitleIndex: Int32 = -1
    open var videoSubTitlesNames: [Any] { [] }
    open var videoSubTitlesIndexes: [Any] { [] }
    open var currentAudioTrackIndex: Int32 = -1
    open var audioTrackNames: [Any] { [] }
    open var audioTrackIndexes: [Any] { [] }
    open func play() {}
    open func pause() {}
    open func stop() {}
    open func jumpBackward(_ interval: Int32) {}
    open func jumpForward(_ interval: Int32) {}
}

public let VLCMediaTracksInformationType = "type"
public let VLCMediaTracksInformationTypeVideo = "video"
public let VLCMediaTracksInformationTypeAudio = "audio"
public let VLCMediaTracksInformationTypeText = "text"
public let VLCMediaTracksInformationVideoWidth = "width"
public let VLCMediaTracksInformationVideoHeight = "height"
public let VLCMediaTracksInformationVideoOrientation = "orientation"
public let VLCMediaTracksInformationSourceAspectRatio = "sar_num"
public let VLCMediaTracksInformationSourceAspectRatioDenominator = "sar_den"

extension VLCMedia {
    public var tracksInformation: [Any] { [] }
}
