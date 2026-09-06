# Hisab build helpers. CPU-heavy targets are expected to run behind
# ~/.claude/scripts/cpu-gate.sh on shared machines.
SIM := platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: gen build test run

gen:
	xcodegen generate

build: gen
	xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination '$(SIM)' -quiet build

test:
	cd HisabCore && swift test

run: build
	xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
	xcrun simctl install booted $$(xcodebuild -project Hisab.xcodeproj -scheme Hisab -destination '$(SIM)' -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $$3}')/Hisab.app
	xcrun simctl launch booted com.vedants.hisab
