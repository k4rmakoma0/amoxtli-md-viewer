import AppKit
import XCTest
@testable import Amoxtli

/// Drives a real `MarkdownTextView` in a window with synthesized events.
@MainActor
final class MarkdownTextViewTests: XCTestCase {
    private let link = URL(string: "https://example.com/ruta")
    private let workspace = FakeWorkspace()
    private let pasteboard = NSPasteboard.withUniqueName()
    private let prompter = FakeLinkWarningPrompter()
    private var window: NSWindow?
    private var viewModel: LinkInteractionViewModel?

    private var defaults = UserDefaults()
    private var suiteName = ""

    override func setUpWithError() throws {
        suiteName = "MarkdownTextViewTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeView(_ source: String) throws -> (MarkdownTextView, LinkInteractionViewModel) {
        let blocks = try MarkdownParser().parse(source).blocks
        guard case .paragraph(let content) = blocks.first else {
            throw XCTSkip("Se esperaba un párrafo")
        }
        let viewModel = LinkInteractionViewModel(
            workspace: workspace,
            pasteboard: pasteboard,
            trustedHosts: TrustedHostsStore(defaults: defaults),
            warningPrompter: prompter
        )
        let view = MarkdownTextView.make()
        view.links = viewModel
        view.setLinksUnderlined(false)
        view.setContent(content.attributedString(style: MarkdownTextStyle(.body, typography: Typography()), color: .labelColor))
        let size = view.fittingSize(forProposedWidth: 400)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: size.height)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(view)
        self.window = window
        self.viewModel = viewModel
        return (view, viewModel)
    }

    private func point(ofText text: String, in view: MarkdownTextView, fraction: CGFloat = 0.5) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(view.layoutManager)
        let textContainer = try XCTUnwrap(view.textContainer)
        let range = (view.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound)
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        return NSPoint(x: rect.minX + rect.width * fraction, y: rect.midY)
    }

    private func event(_ type: NSEvent.EventType, at point: NSPoint, in view: NSView) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }

    private func titles(of menu: NSMenu?) -> [String] {
        menu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
    }

    // MARK: - Hit testing and hover

    func testLinkIsFoundOnlyOverLinkText() throws {
        let (view, _) = try makeView("antes [enlace](https://example.com/ruta) después")
        XCTAssertEqual(view.link(at: try point(ofText: "enlace", in: view)), link)
        XCTAssertNil(view.link(at: try point(ofText: "antes", in: view)))
        XCTAssertNil(view.link(at: try point(ofText: "después", in: view)))
    }

    func testLinkEdgesAreExact() throws {
        let (view, _) = try makeView("antes [enlace](https://example.com/ruta) después")
        XCTAssertEqual(view.link(at: try point(ofText: "enlace", in: view, fraction: 0.02)), link)
        XCTAssertEqual(view.link(at: try point(ofText: "enlace", in: view, fraction: 0.98)), link)
        XCTAssertNil(view.link(at: try point(ofText: "s ", in: view, fraction: 0.2)))
    }

    func testLinkIsFoundInAVisibleWindowAwayFromTheScreenOrigin() throws {
        let (view, _) = try makeView("antes [enlace](https://example.com/ruta) y mucho más texto después")
        view.window?.setFrameOrigin(NSPoint(x: 200, y: 300))
        view.window?.orderFront(nil)
        view.frame.origin = NSPoint(x: 0, y: 40)
        XCTAssertEqual(view.link(at: try point(ofText: "enlace", in: view)), link)
    }

    func testLinkIsNotFoundBesideTheLine() throws {
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")
        let inside = try point(ofText: "enlace", in: view)
        XCTAssertNil(view.link(at: NSPoint(x: 390, y: inside.y)))
    }

    func testHoverReportsLinkAndClearsOnExit() throws {
        let (view, viewModel) = try makeView("antes [enlace](https://example.com/ruta) después")
        view.mouseMoved(with: try event(.mouseMoved, at: try point(ofText: "enlace", in: view), in: view))
        XCTAssertEqual(viewModel.hoveredLink, link)

        view.mouseMoved(with: try event(.mouseMoved, at: try point(ofText: "antes", in: view), in: view))
        XCTAssertNil(viewModel.hoveredLink)

        view.mouseMoved(with: try event(.mouseMoved, at: try point(ofText: "enlace", in: view), in: view))
        let exit = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        ))
        view.mouseExited(with: exit)
        XCTAssertNil(viewModel.hoveredLink)
    }

    func testTrackingAreasDoNotAccumulate() throws {
        let (view, _) = try makeView("texto")
        view.updateTrackingAreas()
        let count = view.trackingAreas.count
        view.updateTrackingAreas()
        XCTAssertEqual(view.trackingAreas.count, count)
    }

    // MARK: - Activation

    func testClickOpensThroughClassifier() async throws {
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")
        view.clicked(onLink: try XCTUnwrap(link), at: 0)
        for _ in 0..<100 where workspace.openedLinks.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(workspace.openedLinks, [try XCTUnwrap(link)])
    }

    func testRealMouseClickReachesTheLinkHandler() async throws {
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")
        let location = try point(ofText: "enlace", in: view)
        NSApp.postEvent(try event(.leftMouseUp, at: location, in: view), atStart: false)
        view.mouseDown(with: try event(.leftMouseDown, at: location, in: view))
        for _ in 0..<100 where workspace.openedLinks.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(workspace.openedLinks, [try XCTUnwrap(link)])
    }

    func testHoverOverLinkUsesPointingHandCursor() throws {
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")
        view.mouseMoved(with: try event(.mouseMoved, at: try point(ofText: "enlace", in: view), in: view))
        XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
    }

    func testClickOnUnsupportedSchemeOnlyShowsNotice() async throws {
        let (view, viewModel) = try makeView("[enlace](ftp://example.com)")
        view.clicked(onLink: try XCTUnwrap(URL(string: "ftp://example.com")), at: 0)
        for _ in 0..<100 where viewModel.notice == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(viewModel.notice?.reason, .unsupportedLink)
        XCTAssertEqual(workspace.openedLinks, [])
    }

    // MARK: - Misleading text

    private func waitForWarning() async throws {
        for _ in 0..<100 where prompter.warnings.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private var misleadingWarning: LinkWarning? {
        URL(string: "https://example.org").map {
            LinkWarning(link: $0, host: "example.org", reason: .misleadingText(claimedHost: "apple.com"))
        }
    }

    func testClickSendsTheWholeLinkTextEvenWithMixedStyles() async throws {
        let (view, _) = try makeView("antes [**apple**.com](https://example.org) después")
        let index = (view.string as NSString).range(of: "apple").location
        view.clicked(onLink: try XCTUnwrap(URL(string: "https://example.org")), at: index)
        try await waitForWarning()
        XCTAssertEqual(prompter.warnings, [try XCTUnwrap(misleadingWarning)])
    }

    func testReturnSendsTheLinkText() async throws {
        let (view, _) = try makeView("[apple.com](https://example.org)")
        view.insertTab(nil)
        view.insertNewline(nil)
        try await waitForWarning()
        XCTAssertEqual(prompter.warnings, [try XCTUnwrap(misleadingWarning)])
    }

    func testMenuItemsSendTheLinkText() async throws {
        let web = URL(filePath: "/Applications/Web.app")
        workspace.defaultApplication = web
        workspace.applications = [web]
        prompter.answer = LinkWarningAnswer(opens: false, alwaysTrusts: false)
        let (view, _) = try makeView("[apple.com](https://example.org)")
        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "apple", in: view), in: view))

        try invoke(menu?.items.first { $0.title == String(localized: "Abrir en \("Web")") })
        try await waitForWarning()
        XCTAssertEqual(prompter.warnings, [try XCTUnwrap(misleadingWarning)])

        try invoke(menu?.items.first { $0.title == String(localized: "Abrir con") }?.submenu?.items.first)
        for _ in 0..<100 where prompter.warnings.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(prompter.warnings.last, try XCTUnwrap(misleadingWarning))
        XCTAssertEqual(workspace.openedLinks, [])
    }

    // MARK: - Menus

    func testLinkMenuListsOpenOpenWithAndCopy() throws {
        let web = URL(filePath: "/Applications/Web.app")
        let another = URL(filePath: "/Applications/Another.app")
        workspace.defaultApplication = web
        workspace.applications = [web, another]
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")

        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "enlace", in: view), in: view))
        XCTAssertEqual(titles(of: menu), [String(localized: "Abrir en \("Web")"), String(localized: "Abrir con"), String(localized: "Copiar enlace")])

        let submenu = menu?.items.first { $0.title == String(localized: "Abrir con") }?.submenu
        XCTAssertEqual(submenu?.items.map(\.title), ["Another", "Web"])
        XCTAssertEqual(submenu?.items.map(\.state), [.off, .on])
        XCTAssertEqual(submenu?.items.compactMap(\.image?.size), [NSSize(width: 16, height: 16), NSSize(width: 16, height: 16)])
        XCTAssertEqual(submenu?.items.map(\.preferredImageVisibility), [.visible, .visible])
    }

    func testLinkMenuItemsPerformTheirActions() async throws {
        let web = URL(filePath: "/Applications/Web.app")
        workspace.defaultApplication = web
        workspace.applications = [web]
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")
        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "enlace", in: view), in: view))
        let expected = try XCTUnwrap(link)

        try invoke(menu?.items.first { $0.title == String(localized: "Copiar enlace") })
        XCTAssertEqual(pasteboard.string(forType: .string), expected.absoluteString)

        try invoke(menu?.items.first { $0.title == String(localized: "Abrir en \("Web")") })
        try invoke(menu?.items.first { $0.title == String(localized: "Abrir con") }?.submenu?.items.first)
        for _ in 0..<100 where workspace.openedLinks.isEmpty || workspace.openedWithApplication.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(workspace.openedLinks, [expected])
        XCTAssertEqual(workspace.openedWithApplication.map(\.application), [web])
    }

    private func invoke(_ item: NSMenuItem?) throws {
        try XCTUnwrap(item?.target as? MenuAction).invoke()
    }

    func testUnsupportedLinkMenuCanOnlyCopy() throws {
        let (view, _) = try makeView("[enlace](ftp://example.com)")
        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "enlace", in: view), in: view))
        XCTAssertEqual(titles(of: menu), [String(localized: "Enlace no admitido"), String(localized: "Copiar enlace")])
        XCTAssertEqual(menu?.items.first?.isEnabled, false)
    }

    func testAnchorMenuOffersGoToSection() throws {
        let (view, _) = try makeView("[enlace](#uno)")
        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "enlace", in: view), in: view))
        XCTAssertEqual(titles(of: menu), [String(localized: "Ir a la sección"), String(localized: "Copiar enlace")])
    }

    func testTextMenuHasCopyAndSelectAllButNotPaste() throws {
        let (view, _) = try makeView("texto seleccionado")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "texto", in: view), in: view))
        XCTAssertEqual(titles(of: menu), [String(localized: "Copiar"), String(localized: "Seleccionar todo")])
        XCTAssertEqual(menu?.items.first?.action, #selector(NSText.copy(_:)))
        XCTAssertEqual(menu?.items.last?.action, #selector(NSText.selectAll(_:)))
        XCTAssertFalse(menu?.items.contains { $0.action == #selector(NSText.paste(_:)) } ?? true)
    }

    func testCopyIsDisabledWithoutSelection() throws {
        let (view, _) = try makeView("texto")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let menu = view.menu(for: try event(.rightMouseDown, at: try point(ofText: "texto", in: view), in: view))
        menu?.update()
        XCTAssertEqual(menu?.items.first?.isEnabled, false)
    }

    // MARK: - Keyboard

    func testOnlyBlocksWithLinksAreTabStops() throws {
        let (withLink, _) = try makeView("[uno](https://a.example)")
        withLink.window?.orderBack(nil)
        XCTAssertTrue(withLink.canBecomeKeyView)

        let (withoutLink, _) = try makeView("solo texto")
        withoutLink.window?.orderBack(nil)
        XCTAssertFalse(withoutLink.canBecomeKeyView)
        XCTAssertTrue(withoutLink.acceptsFirstResponder, "Debe seguir siendo seleccionable con el mouse")
    }

    func testTabMovesThroughLinks() throws {
        let (view, viewModel) = try makeView("[uno](https://a.example) y [dos](https://b.example)")
        view.insertTab(nil)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "uno")
        XCTAssertEqual(viewModel.hoveredLink?.host(), "a.example")

        view.insertTab(nil)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "dos")

        view.insertBacktab(nil)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "uno")
    }

    func testBacktabWithoutSelectionStartsFromLastLink() throws {
        let (view, _) = try makeView("[uno](https://a.example) y [dos](https://b.example)")
        view.insertBacktab(nil)
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "dos")
    }

    func testReturnActivatesSelectedLink() async throws {
        let (view, _) = try makeView("[enlace](https://example.com/ruta)")
        view.insertTab(nil)
        view.insertNewline(nil)
        for _ in 0..<100 where workspace.openedLinks.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(workspace.openedLinks, [try XCTUnwrap(link)])
    }

    func testReturnWithoutSelectedLinkDoesNothing() async throws {
        let (view, _) = try makeView("texto")
        view.insertNewline(nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(workspace.openedLinks, [])
        XCTAssertEqual(view.string, "texto")
    }

    // MARK: - Configuration and sizing

    func testViewIsSelectableAndReadOnly() throws {
        let (view, _) = try makeView("texto")
        XCTAssertFalse(view.isEditable)
        XCTAssertTrue(view.isSelectable)
    }

    func testSizingWrapsToProposedWidth() throws {
        let (view, _) = try makeView(String(repeating: "palabra ", count: 40))
        let narrow = view.fittingSize(forProposedWidth: 100)
        let wide = view.fittingSize(forProposedWidth: 1000)
        XCTAssertGreaterThan(narrow.height, wide.height)
        XCTAssertLessThanOrEqual(narrow.width, 100)
    }

    func testSizingDoesNotLeaveProbeWidthBehind() throws {
        let (view, _) = try makeView(String(repeating: "palabra ", count: 40))
        _ = view.fittingSize(forProposedWidth: 100)
        XCTAssertEqual(view.textContainer?.size.width, view.bounds.width)
    }

    func testUnwrappedSizingIgnoresProposedWidth() throws {
        let (view, _) = try makeView(String(repeating: "palabra ", count: 40))
        view.wrapsLines = false
        let size = view.fittingSize(forProposedWidth: 100)
        XCTAssertGreaterThan(size.width, 100)
    }

    // MARK: - Attributed string

    func testInlineStylesBecomeAttributes() throws {
        let content = InlineText(runs: [
            InlineRun(text: "b", style: .strong),
            InlineRun(text: "i", style: .emphasis),
            InlineRun(text: "c", style: .code),
            InlineRun(text: "s", style: .strikethrough),
            InlineRun(text: "l", link: link),
        ])
        let string = content.attributedString(style: MarkdownTextStyle(.body, typography: Typography()), color: .labelColor)

        func font(at index: Int) throws -> NSFont {
            try XCTUnwrap(string.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
        }
        XCTAssertTrue(try font(at: 0).fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(try font(at: 1).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(try font(at: 2).fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertNotNil(string.attribute(.strikethroughStyle, at: 3, effectiveRange: nil))
        XCTAssertEqual(string.attribute(.link, at: 4, effectiveRange: nil) as? URL, link)
    }
}
