APP := build/Foci.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: build test app install run log clean

build:
	swift build

test:
	swift test

app:
	scripts/bundle.sh

# Quits the running Foci (it restores parked windows on quit), installs and starts the new one.
install: app
	-pkill -TERM -x foci && sleep 1
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/Foci.app
	cp -R $(APP) $(INSTALL_DIR)/Foci.app
	mkdir -p $(HOME)/.local/bin
	ln -sf $(INSTALL_DIR)/Foci.app/Contents/MacOS/foci $(HOME)/.local/bin/foci
	open $(INSTALL_DIR)/Foci.app

run: build
	swift run foci

log:
	log stream --level info --predicate 'subsystem == "dev.foci"'

clean:
	rm -rf .build build
