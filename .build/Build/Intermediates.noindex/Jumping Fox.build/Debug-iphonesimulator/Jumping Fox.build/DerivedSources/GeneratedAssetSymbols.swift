import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

    /// The "LaunchBackground" asset catalog color resource.
    static let launchBackground = ColorResource(name: "LaunchBackground", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "bear_no_background" asset catalog image resource.
    static let bearNoBackground = ImageResource(name: "bear_no_background", bundle: resourceBundle)

    /// The "bunny_no_background" asset catalog image resource.
    static let bunnyNoBackground = ImageResource(name: "bunny_no_background", bundle: resourceBundle)

    /// The "crab_no_background" asset catalog image resource.
    static let crabNoBackground = ImageResource(name: "crab_no_background", bundle: resourceBundle)

    /// The "dog_no_background" asset catalog image resource.
    static let dogNoBackground = ImageResource(name: "dog_no_background", bundle: resourceBundle)

    /// The "elephant_no_background" asset catalog image resource.
    static let elephantNoBackground = ImageResource(name: "elephant_no_background", bundle: resourceBundle)

    /// The "frog_no_background" asset catalog image resource.
    static let frogNoBackground = ImageResource(name: "frog_no_background", bundle: resourceBundle)

    /// The "lion_no_background" asset catalog image resource.
    static let lionNoBackground = ImageResource(name: "lion_no_background", bundle: resourceBundle)

    /// The "no_background" asset catalog image resource.
    static let noBackground = ImageResource(name: "no_background", bundle: resourceBundle)

    /// The "octupus_no_background" asset catalog image resource.
    static let octupusNoBackground = ImageResource(name: "octupus_no_background", bundle: resourceBundle)

    /// The "pinquin_no_background" asset catalog image resource.
    static let pinquinNoBackground = ImageResource(name: "pinquin_no_background", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .launchBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "LaunchBackground" asset catalog color.
    static var launchBackground: SwiftUI.Color { .init(.launchBackground) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "bear_no_background" asset catalog image.
    static var bearNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .bearNoBackground)
#else
        .init()
#endif
    }

    /// The "bunny_no_background" asset catalog image.
    static var bunnyNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .bunnyNoBackground)
#else
        .init()
#endif
    }

    /// The "crab_no_background" asset catalog image.
    static var crabNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .crabNoBackground)
#else
        .init()
#endif
    }

    /// The "dog_no_background" asset catalog image.
    static var dogNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .dogNoBackground)
#else
        .init()
#endif
    }

    /// The "elephant_no_background" asset catalog image.
    static var elephantNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .elephantNoBackground)
#else
        .init()
#endif
    }

    /// The "frog_no_background" asset catalog image.
    static var frogNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .frogNoBackground)
#else
        .init()
#endif
    }

    /// The "lion_no_background" asset catalog image.
    static var lionNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .lionNoBackground)
#else
        .init()
#endif
    }

    /// The "no_background" asset catalog image.
    static var noBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .noBackground)
#else
        .init()
#endif
    }

    /// The "octupus_no_background" asset catalog image.
    static var octupusNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .octupusNoBackground)
#else
        .init()
#endif
    }

    /// The "pinquin_no_background" asset catalog image.
    static var pinquinNoBackground: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pinquinNoBackground)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "bear_no_background" asset catalog image.
    static var bearNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .bearNoBackground)
#else
        .init()
#endif
    }

    /// The "bunny_no_background" asset catalog image.
    static var bunnyNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .bunnyNoBackground)
#else
        .init()
#endif
    }

    /// The "crab_no_background" asset catalog image.
    static var crabNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .crabNoBackground)
#else
        .init()
#endif
    }

    /// The "dog_no_background" asset catalog image.
    static var dogNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .dogNoBackground)
#else
        .init()
#endif
    }

    /// The "elephant_no_background" asset catalog image.
    static var elephantNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .elephantNoBackground)
#else
        .init()
#endif
    }

    /// The "frog_no_background" asset catalog image.
    static var frogNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .frogNoBackground)
#else
        .init()
#endif
    }

    /// The "lion_no_background" asset catalog image.
    static var lionNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .lionNoBackground)
#else
        .init()
#endif
    }

    /// The "no_background" asset catalog image.
    static var noBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .noBackground)
#else
        .init()
#endif
    }

    /// The "octupus_no_background" asset catalog image.
    static var octupusNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .octupusNoBackground)
#else
        .init()
#endif
    }

    /// The "pinquin_no_background" asset catalog image.
    static var pinquinNoBackground: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .pinquinNoBackground)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
@available(watchOS, unavailable)
extension ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
@available(watchOS, unavailable)
extension ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif