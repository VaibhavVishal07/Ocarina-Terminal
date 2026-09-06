import AppKit
import Foundation
import Testing
@testable import OcarinaUI

@Suite("Dropping onto the terminal")
@MainActor
struct TerminalDropTests {

    /// A pasteboard of its own, so a test never reads or writes the one the
    /// person running it is using.
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ocarina-tests-\(UUID().uuidString)"))
    }

    @Test("A path only gets quotes when it needs them")
    func quoting() {
        #expect(DroppableTerminalView.quoted("/Users/me/notes.md") == "/Users/me/notes.md")
        #expect(DroppableTerminalView.quoted("/Users/me/My Screenshots/a.png")
                == "'/Users/me/My Screenshots/a.png'")
        // A quote in the name closes the quoting early, and the rest of the
        // path becomes shell syntax.
        #expect(DroppableTerminalView.quoted("/tmp/it's here.png") == #"'/tmp/it'\''s here.png'"#)
    }

    @Test("A dropped file becomes its path, ready for the next word")
    func fileDrop() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocarina drop \(UUID().uuidString).png")
        try Data([0x89, 0x50]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])

        let text = try #require(DroppableTerminalView.text(from: pasteboard))
        #expect(text == DroppableTerminalView.quoted(file.path) + " ")
        // The trailing space is the point: you drop a file *into* a sentence
        // you are still typing, and having to press space first is the kind of
        // thing that makes people go back to typing the path out.
        #expect(text.hasSuffix(" "))
    }

    @Test("An image with no file behind it is given one")
    func imageWithoutAFile() throws {
        // Dragged out of a browser or a message there is no path to insert,
        // which is where Terminal.app gives up. Writing the bytes out is what
        // turns it into something an agent can be pointed at.
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)

        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: .tiff)

        let text = try #require(DroppableTerminalView.text(from: pasteboard))
        let path = text.trimmingCharacters(in: CharacterSet(charactersIn: " '"))
        defer { try? FileManager.default.removeItem(atPath: path) }

        #expect(path.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(path.hasPrefix(DroppableTerminalView.droppedImageDirectory.path))
    }

    @Test("Dropped text never arrives already run")
    func textDrop() throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("echo hello\n", forType: .string)

        #expect(DroppableTerminalView.text(from: pasteboard) == "echo hello")
    }

    @Test("Nothing droppable reads as nothing")
    func emptyPasteboard() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        #expect(DroppableTerminalView.text(from: pasteboard) == nil)
    }
}

