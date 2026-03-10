FLOWNET_DIR := $(abspath ../flownet)
FLOWNET_REPO := https://github.com/fitzee/flownet.git

.PHONY: deps build test clean

deps:
	@if [ ! -d "$(FLOWNET_DIR)" ]; then \
		echo "FlowNet not found at $(FLOWNET_DIR), cloning from GitHub..."; \
		git clone $(FLOWNET_REPO) $(FLOWNET_DIR); \
	else \
		echo "FlowNet found at $(FLOWNET_DIR)"; \
	fi

build: deps
	mx build

test: deps
	mx test

clean:
	rm -rf .m2c build
