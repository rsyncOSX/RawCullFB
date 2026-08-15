# sudo ditto "build/RawCullFB.app" "/Applications/RawCullFB.app"
APP = RawCullFB
BUNDLE_ID = no.blogspot.$(APP)
VERSION := $(shell grep -m 1 'MARKETING_VERSION' RawCullFB.xcodeproj/project.pbxproj | awk -F' = ' '{print $$2}' | tr -d ';')
BUILD_PATH = $(PWD)/build
APP_PATH = "$(BUILD_PATH)/$(APP).app"
ZIP_PATH = "$(BUILD_PATH)/$(APP).$(VERSION).zip"
DMG_PATH = $(PWD)/$(APP).$(VERSION).dmg
DMG_SHA256_PATH = $(DMG_PATH).sha256
MODEL_DOWNLOADER_PATH = $(BUILD_PATH)/$(APP).app/Contents/Extensions/RawCullFBModelDownloader.appex
TEST_DESTINATION = platform=macOS
XCODE_TEST_FLAGS = -project RawCullFB.xcodeproj -scheme $(APP) -destination '$(TEST_DESTINATION)' -onlyUsePackageVersionsFromResolvedFile
XCODE_RELEASE_FLAGS = -project RawCullFB.xcodeproj -scheme $(APP) -destination 'platform=macOS,arch=arm64' -configuration Release -onlyUsePackageVersionsFromResolvedFile

# Default target is release build
build: archive sign-app notarize staple prepare-dmg hash-dmg open

# Debug build - skips notarization and signing
debug: archive-debug open-debug

test-smoke:
	xcodebuild test $(XCODE_TEST_FLAGS) -enableCodeCoverage NO \
		-only-testing:RawCullFBTests/CLIPFeatureTests

test-full:
	xcodebuild test $(XCODE_TEST_FLAGS)

# --- MAIN WORKFLOW FUNCTIONS --- #
archive: clean
	osascript -e 'display notification "Exporting application archive..." with title "Build RawCullFB"'
	echo "Exporting application archive (RELEASE)..."
	xcodebuild \
		$(XCODE_RELEASE_FLAGS) archive \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive
	echo "Application built, starting the export archive..."
	xcodebuild -exportArchive \
		-exportOptionsPlist "exportOptions.plist" \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive \
		-exportPath $(BUILD_PATH) \
		-allowProvisioningUpdates
	echo "Project archived successfully (RELEASE)"

archive-debug: clean
	osascript -e 'display notification "Building debug version..." with title "Build RawCullFB"'
	echo "Building application (DEBUG)..."
	xcodebuild \
		-scheme $(APP) \
		-destination 'platform=OS X,arch=arm64' \
		-configuration Debug archive \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive
	echo "Application built, starting the export archive..."
	xcodebuild -exportArchive \
		-exportOptionsPlist "exportOptionsDebug.plist" \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive \
		-exportPath $(BUILD_PATH)
	echo "Debug build completed successfully"

sign-app:
	osascript -e 'display notification "Verifying Developer ID signatures..." with title "Build RawCullFB"'
	echo "Verifying exported Developer ID signatures..."
	@test -d "$(MODEL_DOWNLOADER_PATH)" || (echo "Missing model downloader extension: $(MODEL_DOWNLOADER_PATH)"; exit 1)
	@EXTENSION_SIGNATURE=$$(codesign -dv --verbose=4 "$(MODEL_DOWNLOADER_PATH)" 2>&1); \
		echo "$$EXTENSION_SIGNATURE"; \
		echo "$$EXTENSION_SIGNATURE" | grep -q "Authority=Developer ID Application:" || \
			(echo "RawCullFBModelDownloader is not signed with Developer ID Application"; exit 1); \
		echo "$$EXTENSION_SIGNATURE" | grep -q "Timestamp=" || \
			(echo "RawCullFBModelDownloader signature has no secure timestamp"; exit 1)
	codesign --verify --strict --verbose=4 "$(MODEL_DOWNLOADER_PATH)"
	codesign --verify --deep --strict --verbose=2 $(APP_PATH)
	@APP_SIGNATURE=$$(codesign -dv --verbose=4 $(APP_PATH) 2>&1); \
		echo "$$APP_SIGNATURE"; \
		echo "$$APP_SIGNATURE" | grep -q "Authority=Developer ID Application:" || \
			(echo "$(APP) is not signed with Developer ID Application"; exit 1); \
		echo "$$APP_SIGNATURE" | grep -q "Timestamp=" || \
			(echo "$(APP) signature has no secure timestamp"; exit 1)
	echo "Creating zip for notarization..."
	ditto -c -k --keepParent $(APP_PATH) $(ZIP_PATH)
	echo "Developer ID signatures verified successfully"

