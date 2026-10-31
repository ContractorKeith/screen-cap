# SwiftPM-first build. See AGENTS.md for details.
.PHONY: build test bundle run lint clean

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

test:
	swift test $(TEST_FLAGS)

bundle:
	scripts/bundle.sh

run: bundle
	-pkill -x ScreenCap
	open build/ScreenCap.app

lint:
	$(LINT_ENV) swiftlint --strict

clean:
	swift package clean
	rm -rf .build build
