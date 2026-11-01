# SwiftPM-first build. See AGENTS.md for details.
.PHONY: build test test-slow bundle dmg appcast run lint clean

# Command Line Tools (no Xcode) keep Swift Testing outside SwiftPM's default search
# paths, so plain `swift test` runs 0 tests there. Pass the paths explicitly in that case.
DEVELOPER_DIR_ACTIVE := $(or $(DEVELOPER_DIR),$(shell xcode-select -p 2>/dev/null))
ifneq (,$(findstring CommandLineTools,$(DEVELOPER_DIR_ACTIVE)))
TESTING_FW := $(DEVELOPER_DIR_ACTIVE)/Library/Developer/Frameworks
TESTING_LIB := $(DEVELOPER_DIR_ACTIVE)/Library/Developer/usr/lib
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING_FW) -Xlinker -F -Xlinker $(TESTING_FW) \
	-Xlinker -rpath -Xlinker $(TESTING_FW) -Xlinker -rpath -Xlinker $(TESTING_LIB)
# SwiftLint looks for sourcekitd inside Xcode unless told where the toolchain is.
LINT_ENV := TOOLCHAIN_DIR=$(DEVELOPER_DIR_ACTIVE)
endif

build:
	swift build

# Slow end-to-end suites (full-size scrolling pages, the whole OCR matrix) are tagged `.slow` and
# named `…SlowTests`; SwiftPM can't filter by tag, so the name selects them (#140).
SLOW_TESTS := SlowTests

test:
	# Serial, like CI: CPU-heavy suites starve the cooperative pool and time out blocking tests.
	swift test --no-parallel --skip $(SLOW_TESTS) $(TEST_FLAGS)

test-slow:
	# The slow tier only: nightly CI and the release workflow run it (#140).
	swift test --no-parallel --filter $(SLOW_TESTS) $(TEST_FLAGS)

bundle:
	scripts/bundle.sh

dmg:
	scripts/dmg.sh

appcast:
	scripts/appcast.sh

run: bundle
	-pkill -x ScreenCap
	open build/ScreenCap.app

lint:
	$(LINT_ENV) swiftlint --strict

clean:
	swift package clean
	rm -rf .build build dist
