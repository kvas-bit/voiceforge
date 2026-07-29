import XCTest

@MainActor
final class VoiceForgeUITests: XCTestCase {
    private var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        launchedApp?.terminate()
        launchedApp = nil
    }

    // MARK: - Studio / generation

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
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "This is a short reference sample for testing.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "This is a GUI generation test."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let playButton = app.buttons["playOutputButton"]
        XCTAssertTrue(waitUntilEnabled(playButton, timeout: 30))

        let saveButton = app.buttons["saveOutputButton"]
        let revealButton = app.buttons["revealOutputButton"]
        XCTAssertTrue(waitUntilEnabled(saveButton, timeout: 5))
        XCTAssertTrue(waitUntilEnabled(revealButton, timeout: 5))
    }

    func testGenerateShowsMissingTextError() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let errorText = app.staticTexts["generationErrorText"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
        XCTAssertEqual(textContent(of: errorText), "Enter text to generate.")
    }

    func testGenerateShowsMissingReferenceAudioError() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Reference audio is required."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let errorText = app.staticTexts["generationErrorText"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
        XCTAssertEqual(textContent(of: errorText), "Choose a reference audio file.")
    }

    func testGenerateShowsMissingReferenceTextError() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Reference text is required."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()

        let errorText = app.staticTexts["generationErrorText"]
        XCTAssertTrue(errorText.waitForExistence(timeout: 10))
        XCTAssertEqual(textContent(of: errorText), "Enter the reference transcript.")
    }

    // MARK: - History

    func testGenerationAddsHistoryEntry() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "History entry generation."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()
        XCTAssertTrue(waitUntilEnabled(app.buttons["playOutputButton"], timeout: 30))

        goToSidebar(app, "History")
        XCTAssertTrue(waitUntilHistoryContainsEntries(app, timeout: 10))
    }

    /// Loading a history entry back into Studio ("Reuse") must populate the
    /// editor from that entry and surface the regeneration banner — without
    /// creating a new history entry until the user actually generates again.
    func testHistoryReuseLoadsIntoStudioWithRegenerationBanner() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Original generation for reuse test."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()
        XCTAssertTrue(waitUntilEnabled(app.buttons["playOutputButton"], timeout: 30))

        goToSidebar(app, "History")
        let firstEntry = firstHistoryEntry(app)
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 10))
        firstEntry.click()

        let reuseButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyReuseButton-"))
            .element(boundBy: 0)
        XCTAssertTrue(reuseButton.waitForExistence(timeout: 10))
        reuseButton.click()

        // Reuse navigates back to Studio and shows the regeneration banner.
        let banner = app.descendants(matching: .any)["regenerationBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
    }

    /// Regenerating an edited copy must produce a *second*, independent
    /// history entry (the original stays exactly as it was) and the new
    /// entry must carry a "Version of" breadcrumb back to the original.
    func testRegenerationCreatesLinkedVersionWithoutDestroyingOriginal() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Original generation for version test."
        ])

        let generateButton = app.buttons["generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()
        XCTAssertTrue(waitUntilEnabled(app.buttons["playOutputButton"], timeout: 30))

        goToSidebar(app, "History")
        XCTAssertTrue(waitUntilHistoryContainsEntries(app, timeout: 10))
        let originalCount = historyEntries(app).count
        XCTAssertEqual(originalCount, 1)

        let firstEntry = firstHistoryEntry(app)
        firstEntry.click()
        let reuseButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyReuseButton-"))
            .element(boundBy: 0)
        XCTAssertTrue(reuseButton.waitForExistence(timeout: 10))
        reuseButton.click()

        // Now back in Studio with the banner showing; regenerate as-is.
        XCTAssertTrue(app.descendants(matching: .any)["regenerationBanner"].waitForExistence(timeout: 10))
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10))
        generateButton.click()
        XCTAssertTrue(waitUntilEnabled(app.buttons["playOutputButton"], timeout: 30))

        goToSidebar(app, "History")
        XCTAssertTrue(waitUntil(timeout: 10) { self.historyEntries(app).count == 2 })

        // The newest entry (top of the list) is the regenerated version and
        // must show the "Version of" link back to the original.
        firstHistoryEntry(app).click()
        let versionLink = app.descendants(matching: .any)["historyVersionOfLink"]
        XCTAssertTrue(versionLink.waitForExistence(timeout: 10))
    }

    // MARK: - Voices

    func testVoicesNavigationAndNewVoiceSheet() {
        let app = launchApp()

        goToSidebar(app, "Voices")
        let newVoiceButton = app.buttons["newVoiceButton"]
        XCTAssertTrue(newVoiceButton.waitForExistence(timeout: 10))
        newVoiceButton.click()

        let presetNameField = app.textFields["presetNameField"]
        XCTAssertTrue(presetNameField.waitForExistence(timeout: 10))
    }

    func testCanSaveCustomVoicePresetFromCurrentReference() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript."
        ])

        goToSidebar(app, "Voices")
        let newVoiceButton = app.buttons["newVoiceButton"]
        XCTAssertTrue(newVoiceButton.waitForExistence(timeout: 10))
        newVoiceButton.click()

        let presetNameField = app.textFields["presetNameField"]
        XCTAssertTrue(presetNameField.waitForExistence(timeout: 10))
        presetNameField.click()
        presetNameField.typeText("Kayden Test")

        let saveButton = app.buttons["saveCurrentReferenceButton"]
        XCTAssertTrue(waitUntilEnabled(saveButton, timeout: 10))
        saveButton.click()

        let voiceCard = app.descendants(matching: .any)["voiceCard-Kayden Test"]
        XCTAssertTrue(voiceCard.waitForExistence(timeout: 10))
    }

    // MARK: - Sidebar navigation

    func testSidebarNavigationSwitchesDestinations() {
        let app = launchApp()

        goToSidebar(app, "Voices")
        XCTAssertTrue(app.buttons["newVoiceButton"].waitForExistence(timeout: 10))

        goToSidebar(app, "History")
        XCTAssertTrue(app.descendants(matching: .any)["historyList"].waitForExistence(timeout: 10))

        goToSidebar(app, "Conversations")
        XCTAssertTrue(app.buttons["conversationImportButton"].waitForExistence(timeout: 10))

        goToSidebar(app, "Studio")
        XCTAssertTrue(app.buttons["generateButton"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    private func goToSidebar(_ app: XCUIApplication, _ label: String) {
        let item = app.descendants(matching: .any)["sidebar\(label)"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Sidebar item \(label) not found")
        item.click()
    }

    private func historyEntries(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyEntry-"))
    }

    private func firstHistoryEntry(_ app: XCUIApplication) -> XCUIElement {
        historyEntries(app).element(boundBy: 0)
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

    private func launchApp(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        // Mock generation alone is sufficient isolation: it creates a brand
        // new temp-rooted HistoryStore + UserDefaults suite on every launch,
        // so there's no persistent state to reset between runs.
        app.launchArguments = ["--uitest-mock-generation"]
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
            if historyEntries(app).count > 0 {
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
