# Hisab build helpers. CPU-heavy targets are expected to run behind
# ~/.claude/scripts/cpu-gate.sh on shared machines.
SIM := platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: gen build test uitest run

gen:
	xcodegen generate

# CODE_SIGNING_ALLOWED=NO for the same reason `uitest` carries it: HisabCore's
# SwiftPM resource bundle can't be re-signed for the simulator. This target
# hardcodes a Simulator destination, so it can never be a signed device build.
build: gen
	xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination '$(SIM)' -quiet CODE_SIGNING_ALLOWED=NO build

test:
	cd HisabCore && swift test

# The insight strip's five device behaviours, driven through the real UI.
# CODE_SIGNING_ALLOWED=NO: HisabCore's SwiftPM resource bundle can't be
# re-signed for the simulator, and nothing here needs a signed build.
uitest: gen
	xcodebuild test -project Hisab.xcodeproj -scheme Hisab \
	  -destination '$(SIM)' CODE_SIGNING_ALLOWED=NO

run: build
	xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
	xcrun simctl install booted $$(xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination '$(SIM)' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $$3}')/Hisab.app
	xcrun simctl launch booted com.vedants.hisab
