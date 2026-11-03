import UniformTypeIdentifiers
import XCTest
@testable import Amoxtli

@MainActor
final class DefaultAppTests: XCTestCase {
    private final class FakePrompter: DefaultAppPrompting {
        var answer = DefaultAppPromptAnswer(accepted: false, dontAskAgain: false)
        private(set) var promptCount = 0
        private(set) var alreadyDefaultCount = 0
        private(set) var failureCount = 0

        func askToSetAsDefault() -> DefaultAppPromptAnswer {
            promptCount += 1
            return answer
        }

        func showAlreadyDefault() {
            alreadyDefaultCount += 1
        }

        func showFailure() {
            failureCount += 1
        }
    }

    private let amoxtli = URL(fileURLWithPath: "/Applications/Amoxtli.app", isDirectory: true)
    private let another = URL(fileURLWithPath: "/Applications/Otra.app", isDirectory: true)
    private let workspace = FakeWorkspace()
    private let prompter = FakePrompter()
    private var defaults = UserDefaults()
    private var suiteName = ""

    override func setUp() async throws {
        suiteName = "DefaultAppTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var checker: DefaultAppChecker {
        DefaultAppChecker(workspace: workspace, applicationURL: amoxtli, defaults: defaults)
    }

    private var flow: DefaultAppFlow {
        DefaultAppFlow(checker: checker, prompter: prompter)
    }

    // MARK: - Checker

    func testIsDefaultWhenSystemResolvesToThisApp() {
        workspace.defaultMarkdownApplication = amoxtli
        XCTAssertTrue(checker.isDefault)
        XCTAssertFalse(checker.shouldPromptAtLaunch)
    }

    func testTrailingSlashDoesNotChangeTheAnswer() {
        workspace.defaultMarkdownApplication = URL(fileURLWithPath: "/Applications/Amoxtli.app", isDirectory: false)
        XCTAssertTrue(checker.isDefault)
    }

    func testIsNotDefaultWhenAnotherAppOpensMarkdown() {
        workspace.defaultMarkdownApplication = another
        XCTAssertFalse(checker.isDefault)
        XCTAssertTrue(checker.shouldPromptAtLaunch)
    }

    func testIsNotDefaultWhenNoAppOpensMarkdown() {
        workspace.defaultMarkdownApplication = nil
        XCTAssertFalse(checker.isDefault)
        XCTAssertTrue(checker.shouldPromptAtLaunch)
    }

    func testAnotherCopyOfTheAppIsNotThisApp() {
        workspace.defaultMarkdownApplication = URL(fileURLWithPath: "/Users/alguien/Amoxtli.app", isDirectory: true)
        XCTAssertFalse(checker.isDefault)
    }

    func testSuppressedPromptIsNotShownAndPersists() {
        workspace.defaultMarkdownApplication = another
        checker.suppressPrompt()
        let later = DefaultAppChecker(workspace: workspace, applicationURL: amoxtli, defaults: defaults)
        XCTAssertFalse(later.shouldPromptAtLaunch)
        XCTAssertFalse(later.isDefault)
    }

    func testSetAsDefaultAsksForTheMarkdownType() async throws {
        try await checker.setAsDefault()
        XCTAssertEqual(workspace.setDefaultRequests.map(\.application), [amoxtli])
        XCTAssertEqual(workspace.setDefaultRequests.map(\.contentType), [.markdown])
    }

    func testSetAsDefaultPropagatesSystemError() async {
        workspace.setDefaultError = FakeWorkspace.Failure()
        do {
            try await checker.setAsDefault()
            XCTFail("Se esperaba un error")
        } catch {
            XCTAssertTrue(error is FakeWorkspace.Failure)
        }
    }

    // MARK: - Launch prompt

    func testDoesNotPromptWhenAlreadyDefault() async {
        workspace.defaultMarkdownApplication = amoxtli
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(prompter.promptCount, 0)
    }

    func testDoesNotPromptAfterDontAskAgain() async {
        workspace.defaultMarkdownApplication = another
        checker.suppressPrompt()
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(prompter.promptCount, 0)
    }

    func testAcceptingSetsTheDefault() async {
        workspace.defaultMarkdownApplication = another
        prompter.answer = DefaultAppPromptAnswer(accepted: true, dontAskAgain: false)
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(workspace.setDefaultRequests.map(\.application), [amoxtli])
        XCTAssertTrue(checker.shouldPromptAtLaunch)
    }

    func testNotNowChangesNothingAndAsksAgainNextTime() async {
        workspace.defaultMarkdownApplication = another
        await flow.promptAtLaunchIfNeeded()
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(prompter.promptCount, 2)
        XCTAssertTrue(workspace.setDefaultRequests.isEmpty)
    }

    func testNotNowWithCheckboxStopsAsking() async {
        workspace.defaultMarkdownApplication = another
        prompter.answer = DefaultAppPromptAnswer(accepted: false, dontAskAgain: true)
        await flow.promptAtLaunchIfNeeded()
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(prompter.promptCount, 1)
        XCTAssertTrue(workspace.setDefaultRequests.isEmpty)
    }

    func testAcceptingWithCheckboxAlsoStopsAsking() async {
        workspace.defaultMarkdownApplication = another
        prompter.answer = DefaultAppPromptAnswer(accepted: true, dontAskAgain: true)
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(workspace.setDefaultRequests.count, 1)
        XCTAssertFalse(checker.shouldPromptAtLaunch)
    }

    func testSystemErrorIsReported() async {
        workspace.defaultMarkdownApplication = another
        workspace.setDefaultError = FakeWorkspace.Failure()
        prompter.answer = DefaultAppPromptAnswer(accepted: true, dontAskAgain: false)
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(prompter.failureCount, 1)
    }

    func testDecliningTheSystemConfirmationIsNotAFailure() async {
        workspace.defaultMarkdownApplication = another
        workspace.setDefaultError = CocoaError(.userCancelled)
        prompter.answer = DefaultAppPromptAnswer(accepted: true, dontAskAgain: false)
        await flow.promptAtLaunchIfNeeded()
        XCTAssertEqual(prompter.failureCount, 0)
    }

    // MARK: - App menu

    func testMenuSetsTheDefaultEvenAfterDontAskAgain() async {
        workspace.defaultMarkdownApplication = another
        checker.suppressPrompt()
        await flow.setAsDefaultFromMenu()
        XCTAssertEqual(workspace.setDefaultRequests.count, 1)
        XCTAssertEqual(prompter.promptCount, 0)
    }

    func testMenuReportsWhenAlreadyDefault() async {
        workspace.defaultMarkdownApplication = amoxtli
        await flow.setAsDefaultFromMenu()
        XCTAssertEqual(prompter.alreadyDefaultCount, 1)
        XCTAssertTrue(workspace.setDefaultRequests.isEmpty)
    }

    func testMenuReportsSystemError() async {
        workspace.defaultMarkdownApplication = another
        workspace.setDefaultError = FakeWorkspace.Failure()
        await flow.setAsDefaultFromMenu()
        XCTAssertEqual(prompter.failureCount, 1)
    }

    // MARK: - Real system

    func testBundleDeclaresMarkdownAsEditor() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        let markdown = try XCTUnwrap(types.first {
            ($0["LSItemContentTypes"] as? [String])?.contains(UTType.markdown.identifier) == true
        })
        XCTAssertEqual(markdown["CFBundleTypeRole"] as? String, "Editor")
    }

    func testRealWorkspaceAnswersWithoutChangingAnything() {
        _ = DefaultAppChecker(workspace: SystemWorkspace(), defaults: defaults).isDefault
    }
}
