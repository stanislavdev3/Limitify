SWIFT_CACHE_PATH ?= /tmp/limitify-swiftpm-cache
SWIFT_MODULE_CACHE ?= /tmp/limitify-clang-cache
SWIFT_XDG_CACHE ?= /tmp/limitify-xdg-cache
SWIFT_BUILD_FLAGS ?=

SWIFT_ENV = CLANG_MODULE_CACHE_PATH=$(SWIFT_MODULE_CACHE) \
	SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFT_MODULE_CACHE) \
	XDG_CACHE_HOME=$(SWIFT_XDG_CACHE)

.PHONY: test build icon bundle dmg notarize clean

test:
	$(SWIFT_ENV) swift test $(SWIFT_BUILD_FLAGS) --cache-path $(SWIFT_CACHE_PATH) --scratch-path .build

build:
	$(SWIFT_ENV) swift build -c release $(SWIFT_BUILD_FLAGS) --cache-path $(SWIFT_CACHE_PATH) --scratch-path .build

icon:
	$(SWIFT_ENV) ./scripts/make-icon.sh

bundle: icon
	$(SWIFT_ENV) SWIFT_BUILD_FLAGS="$(SWIFT_BUILD_FLAGS) --cache-path $(SWIFT_CACHE_PATH)" ./scripts/build-app.sh

dmg: bundle
	./scripts/build-dmg.sh

notarize: dmg
	./scripts/notarize.sh

clean:
	swift package clean
	rm -rf .build-arm64 .build-x86_64 dist
