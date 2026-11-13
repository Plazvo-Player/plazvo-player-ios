// Imitação mínima de UniformTypeIdentifiers, só para conferir os tipos do código do app fora de um Mac.
import Foundation

public struct UTType: Hashable, Sendable {
    public let identifier: String
    public init?(_ identifier: String) { self.identifier = identifier }
    public init?(filenameExtension: String, conformingTo supertype: UTType = .data) { identifier = filenameExtension }
    public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) { self.identifier = identifier }
    init(known: String) { identifier = known }
    public static let data = UTType(known: "public.data")
    public static let item = UTType(known: "public.item")
    public static let content = UTType(known: "public.content")
    public static let movie = UTType(known: "public.movie")
    public static let video = UTType(known: "public.video")
    public static let audio = UTType(known: "public.audio")
    public static let audiovisualContent = UTType(known: "public.audiovisual-content")
    public static let mpeg4Movie = UTType(known: "public.mpeg-4")
    public static let quickTimeMovie = UTType(known: "com.apple.quicktime-movie")
    public static let mpeg2TransportStream = UTType(known: "public.mpeg-2-transport-stream")
    public static let avi = UTType(known: "public.avi")
    public static let mpeg = UTType(known: "public.mpeg")
    public func conforms(to type: UTType) -> Bool { false }
    public var preferredFilenameExtension: String? { nil }
}
