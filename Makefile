APP = build/EvenBetterTouchTool.app
SWIFTC = xcrun swiftc
CORE = $(wildcard Sources/Core/*.swift)
SOURCES = $(wildcard Sources/App/*.swift) $(CORE) main.swift
SIGN ?= -
SWIFTFLAGS = -swift-version 5 -O -target arm64-apple-macosx14.0 -module-cache-path build/module-cache

all: $(APP)/Contents/MacOS/EvenBetterTouchTool sign

$(APP)/Contents/MacOS/EvenBetterTouchTool: $(SOURCES) mt.h Resources/Info.plist Resources/AppIcon.icns LICENSE
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources build/module-cache
	$(SWIFTC) $(SWIFTFLAGS) -import-objc-header mt.h $(SOURCES) -o $@
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp LICENSE $(APP)/Contents/Resources/LICENSE

sign: $(APP)/Contents/MacOS/EvenBetterTouchTool
	codesign --force --sign "$(SIGN)" --identifier org.evenbettertouchtool.app $(APP)

Resources/AppIcon.icns: scripts/create-icon.swift
	mkdir -p build/AppIcon.iconset
	xcrun swift -module-cache-path build/module-cache scripts/create-icon.swift build/AppIcon.iconset

build/CoreTests: $(CORE) Tests/CoreTests.swift
	mkdir -p build/module-cache
	$(SWIFTC) $(SWIFTFLAGS) $(CORE) Tests/CoreTests.swift -o $@

build/AppModelTests: $(CORE) Sources/App/AppModel.swift Sources/App/ActionExecutor.swift Sources/App/TrackpadDriver.swift Tests/AppModelTests.swift mt.h
	mkdir -p build/module-cache
	$(SWIFTC) $(SWIFTFLAGS) -import-objc-header mt.h $(CORE) Sources/App/AppModel.swift Sources/App/ActionExecutor.swift Sources/App/TrackpadDriver.swift Tests/AppModelTests.swift -o $@

test: build/CoreTests build/AppModelTests
	./build/CoreTests
	./build/AppModelTests

check: all test
	$(APP)/Contents/MacOS/EvenBetterTouchTool --smoke-test
	codesign --verify --strict $(APP)
	plutil -lint $(APP)/Contents/Info.plist
	for script in Install.command install.sh uninstall.sh scripts/migrate-legacy.sh scripts/package.sh; do bash -n "$$script" || exit 1; done

run: all
	open $(APP)

install: all
	./install.sh

uninstall:
	./uninstall.sh

package: check
	./scripts/package.sh

clean:
	rm -rf build

.PHONY: all sign test check run install uninstall package clean
