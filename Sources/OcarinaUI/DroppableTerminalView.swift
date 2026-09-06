import AppKit
import SwiftTerm
import UniformTypeIdentifiers

/// A terminal you can drop a file — or an image — onto.
///
/// SwiftTerm's view registers no dragged types, so a drag over the terminal
/// showed the "no" cursor and a drop did nothing at all. Terminal.app has done
/// this since forever, and it is the one gesture that gets a path into a
/// prompt without typing it.
///
/// Two things here go past what Terminal.app does, both for the same reason —
/// the person at this prompt is talking to an agent, and what they want to
/// hand it is usually a picture:
///
/// * An image with no file behind it — dragged out of a browser, a message, a
///   screenshot straight off the desktop — is written to a real file first, so
///   there is a path to hand over. Terminal.app rejects those outright.
/// * The drop target is *visible*. Native gives no feedback until the drop has
///   already happened, so the only way to learn a terminal accepts files is to
///   be told. A frame that lights up says it before the mouse is released.
///
/// Nothing here presses Return: the path lands at the prompt and stops, which
/// is the same rule the paste inspector and Quick Actions follow.
public final class DroppableTerminalView: TerminalView {

    /// Called with the text to put at the prompt. Set by `TerminalSession`, so
    /// a drop goes through the same door as everything else typed here.
    ///
    /// The path *is* the receipt. A chip under the prompt was tried — thumbnail,
    /// name, an × that took the path back off the line — and it is one thing too
    /// many: the line already says what you attached, in the place you are about
    /// to press Return on.
    public var onDropText: ((String) -> Void)?

    /// Called as a drag enters and leaves, so the panel can draw the target.
    ///
    /// The frame used to be a layer inside this view, which is the wrong place
    /// for it: a 2pt outline is what a native app draws, and the person this
    /// is for has only ever seen the *web* version — the whole panel dimming,
    /// a dashed box, and a sentence telling them what dropping will do.
    /// SwiftUI draws that, over the panel, so this only has to say when.
    public var onDragStateChange: ((Bool) -> Void)?

    /// Where images that arrive without a file get written.
    ///
    /// Inside the temporary directory on purpose: the file exists so the agent
    /// has something to open, and the OS clears it out afterwards. Dropping a
    /// screenshot should not quietly fill up a folder somewhere.
    public static let droppedImageDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Ocarina Dropped Images", isDirectory: true)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
        watchForScrolling()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .png, .tiff, .string])
        watchForScrolling()
    }



    // MARK: - The scroller

    /// SwiftTerm's scroll indicator, which is a bare `NSScroller` sitting in
    /// the view rather than one inside an `NSScrollView`.
    ///
    /// That distinction is the whole bug. An overlay scroller only knows to
    /// fade itself out because a scroll view tells it to — on its own it is
    /// just a control, and it drew a knob down the right-hand edge of the
    /// terminal permanently, over text, in a window that has no other
    /// always-on furniture in it. A terminal at a prompt is not scrolling and
    /// should not say it is.
    private var scroller: NSScroller? {
        subviews.compactMap { $0 as? NSScroller }.first
    }

    private var scrollerFade: DispatchWorkItem?

    /// How long the scroller stays up after the last scroll, and how long it
    /// takes to go. Matched to the system's own overlay scrollers, which is
    /// the behaviour this is impersonating.
    private static let scrollerLinger: TimeInterval = 0.9
    private static let scrollerFadeDuration: TimeInterval = 0.4

    public override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        // The scroller is created lazily by SwiftTerm, so this is the first
        // moment there is one to hide.
        if let scroller = subview as? NSScroller { scroller.alphaValue = 0 }
    }

    /// Watches for scrolling without getting in the way of it.
    ///
    /// `scrollWheel` cannot be overridden — SwiftTerm declares it `public`
    /// rather than `open`, so the subclass is not allowed to see it — and a
    /// view laid over the terminal to catch the event would also swallow it.
    /// A local monitor observes the event and hands it straight back.
    private func watchForScrolling() {
        scrollMonitor.token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) { self.flashScroller() }
            return event
        }
    }

    /// Holds the monitor so it is taken down when the view goes.
    ///
    /// A box rather than a stored property with a `deinit` beside it: the
    /// token is `Any`, which is not `Sendable`, and a view's `deinit` is not
    /// isolated — so the view cannot touch it on the way out. The box can,
    /// and it dies with the view that owns it, which is the same moment.
    private final class ScrollMonitor: @unchecked Sendable {
        var token: Any?
        deinit {
            guard let token else { return }
            // Views are released on the main thread, which is where AppKit
            // wants this call.
            NSEvent.removeMonitor(token)
        }
    }

    private let scrollMonitor = ScrollMonitor()

    /// Show the scroller, then take it away again once scrolling has stopped.
    public func flashScroller() {
        guard let scroller else { return }
        scrollerFade?.cancel()
        scroller.alphaValue = 1

        let fade = DispatchWorkItem { [weak scroller] in
            guard let scroller else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.scrollerFadeDuration
                scroller.animator().alphaValue = 0
            }
        }
        scrollerFade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollerLinger, execute: fade)
    }

    // MARK: - Dragging destination

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        onDragStateChange?(true)
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragStateChange?(false)
    }

    public override func draggingEnded(_ sender: any NSDraggingInfo) {
        onDragStateChange?(false)
    }

    public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        accepts(sender)
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDragStateChange?(false)
        guard let text = Self.text(from: sender.draggingPasteboard), !text.isEmpty else {
            return false
        }
        onDropText?(text)
        return true
    }

    /// Whether there is anything here worth taking.
    ///
    /// Types only. `draggingUpdated` fires on every mouse move, and reading
    /// the drop properly means *writing a PNG* for an image that has no file
    /// behind it — so asking the real question here would have littered the
    /// temporary directory with a file per frame of the drag.
    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.availableType(from: Self.acceptedTypes) != nil
    }

    private static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .png, .tiff, .string]

    // MARK: - Reading the drop

    /// What to type for what was dropped.
    ///
    /// Files first: a drag that carries a file *and* a picture of it — which
    /// is most of them, since the source usually offers both — is a file, and
    /// the file already on disk beats a copy of it.
    public static func text(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls.map { quoted($0.path) }.joined(separator: " ") + " "
        }

        if let image = imageData(from: pasteboard), let url = write(image) {
            return quoted(url.path) + " "
        }

        // Text dropped from another app. The trailing newline comes off for
        // the same reason it does on paste: it would run the line the instant
        // it landed, and nobody confirmed that.
        if let string = pasteboard.string(forType: .string) {
            return PasteInspector.withoutTrailingNewline(string)
        }

        return nil
    }

    /// PNG as offered, otherwise whatever bitmap there is re-encoded as one.
    private static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let representation = NSBitmapImageRep(data: tiff)
        else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private static func write(_ png: Data) -> URL? {
        let directory = droppedImageDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // Named for the moment it was dropped, so a second image does not
        // overwrite the first and the name says which is which.
        let stamp = Self.stampFormatter.string(from: Date())
        let url = directory.appendingPathComponent("Dropped image \(stamp).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    /// A path safe to hand a shell.
    ///
    /// Single quotes rather than backslashes, which is what Terminal.app
    /// inserts: a backslash-escaped path is unreadable at a glance and, worse,
    /// stops being a path the moment someone edits the line around it. Quotes
    /// are added only when the path needs them, so the common case still looks
    /// like the path it is.
    public static func quoted(_ path: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-~"))
        guard path.unicodeScalars.contains(where: { !safe.contains($0) }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
