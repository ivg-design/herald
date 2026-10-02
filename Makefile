.PHONY: build test install-cli install

build:
	swift build

test:
	swift test

# herald and herald-mcp (the MCP server for agents) go to /usr/local/bin, or ~/bin when that is not writable.
install-cli:
	./scripts/install-cli.sh
	swift build -c release --product herald-mcp
	@DEST=/usr/local/bin; \
	if [ ! -d "$$DEST" ] || [ ! -w "$$DEST" ]; then DEST="$$HOME/bin"; mkdir -p "$$DEST"; fi; \
	install -m 755 "$$(swift build -c release --show-bin-path)/herald-mcp" "$$DEST/herald-mcp"; \
	echo "Installed herald-mcp to $$DEST/herald-mcp (Claude Code: claude mcp add herald -- $$DEST/herald-mcp)"

# Release build of Herald.app into /Applications (ad-hoc signed locally; use scripts/notarize.sh for a distributable build)
# plus the herald CLI.
install: install-cli
	xcodegen generate
	xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Release -derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO
	rm -rf /Applications/Herald.app
	cp -R .build/xcode/Build/Products/Release/Herald.app /Applications/Herald.app
	@echo "Installed /Applications/Herald.app"

# The Worker as one ES module in Resources/relay (what Herald uploads to Cloudflare). Re-run after any change in relay/src.
.PHONY: relay-bundle
relay-bundle:
	./scripts/relay-bundle.sh
