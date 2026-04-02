import XCTest
@testable import ClaudeStudio

final class ChatComposerAvailabilityTests: XCTestCase {
    private func makeQuestion(
        sessionId: String = UUID().uuidString,
        questionId: String = UUID().uuidString
    ) -> AppState.AgentQuestion {
        AppState.AgentQuestion(
            id: questionId,
            sessionId: sessionId,
            question: "Continue?",
            options: nil,
            multiSelect: false,
            isPrivate: true,
            timestamp: Date(),
            inputType: "text",
            inputConfig: nil
        )
    }

    func testEmptyComposerDisablesSend() {
        XCTAssertNil(
            ChatComposerAvailability.submitAction(
                trimmedText: "",
                hasAttachments: false,
                isProcessing: false,
                pendingQuestions: [],
                hasPendingConfirmations: false
            )
        )
    }

    func testIdleComposerSendsNewMessage() {
        XCTAssertEqual(
            ChatComposerAvailability.submitAction(
                trimmedText: "Ship it",
                hasAttachments: false,
                isProcessing: false,
                pendingQuestions: [],
                hasPendingConfirmations: false
            ),
            .sendNewMessage(interruptsCurrentTurn: false)
        )
    }

    func testSinglePendingQuestionRoutesComposerReply() {
        let question = makeQuestion(sessionId: "session-1", questionId: "question-1")

        XCTAssertEqual(
            ChatComposerAvailability.submitAction(
                trimmedText: "yes",
                hasAttachments: false,
                isProcessing: true,
                pendingQuestions: [question],
                hasPendingConfirmations: false
            ),
            .answerPendingQuestion(sessionId: "session-1", questionId: "question-1")
        )
    }

    func testProcessingTurnCanBeInterruptedWhenNoUserInputIsPending() {
        XCTAssertEqual(
            ChatComposerAvailability.submitAction(
                trimmedText: "Keep going",
                hasAttachments: false,
                isProcessing: true,
                pendingQuestions: [],
                hasPendingConfirmations: false
            ),
            .sendNewMessage(interruptsCurrentTurn: true)
        )
    }

    func testProcessingTurnStaysBlockedWhenMultipleQuestionsArePending() {
        XCTAssertNil(
            ChatComposerAvailability.submitAction(
                trimmedText: "yes",
                hasAttachments: false,
                isProcessing: true,
                pendingQuestions: [makeQuestion(), makeQuestion()],
                hasPendingConfirmations: false
            )
        )
    }

    func testPendingConfirmationStillBlocksComposerSend() {
        XCTAssertNil(
            ChatComposerAvailability.submitAction(
                trimmedText: "go ahead",
                hasAttachments: false,
                isProcessing: true,
                pendingQuestions: [],
                hasPendingConfirmations: true
            )
        )
    }
}
