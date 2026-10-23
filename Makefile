APP := build/Foci.app
INSTALL_DIR := $(HOME)/Applications

.PHONY: build test app install run log clean e2e

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

# End-to-end tests against real windows, see Tests/E2E/SCENARIOS.md. Stops your Foci meanwhile and starts it again.
# make e2e E2E_ARGS='-k A'
e2e:
	python3 Tests/E2E/e2e.py $(E2E_ARGS)

clean:
	rm -rf .build build Tests/E2E/Probe/.build