notarize:
	osascript -e 'display notification "Submitting app for notarization..." with title "Build RawCullFB"'
	echo "Submitting app for notarization..."
	@RESULT=$$(xcrun notarytool submit --keychain-profile "RsyncUI" --wait $(ZIP_PATH) 2>&1); \
	echo "$$RESULT"; \
	if echo "$$RESULT" | grep -q "status: Accepted"; then \
		echo "✅ $(APP) successfully notarized"; \
	else \
		echo "❌ Notarization failed!"; \
		SUBMISSION_ID=$$(echo "$$RESULT" | grep "id:" | head -1 | awk '{print $$2}'); \
		echo "Fetching detailed log for submission: $$SUBMISSION_ID"; \
		xcrun notarytool log "$$SUBMISSION_ID" --keychain-profile "RsyncUI"; \
		exit 1; \
	fi

staple:
	osascript -e 'display notification "Stapling $(APP)..." with title "Build RawCullFB"'
	echo "Stapling notarization ticket to application..."
	xcrun stapler staple $(APP_PATH)
	echo "Verifying stapled application..."
	spctl -a -t exec -vvv $(APP_PATH)
	osascript -e 'display notification "$(APP) successfully stapled" with title "Build RawCullFB"'
	echo "✅ $(APP) successfully stapled"

prepare-dmg:
	osascript -e 'display notification "Creating DMG..." with title "Build RawCullFB"'
	echo "Creating DMG installer..."
	../create-dmg/create-dmg \
		--volname "$(APP) ver $(VERSION)" \
		--background "./images/background.png" \
		--window-pos 200 120 \
		--window-size 500 320 \
		--icon-size 80 \
		--icon "$(APP).app" 125 175 \
		--hide-extension "$(APP).app" \
		--app-drop-link 375 175 \
		--no-internet-enable \
		--codesign 93M47F4H9T \
		"$(DMG_PATH)" \
		$(APP_PATH)
	echo "✅ DMG created successfully"
	@echo "Submitting DMG for notarization..."
	xcrun notarytool submit --keychain-profile "RsyncUI" --wait "$(DMG_PATH)"
	
	@echo "Stapling ticket to DMG..."
	xcrun stapler staple "$(DMG_PATH)"
	xcrun stapler validate "$(DMG_PATH)"
	hdiutil verify "$(DMG_PATH)"
	
	@echo "✅ DMG is now signed, notarized and stapled!"

hash-dmg:
	@echo "Writing final DMG SHA-256..."
	shasum -a 256 "$(DMG_PATH)" > "$(DMG_SHA256_PATH)"
	@cat "$(DMG_SHA256_PATH)"

verify-downloaded-dmg:
	@test -n "$(DOWNLOADED_DMG)" || (echo "Set DOWNLOADED_DMG to the downloaded DMG path"; exit 1)
	@test -f "$(DMG_SHA256_PATH)" || (echo "Missing $(DMG_SHA256_PATH)"; exit 1)
	@test -f "$(DOWNLOADED_DMG)" || (echo "Missing downloaded DMG: $(DOWNLOADED_DMG)"; exit 1)
	@EXPECTED=$$(awk '{print $$1}' "$(DMG_SHA256_PATH)"); \
	ACTUAL=$$(shasum -a 256 "$(DOWNLOADED_DMG)" | awk '{print $$1}'); \
	test "$$EXPECTED" = "$$ACTUAL" || (echo "Downloaded DMG SHA-256 mismatch"; exit 1); \
	echo "Downloaded DMG SHA-256 reproduced: $$ACTUAL"

# --- HELPERS --- #
clean:
	rm -rf $(BUILD_PATH)
	if [ -a "$(DMG_PATH)" ]; then rm "$(DMG_PATH)"; fi;
	if [ -a "$(DMG_SHA256_PATH)" ]; then rm "$(DMG_SHA256_PATH)"; fi;

check:
	xcrun notarytool log f62c4146-0758-4942-baac-9575190858b8 --keychain-profile "RsyncUI"

history:
	xcrun notarytool history --keychain-profile "RsyncUI"

check-cert:
	@echo "Available code signing certificates:"
	@security find-identity -v -p codesigning

open:
	osascript -e 'display notification "$(APP) signed and ready for distribution" with title "Build RawCullFB"'
	echo "Opening working folder..."
	open $(PWD)

open-debug:
	osascript -e 'display notification "$(APP) debug build ready" with title "Build RawCullFB"'
	echo "Opening working folder..."
	open $(PWD)
	echo "Debug build complete - app is at: $(APP_PATH)"

.PHONY: build debug test-smoke test-full archive archive-debug sign-app notarize staple prepare-dmg hash-dmg verify-downloaded-dmg clean check history check-cert open open-debug
