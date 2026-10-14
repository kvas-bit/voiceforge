import XCTest
import AVFoundation

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

    func testMinorTranscriptDifferencesOfferWhisperVersionWithoutReplacingTypedText() {
        let typed = "Al sent the date on 1st June"
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": typed,
            "VOICEFORGE_UITEST_TRANSCRIBE_TEXT": "AI sent the day on first June",
            "VOICEFORGE_UITEST_WER": "0.036"
        ])
        goToSidebar(app, "Voices")
        let newVoiceButton = app.buttons["newVoiceButton"]
        XCTAssertTrue(newVoiceButton.waitForExistence(timeout: 10))
        newVoiceButton.click()
        let autoTranscribeButton = app.buttons["autoTranscribeMainButton"]
        XCTAssertTrue(autoTranscribeButton.waitForExistence(timeout: 10))
        autoTranscribeButton.click()

        let hint = app.descendants(matching: .any)["transcriptDifferenceHint-mainTranscriptSuggestion"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10))
        XCTAssertTrue(hint.label.contains("Possible transcript differences:"))
        XCTAssertEqual(app.textFields["referenceTranscriptField"].value as? String, typed)
        XCTAssertTrue(app.buttons["useTranscriptSuggestion-mainTranscriptSuggestion"].label.contains("Use Whisper version"))
        app.buttons["useTranscriptSuggestion-mainTranscriptSuggestion"].click()
        XCTAssertEqual(app.textFields["referenceTranscriptField"].value as? String, "AI sent the day on first June")
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
        let status = app.descendants(matching: .any)["generationRetryStatus"]
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

    func testSceneModeAssignsVoicesFromSpeakerCastRows() {
        let app = launchApp(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": "/tmp/voiceforge-uitest-ref.wav",
            "VOICEFORGE_UITEST_REFERENCE_TEXT": "Shared studio reference transcript."
        ])
        goToSidebar(app, "Conversations")
        let script = app.textViews["conversationScriptEditor"]
        XCTAssertTrue(script.waitForExistence(timeout: 10))
        script.click()
        script.typeText("Kayden: First line.\nEn0: Second line.")
        app.buttons["conversationImportButton"].click()

        let kaydenCastVoice = app.descendants(matching: .any)["speakerBrowseVoiceButton-kayden"]
        let en0CastVoice = app.descendants(matching: .any)["speakerBrowseVoiceButton-en0"]
        XCTAssertTrue(kaydenCastVoice.waitForExistence(timeout: 10), "Kayden should have one cast voice control")
        XCTAssertTrue(en0CastVoice.waitForExistence(timeout: 10), "En0 should have one cast voice control")
        app.buttons["speakerUseStudioVoiceButton-kayden"].click()
        app.buttons["speakerUseStudioVoiceButton-en0"].click()
        XCTAssertTrue(app.textFields["speakerReferenceTranscriptField-kayden"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["conversationBrowseVoiceButton-0"].exists,
            "Scene lines inherit the cast voice and should not show a second voice picker per line")
        XCTAssertFalse(app.descendants(matching: .any)["conversationBrowseVoiceButton-1"].exists,
            "Scene lines inherit the cast voice and should not show a second voice picker per line")
        XCTAssertTrue(waitUntilEnabled(app.buttons["conversationGenerateButton"], timeout: 5),
            "The scene should be ready after each speaker receives one complete cast voice")
    }

    func testRealDrama3SingleGeneration() throws {
        try requireRealModelUITests()
        let referenceText = try kaydenTranscript()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let startedAt = Date()
        let before = Set(outputWaveURLs().map(\.path))
        let app = launchRealDrama3App(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": kaydenAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": referenceText,
            "VOICEFORGE_UITEST_SOURCE_TEXT": "Hey! It is finally working. [laughs] I can not believe it."
        ])
        let generate = app.buttons["generateButton"]
        XCTAssertTrue(generate.waitForExistence(timeout: 20))
        generate.click()

        let playButton = app.buttons["playOutputButton"]
        XCTAssertTrue(waitUntilEnabled(playButton, timeout: 240), "Drama 3 did not finish within 240 seconds")
        let output = try XCTUnwrap(waitForNewPlayableWave(comparedTo: before, timeout: 10))
        XCTAssertGreaterThan(try wavDuration(at: output), 0)
        XCTAssertTrue(playButton.isEnabled, "The generated output playback control should be enabled")
        print("REAL_MODEL_UITEST single_generation_elapsed_seconds=\(Date().timeIntervalSince(startedAt)) output=\(output.path)")
    }

    func testRealDrama3ConversationSceneGeneration() throws {
        try requireRealModelUITests()
        let startedAt = Date()
        let before = Set(outputWaveURLs().map(\.path))
        let app = launchRealDrama3App(environment: [
            "VOICEFORGE_UITEST_REFERENCE_AUDIO": kaydenAudioPath,
            "VOICEFORGE_UITEST_REFERENCE_TEXT": try kaydenTranscript()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ])
        goToSidebar(app, "Conversations")
        let sceneToggle = app.descendants(matching: .any)["conversationSceneModeToggle"]
        XCTAssertTrue(sceneToggle.waitForExistence(timeout: 20))
        if !app.textFields["sceneDirectionField"].exists { sceneToggle.click() }
        XCTAssertTrue(app.textFields["sceneDirectionField"].exists)

        let script = app.textViews["conversationScriptEditor"]
        XCTAssertTrue(script.waitForExistence(timeout: 10))
        script.click()
        script.typeText("Kayden: Hey, it is good to be here.\nEn0: We asked over twenty different people, and they all said it was his.")
        app.buttons["conversationImportButton"].click()

        chooseAudioFile(app, buttonID: "speakerBrowseVoiceButton-kayden", path: kaydenAudioPath)
        chooseAudioFile(app, buttonID: "speakerBrowseVoiceButton-en0", path: en0AudioPath)
        let en0Transcript = app.textFields["speakerReferenceTranscriptField-en0"]
        XCTAssertTrue(en0Transcript.waitForExistence(timeout: 10))
        replaceText(in: en0Transcript, with: "We asked over twenty different people, and they all said it was his.")

        let generate = app.buttons["conversationGenerateButton"]
        XCTAssertTrue(waitUntilEnabled(generate, timeout: 10))
        generate.click()
        let playScene = app.buttons["Play scene"]
        XCTAssertTrue(waitUntilEnabled(playScene, timeout: 240), "Drama 3 scene did not finish within 240 seconds")
        let output = try XCTUnwrap(waitForNewPlayableWave(comparedTo: before, timeout: 10, fileName: "scene.wav"))
        XCTAssertGreaterThan(try wavDuration(at: output), 0)
        XCTAssertTrue(playScene.isEnabled, "The generated scene playback control should be enabled")
        print("REAL_MODEL_UITEST scene_generation_elapsed_seconds=\(Date().timeIntervalSince(startedAt)) output=\(output.path)")
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

    // Real-model fixtures live outside the repo (personal voice clips); override with env vars.
    private var realModelRefsDir: String {
        // The test runner is sandboxed, so NSHomeDirectory() points at its container.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return ProcessInfo.processInfo.environment["VOICEFORGE_REAL_MODEL_REFS"] ?? home + "/Projects/drama3/eval/refs"
    }
    private func kaydenTranscript() throws -> String {
        if let text = ProcessInfo.processInfo.environment["VOICEFORGE_REAL_KAYDEN_TEXT"], !text.isEmpty { return text }
        return try String(contentsOfFile: kaydenTranscriptPath, encoding: .utf8)
    }
    private var kaydenAudioPath: String { realModelRefsDir + "/kayden.wav" }
    private var en0AudioPath: String { realModelRefsDir + "/en0.wav" }
    private var kaydenTranscriptPath: String { realModelRefsDir + "/kayden.txt" }

    private func requireRealModelUITests() throws {
        guard ProcessInfo.processInfo.environment["VOICEFORGE_REAL_MODEL_UITEST"] == "1" else {
            throw XCTSkip("Set VOICEFORGE_REAL_MODEL_UITEST=1 to run real Drama 3 model UI tests.")
        }
    }

    private func launchRealDrama3App(environment: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-voiceforge.selectedTTSModel", "drama3", "-voiceforge.drama3ModelVariant", "q4"]
        app.launchEnvironment = environment.merging([
            "ApplePersistenceIgnoreState": "YES",
            "VOICEFORGE_DRAMA3_MODEL_DIR": "/Users/kaviantoniovasudeo/Library/Application Support/VoiceForge/models/drama-3-q4"
        ]) { current, _ in current }
        launchedApp = app
        app.launch()
        return app
    }

    private func chooseAudioFile(_ app: XCUIApplication, buttonID: String, path: String) {
        let chooseButton = app.descendants(matching: .any)[buttonID]
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 10))
        chooseButton.click()
        // NSOpenPanel shows as a dialog or as a sheet depending on presentation.
        let sheet = app.sheets.firstMatch
        let dialog = app.dialogs.firstMatch.waitForExistence(timeout: 5) ? app.dialogs.firstMatch : sheet
        XCTAssertTrue(dialog.waitForExistence(timeout: 10), "file picker did not appear")
        dialog.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = app.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))
        pathField.typeText(path)
        pathField.typeKey(.return, modifierFlags: [])
        // Scope to the picker: other "Open" buttons can exist elsewhere in the window.
        let openButton = dialog.buttons["Open"].firstMatch
        if openButton.waitForExistence(timeout: 5), openButton.isEnabled { openButton.click() }
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 10), "file picker did not close")
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func outputWaveURLs() -> [URL] {
        // Sandboxed runner: resolve the real home, not the runner container.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let outputRoot = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/VoiceForge/outputs", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: outputRoot, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "wav" }
    }

    private func waitForNewPlayableWave(comparedTo before: Set<String>, timeout: TimeInterval, fileName: String? = nil) -> URL? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let url = outputWaveURLs().first(where: {
                !before.contains($0.path) && (fileName == nil || $0.lastPathComponent == fileName)
                    && ((try? wavDuration(at: $0)) ?? 0) > 0
            }) {
                return url
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        return nil
    }

    private func wavDuration(at url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        guard file.fileFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
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
