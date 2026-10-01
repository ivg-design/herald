.PHONY: build test install-cli install

build:
	swift build

test:
	swift test

install-cli:
	./scripts/install-cli.sh

# Release build of Herald.app into /Applications (ad-hoc signed locally; use scripts/notarize.sh for a distributable build)
# plus the herald CLI.
install: install-cli
	xcodegen generate
	xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Release -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO
	rm -rf /Applications/Herald.app
	cp -R .build/xcode/Build/Products/Release/Herald.app /Applications/Herald.app
	@echo "Installed /Applications/Herald.app"
