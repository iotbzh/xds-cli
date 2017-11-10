# Makefile used to build xds-cli commands

# Application Name
TARGET=xds-cli


# Retrieve git tag/commit to set version & sub-version strings
GIT_DESC := $(shell git describe --always --tags)
VERSION := $(firstword $(subst -, ,$(GIT_DESC)))
SUB_VERSION := $(subst $(VERSION)-,,$(GIT_DESC))
ifeq ($(VERSION), )
	VERSION := unknown-dev
endif
ifeq ($(SUB_VERSION), )
	SUB_VERSION := $(shell date +'%Y-%m-%d_%H%M%S')
endif

# Configurable variables for installation (default /opt/AGL/...)
ifeq ($(origin DESTDIR), undefined)
	DESTDIR := /opt/AGL/xds/cli
endif

HOST_GOOS=$(shell go env GOOS)
HOST_GOARCH=$(shell go env GOARCH)
ARCH=$(HOST_GOOS)-$(HOST_GOARCH)
REPOPATH=github.com/iotbzh/$(TARGET)

EXT=
ifeq ($(HOST_GOOS), windows)
	EXT=.exe
endif

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
ROOT_SRCDIR := $(patsubst %/,%,$(dir $(mkfile_path)))
ROOT_GOPRJ := $(abspath $(ROOT_SRCDIR)/../../../..)
LOCAL_BINDIR := $(ROOT_SRCDIR)/bin
LOCAL_TOOLSDIR := $(ROOT_SRCDIR)/tools/${HOST_GOOS}
PACKAGE_DIR := $(ROOT_SRCDIR)/package

export GOPATH := $(shell go env GOPATH):$(ROOT_GOPRJ)
export PATH := $(PATH):$(LOCAL_TOOLSDIR)

VERBOSE_1 := -v
VERBOSE_2 := -v -x

# Release or Debug mode
ifeq ($(filter 1,$(RELEASE) $(REL)),)
	GO_LDFLAGS=
	# disable compiler optimizations and inlining
	GO_GCFLAGS=-N -l
	BUILD_MODE="Debug mode"
else
	# optimized code without debug info
	GO_LDFLAGS=-s -w
	GO_GCFLAGS=
	BUILD_MODE="Release mode"
endif


ifeq ($(SUB_VERSION), )
	PACKAGE_ZIPFILE := $(TARGET)_$(ARCH)-$(VERSION).zip
else
	PACKAGE_ZIPFILE := $(TARGET)_$(ARCH)-$(VERSION)_$(SUB_VERSION).zip
endif

.PHONY: all
all: vendor build

.PHONY: build
build:
	@echo "### Build $(TARGET) (version $(VERSION), subversion $(SUB_VERSION) - $(BUILD_MODE))";
	@cd $(ROOT_SRCDIR); $(BUILD_ENV_FLAGS) go build $(VERBOSE_$(V)) -i -o $(LOCAL_BINDIR)/$(TARGET)$(EXT) -ldflags "$(GO_LDFLAGS) -X main.AppVersion=$(VERSION) -X main.AppSubVersion=$(SUB_VERSION)" -gcflags "$(GO_GCFLAGS)" .

test: tools/glide
	go test --race $(shell $(LOCAL_TOOLSDIR)/glide novendor)

vet: tools/glide
	go vet $(shell $(LOCAL_TOOLSDIR)/glide novendor)

fmt: tools/glide
	go fmt $(shell $(LOCAL_TOOLSDIR)/glide novendor)

.PHONY: clean
clean:
	rm -rf $(LOCAL_BINDIR)/* debug $(ROOT_GOPRJ)/pkg/*/$(REPOPATH) $(PACKAGE_DIR)

.PHONY: distclean
distclean: clean
	rm -rf $(LOCAL_BINDIR) $(ROOT_SRCDIR)/tools glide.lock vendor


.PHONY: scripts
scripts:
	@mkdir -p $(LOCAL_BINDIR) && cp -rf scripts/*.sh scripts/xds-utils $(LOCAL_BINDIR)

.PHONY: release
release:
	RELEASE=1 make -f $(ROOT_SRCDIR)/Makefile clean build

package: clean vendor build
	@mkdir -p $(PACKAGE_DIR)/$(TARGET)
	@cp -a $(LOCAL_BINDIR)/*cli$(EXT) $(PACKAGE_DIR)/$(TARGET)
	@cp -r $(ROOT_SRCDIR)/conf.d $(ROOT_SRCDIR)/scripts $(PACKAGE_DIR)/$(TARGET)
	cd $(PACKAGE_DIR) && zip -r $(ROOT_SRCDIR)/$(PACKAGE_ZIPFILE) ./$(TARGET)

.PHONY: package-all
package-all:
	@echo "# Build linux amd64..."
	GOOS=linux GOARCH=amd64 RELEASE=1 make -f $(ROOT_SRCDIR)/Makefile package
	@echo "# Build windows amd64..."
	GOOS=windows GOARCH=amd64 RELEASE=1 make -f $(ROOT_SRCDIR)/Makefile package
	@echo "# Build darwin amd64..."
	GOOS=darwin GOARCH=amd64 RELEASE=1 make -f $(ROOT_SRCDIR)/Makefile package
	make -f $(ROOT_SRCDIR)/Makefile clean

.PHONY: install
install:
	@test -e $(LOCAL_BINDIR)/$(TARGET)$(EXT) || { echo "Please execute first: make all\n"; exit 1; }
	export DESTDIR=$(DESTDIR) && $(ROOT_SRCDIR)/scripts/install.sh

.PHONY: uninstall
uninstall:
	export DESTDIR=$(DESTDIR) && $(ROOT_SRCDIR)/scripts/install.sh uninstall

vendor: tools/glide glide.yaml
	$(LOCAL_TOOLSDIR)/glide install --strip-vendor

vendor/debug: vendor
	(cd vendor/github.com/iotbzh && \
		rm -rf xds-common && ln -s ../../../../xds-common && \
		rm -rf xds-agent && ln -s ../../../../xds-agent )

.PHONY: tools/glide
tools/glide:
	@test -f $(LOCAL_TOOLSDIR)/glide || { \
		echo "Downloading glide"; \
		mkdir -p $(LOCAL_TOOLSDIR); \
		curl --silent -L https://glide.sh/get | GOBIN=$(LOCAL_TOOLSDIR)  sh; \
	}

help:
	@echo "Main supported rules:"
	@echo "  all               (default)"
	@echo "  build"
	@echo "  release"
	@echo "  clean"
	@echo "  package"
	@echo "  install / uninstall"
	@echo "  distclean"
	@echo ""
	@echo "Influential make variables:"
	@echo "  V                 - Build verbosity {0,1,2}."
	@echo "  BUILD_ENV_FLAGS   - Environment added to 'go build'."
