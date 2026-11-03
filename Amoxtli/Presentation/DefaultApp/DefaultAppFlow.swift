import Foundation

struct DefaultAppPromptAnswer: Equatable {
    let accepted: Bool
    let dontAskAgain: Bool
}

protocol DefaultAppPrompting {
    func askToSetAsDefault() -> DefaultAppPromptAnswer
    func showAlreadyDefault()
    func showFailure()
}

/// The two ways to become the default app for Markdown: the prompt at launch and the app menu.
struct DefaultAppFlow {
    private let checker: DefaultAppChecker
    private let prompter: any DefaultAppPrompting

    init(checker: DefaultAppChecker = DefaultAppChecker(), prompter: any DefaultAppPrompting = DefaultAppAlerts()) {
        self.checker = checker
        self.prompter = prompter
    }

    func promptAtLaunchIfNeeded() async {
        guard checker.shouldPromptAtLaunch else { return }
        let answer = prompter.askToSetAsDefault()
        if answer.dontAskAgain {
            checker.suppressPrompt()
        }
        if answer.accepted {
            await setAsDefault()
        }
    }

    func setAsDefaultFromMenu() async {
        if checker.isDefault {
            prompter.showAlreadyDefault()
        } else {
            await setAsDefault()
        }
    }

    /// The system shows its own confirmation, and declining it isn't a failure to report.
    private func setAsDefault() async {
        do {
            try await checker.setAsDefault()
        } catch where Self.isCancellation(error) {
            return
        } catch {
            prompter.showFailure()
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? CocoaError)?.code == .userCancelled
    }
}
