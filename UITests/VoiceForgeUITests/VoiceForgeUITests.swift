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
        XCTAssertEqual(previewText, "*excited* This is only a preview test.")
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
        let originalCount = historyEntryCount(app)
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
        XCTAssertTrue(waitUntil(timeout: 10) { self.historyEntryCount(app) == 2 })

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

    func testAutoTranscribeKeepsTypedTranscriptAndOffersSuggestion() {
        let typed = "My carefully typed transcript."
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": typed
        ])
        goToSidebar(app, "Voices")
        let newVoiceButton = app.buttons["newVoiceButton"]
        XCTAssertTrue(newVoiceButton.waitForExistence(timeout: 10))
        newVoiceButton.click()
        XCTAssertTrue(app.textFields["presetNameField"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["autoTranscribeMainButton"].waitForExistence(timeout: 10))
        app.buttons["autoTranscribeMainButton"].click()
        let suggestion = app.staticTexts["mainTranscriptSuggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["typedTranscriptShown-mainTranscriptSuggestion"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["transcriptMismatchWarning-mainTranscriptSuggestion"].exists)
        app.buttons["keepTranscriptSuggestion-mainTranscriptSuggestion"].click()
        XCTAssertFalse(suggestion.exists)
        app.textFields["presetNameField"].click()
        app.textFields["presetNameField"].typeText("Typed kept")
        app.buttons["saveCurrentReferenceButton"].click()
        XCTAssertTrue(app.staticTexts[typed].waitForExistence(timeout: 10))
    }

    // MARK: - Sidebar navigation

    func testSidebarNavigationSwitchesDestinations() {
        let app = launchApp()

        goToSidebar(app, "Voices")
        XCTAssertTrue(app.buttons["newVoiceButton"].waitForExistence(timeout: 10))

        goToSidebar(app, "History")
        XCTAssertTrue(app.descendants(matching: .any)["historyList"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["sidebarStudio"].isHittable,
            "History must not collapse the app sidebar"
        )
        XCTAssertFalse(app.buttons["generateButton"].exists)
        XCTAssertFalse(app.buttons["inspectorToggleButton"].exists)

        goToSidebar(app, "Conversations")
        XCTAssertTrue(app.buttons["conversationImportButton"].waitForExistence(timeout: 10))

        goToSidebar(app, "Studio")
        XCTAssertTrue(app.buttons["generateButton"].waitForExistence(timeout: 10))
    }

    func testConversationKeyboardShortcutNavigates() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["generateButton"].waitForExistence(timeout: 10))
        app.typeKey("4", modifierFlags: .command)
        XCTAssertTrue(app.buttons["conversationImportButton"].waitForExistence(timeout: 10))
    }

    func testStudioInspectorPreferenceSurvivesNavigation() {
        let app = launchApp()

        let tone = app.textFields["emotionField"]
        XCTAssertTrue(tone.waitForExistence(timeout: 10))

        goToSidebar(app, "History")
        XCTAssertTrue(app.descendants(matching: .any)["historyList"].waitForExistence(timeout: 10))
        XCTAssertFalse(tone.exists, "Studio inspector content must be omitted from History")

        goToSidebar(app, "Studio")
        XCTAssertTrue(
            tone.waitForExistence(timeout: 10),
            "Returning to Studio must restore the inspector's previous visible state"
        )
    }

    func testStudioEditorAndInspectorFieldsAcceptInputAndQuickTags() {
        let app = launchApp()

        let editor = app.textViews["sourceTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(editor.isHittable)
        editor.click()
        editor.typeText("A real interaction test [")
        XCTAssertTrue((editor.value as? String)?.contains("A real interaction test [") == true)

        let quickTag = app.buttons["quickTag-[whispers]"]
        XCTAssertTrue(quickTag.waitForExistence(timeout: 10))
        XCTAssertTrue(quickTag.isHittable)
        quickTag.click()
        XCTAssertTrue((editor.value as? String)?.contains("[whispers]") == true)

        let tone = app.textFields["emotionField"]
        XCTAssertTrue(tone.waitForExistence(timeout: 10))
        XCTAssertTrue(tone.isHittable)
        tone.click()
        tone.typeText("warm narrator")
        XCTAssertEqual(tone.value as? String, "warm narrator")
    }

    func testDrama3ModelAndSamplingControls() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Generate the selected number of Drama 3 takes."
        ])
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.click()

        let modelPicker = app.descendants(matching: .any)["ttsModelPicker"]
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 10))
        modelPicker.click()
        let s2Option = app.menuItems["Fish Audio S2 Pro"]
        XCTAssertTrue(s2Option.waitForExistence(timeout: 5))
        s2Option.click()
        modelPicker.click()
        let drama3Option = app.menuItems["Fish Audio Drama 3"]
        XCTAssertTrue(drama3Option.waitForExistence(timeout: 5))
        drama3Option.click()

        let variantPicker = app.descendants(matching: .any)["drama3VariantPicker"]
        XCTAssertTrue(variantPicker.waitForExistence(timeout: 10))
        variantPicker.click()
        let q5Option = app.menuItems["High fidelity — q5 (~36 GB peak; close other heavy apps)"]
        XCTAssertTrue(q5Option.waitForExistence(timeout: 5))
        q5Option.click()
        XCTAssertTrue((variantPicker.value as? String)?.contains("High fidelity") == true)
        variantPicker.click()
        let q4Option = app.menuItems["Standard — q4 (~31 GB peak, default)"]
        XCTAssertTrue(q4Option.waitForExistence(timeout: 5))
        q4Option.click()

        let expressive = app.buttons["drama3ExpressivePresetButton"]
        XCTAssertTrue(expressive.waitForExistence(timeout: 10))
        expressive.click()
        XCTAssertTrue(app.staticTexts["Temperature: 1.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Top-p: 0.90"].exists)
        app.buttons["closeGenerationSettingsButton"].click()

        let takesPicker = app.descendants(matching: .any)["generateTakeCountPicker"]
        XCTAssertTrue(takesPicker.waitForExistence(timeout: 5))
        takesPicker.click()
        let threeTakes = app.menuItems["3 takes"]
        XCTAssertTrue(threeTakes.waitForExistence(timeout: 5), "Take count picker: \(takesPicker.debugDescription)")
        threeTakes.click()
        XCTAssertTrue((takesPicker.value as? String)?.contains("3 takes") == true)

        app.buttons["generateButton"].click()
        XCTAssertTrue(app.buttons["selectTake-2"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["selectTake-0"].exists)
        XCTAssertTrue(app.buttons["selectTake-1"].exists)
    }

    func testRetryEventShowsSubtleGenerationStatus() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Reference transcript.",
            "VOICEFORGE_UITEST_SOURCE_TEXT": "A retry status test.",
            "VOICEFORGE_UITEST_RETRY_REASON": "stall"
        ])
        app.buttons["generateButton"].click()
        let status = app.staticTexts["generationRetryStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Retrying take (stall detected)…")
        XCTAssertTrue(waitUntilEnabled(app.buttons["playOutputButton"], timeout: 15))
    }

    func testDrama3ConversationSceneModeToggle() {
        let app = launchApp()
        goToSidebar(app, "Conversations")

        let sceneToggle = app.descendants(matching: .any)["conversationSceneModeToggle"]
        XCTAssertTrue(sceneToggle.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["sceneDirectionField"].exists)
        sceneToggle.click()
        XCTAssertFalse(app.textFields["sceneDirectionField"].exists)
        sceneToggle.click()
        XCTAssertTrue(app.textFields["sceneDirectionField"].exists)
    }

    // MARK: - Helpers

    private func goToSidebar(_ app: XCUIApplication, _ label: String) {
        let item = app.descendants(matching: .any)["sidebar\(label)"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "Sidebar item \(label) not found")
        XCTAssertTrue(item.isHittable, "Sidebar item \(label) is present but not clickable")
        item.click()
    }

    private func historyEntries(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyRowSelect-"))
    }

    private func firstHistoryEntry(_ app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "historyRowSelect-"))
            .element(boundBy: 0)
    }

    private func historyEntryCount(_ app: XCUIApplication) -> Int {
        Set(historyEntries(app).allElementsBoundByIndex.map(\.identifier)).count
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
