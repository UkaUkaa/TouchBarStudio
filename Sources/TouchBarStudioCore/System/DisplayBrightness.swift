import CoreGraphics
import Foundation

/// Brightness of the built-in display through the DisplayServices framework (private,
/// the one Control Center uses; it works on Apple silicon and Intel). Its functions are
/// looked up at runtime: if a macOS release removes them, `isAvailable` is false and the
/// brightness keys fall back to posting key events.
public enum DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Functions: @unchecked Sendable {
        let get: GetFunction
        let set: SetFunction
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return Functions(get: unsafeBitCast(get, to: GetFunction.self), set: unsafeBitCast(set, to: SetFunction.self))
    }()

    /// Steps used by the hardware brightness keys.
    public static let steps: Float = 16

    public static var isAvailable: Bool { current() != nil }

    /// The built-in display, or the main display on Macs without one.
    static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success {
            if let builtIn = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) { return builtIn }
        }
        return CGMainDisplayID()
    }

    /// 0…1, or nil when the brightness can't be read.
    public static func current() -> Float? {
        guard let functions else { return nil }
        var value: Float = 0
        guard functions.get(display, &value) == 0 else { return nil }
        return min(1, max(0, value))
    }

    public static func set(_ value: Float) throws {
        guard let functions, functions.set(display, min(1, max(0, value))) == 0 else { throw ActionError.brightnessNotAvailable }
    }

    /// One hardware-key step up or down.
    public static func step(up: Bool) throws {
        guard let value = current() else { throw ActionError.brightnessNotAvailable }
        try set(stepped(value, up: up))
    }

    static func stepped(_ value: Float, up: Bool) -> Float {
        min(1, max(0, ((value * steps).rounded() + (up ? 1 : -1)) / steps))
    }
}
