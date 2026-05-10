import XCTest

@MainActor
final class VoiceForgeUITests: XCTestCase {
    private let referenceAudioPath = "/Users/kaviantoniovasudeo/Downloads/Sound Creation/Reference/Kayden < 30 seconds.mp3"
    private let referenceText = "This is a short reference sample for testing."
    private var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        launchedApp?.terminate()
        launchedApp = nil
    }

    func testPromptFormattingPreviewUpdates() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_EMOTION_TEXT": "Whisper",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "*excited* This is only a preview test."
        ])

        let preview = app.staticTexts["formattedPreviewText"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let previewText = textContent(of: preview)
        XCTAssertTrue(previewText.contains("[whispering softly and quietly]"))
        XCTAssertTrue(previewText.contains("[excited and energetic]"))
    }

    func testGenerationWorkflowProducesOutput() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "This is a GUI generation test."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let playButton = app.buttons["playOutputButton"]
        XCTAssertTrue(waitUntilEnabled(playButton, timeout: 120))

        let saveButton = app.buttons["saveOutputButton"]
        let revealButton = app.buttons["revealOutputButton"]
        XCTAssertTrue(waitUntilEnabled(saveButton, timeout: 5))
        XCTAssertTrue(waitUntilEnabled(revealButton, timeout: 5))
    }

    func testCustomVoicesAndSettingsWindowsOpen() {
        let settingsApp = launchApp()

        let openSettingsButton = settingsApp.buttons["openSettingsButton"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 10))
        openSettingsButton.click()

        let outputPathText = settingsApp.staticTexts["settingsOutputPathText"]
        XCTAssertTrue(outputPathText.waitForExistence(timeout: 10))
        XCTAssertTrue(textContent(of: outputPathText).contains("voiceforge_output.wav"))

        settingsApp.terminate()
        launchedApp = nil

        let voicesApp = launchApp()

        let openCustomVoicesButton = voicesApp.buttons["openCustomVoicesButton"]
        XCTAssertTrue(openCustomVoicesButton.waitForExistence(timeout: 10))
        openCustomVoicesButton.click()

        let presetNameField = voicesApp.textFields["presetNameField"]
        XCTAssertTrue(presetNameField.waitForExistence(timeout: 10))
    }

    func testCanSaveCustomVoicePresetFromCurrentReference() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText
        ])

        let openCustomVoicesButton = app.buttons["openCustomVoicesButton"]
        XCTAssertTrue(openCustomVoicesButton.waitForExistence(timeout: 10))
        openCustomVoicesButton.click()

        let presetNameField = app.textFields["presetNameField"]
        XCTAssertTrue(presetNameField.waitForExistence(timeout: 10))
        presetNameField.click()
        presetNameField.typeText("Kayden Test")

        let saveButton = app.buttons["saveCurrentReferenceButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        saveButton.click()

        let voicesList = app.tables["customVoicesList"]
        XCTAssertTrue(voicesList.waitForExistence(timeout: 10))
    }

    func testSettingsResetClearsReferenceFields() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_EMOTION_TEXT": "professional broadcast tone"
        ])

        let openSettingsButton = app.buttons["openSettingsButton"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 10))
        openSettingsButton.click()

        let resetButton = app.buttons["resetReferenceFieldsButton"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10))
        resetButton.click()

        let referenceAudioField = app.textFields["referenceAudioPathField"]
        let referenceTextField = app.textFields["referenceTextField"]
        let emotionField = app.textFields["emotionField"]

        XCTAssertEqual(stringValue(of: referenceAudioField), "")
        XCTAssertEqual(stringValue(of: referenceTextField), "")
        XCTAssertEqual(stringValue(of: emotionField), "")
    }

    func testSavedPresetCanBeAppliedBackToMainWindow() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText
        ])

        let openCustomVoicesButton = app.buttons["openCustomVoicesButton"]
        XCTAssertTrue(openCustomVoicesButton.waitForExistence(timeout: 10))
        openCustomVoicesButton.click()

        let presetNameField = app.textFields["presetNameField"]
        XCTAssertTrue(presetNameField.waitForExistence(timeout: 10))
        presetNameField.click()
        presetNameField.typeText("Reusable Kayden")

        let saveButton = app.buttons["saveCurrentReferenceButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        saveButton.click()

        let useButton = app.buttons["usePresetButton-Reusable Kayden"]
        XCTAssertTrue(useButton.waitForExistence(timeout: 10))
        useButton.click()

        XCTAssertEqual(stringValue(of: app.textFields["referenceAudioPathField"]), referenceAudioPath)
        XCTAssertEqual(stringValue(of: app.textFields["referenceTextField"]), referenceText)
    }

    func testGenerationAddsHistoryEntry() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "History entry generation."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()
        XCTAssertTrue(waitUntilHistoryContainsEntries(app, timeout: 10))
    }

    func testHistoryEntryReloadsReferenceFields() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Reload this history entry."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()
        XCTAssertTrue(waitUntilHistoryContainsEntries(app, timeout: 10))

        let openSettingsButton = app.buttons["openSettingsButton"]
        XCTAssertTrue(openSettingsButton.waitForExistence(timeout: 10))
        openSettingsButton.click()

        let resetButton = app.buttons["resetReferenceFieldsButton"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10))
        resetButton.click()

        app.typeKey(.escape, modifierFlags: [])

        let historyEntries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyEntry-"))
        XCTAssertGreaterThan(historyEntries.count, 0)
        let firstHistoryEntry = historyEntries.element(boundBy: 0)
        XCTAssertTrue(firstHistoryEntry.waitForExistence(timeout: 5))
        firstHistoryEntry.click()

        XCTAssertEqual(stringValue(of: app.textFields["referenceAudioPathField"]), referenceAudioPath)
        XCTAssertEqual(stringValue(of: app.textFields["referenceTextField"]), referenceText)
    }

    func testPlayButtonTogglesToPauseAfterPlaybackStarts() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Playback state verification."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let playButton = app.buttons["playOutputButton"]
        XCTAssertTrue(waitUntilEnabled(playButton, timeout: 10))
        playButton.click()

        XCTAssertTrue(waitUntil(timeout: 5) {
            playButton.label == "Pause" || (playButton.value as? String) == "Pause"
        })
    }

    func testGenerateShowsMissingTextError() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let errorText = app.staticTexts["Enter text to generate."]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
    }

    func testGenerateShowsMissingReferenceAudioError() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Reference audio is required."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let errorText = app.staticTexts["Choose a reference audio file."]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
    }

    func testGenerateShowsMissingReferenceTextError() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": referenceAudioPath,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Reference text is required."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let errorText = app.staticTexts["Enter the reference transcript."]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.isEnabled
    }

    private func textContent(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    private func stringValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-state", "--uitest-mock-generation"]
        app.launchEnvironment = environment.merging([
            "ApplePersistenceIgnoreState": "YES"
        ]) { current, _ in current }
        launchedApp = app
        app.launch()
        return app
    }

    private func waitUntilHistoryContainsEntries(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let entries = app.descendants(matching: .button).matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyEntry-"))
            if entries.count > 0 {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

}
