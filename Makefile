ERLC ?= erlc
ERL ?= erl
DOCKER ?= docker
IMAGE ?= telecomerl:local
PORT ?= 8080
EBIN := _build/ebin
SOURCES := $(wildcard src/*.erl)

.PHONY: compile run device docker-build webserver clean

compile:
	mkdir -p $(EBIN)
	$(ERLC) -Werror -o $(EBIN) $(SOURCES)
	cp src/telecomerl.app.src $(EBIN)/telecomerl.app

run: compile
	TELECOM_STATIC_DIR=$(CURDIR)/static $(ERL) -pa $(EBIN) -noshell -eval 'telecomerl:start(), receive stop -> ok end.'

device:
	@command -v mmcli >/dev/null || { echo "ModemManager (mmcli) is required for device checks" >&2; exit 1; }
	@command -v nmcli >/dev/null || { echo "NetworkManager (nmcli) is required for APN and network checks" >&2; exit 1; }
	@mmcli -L | grep -q '/Modem/' || { echo "No ModemManager modem detected; connect and enable a supported modem" >&2; exit 1; }
	@$(MAKE) run

docker-build:
	$(DOCKER) build -t $(IMAGE) .

webserver: docker-build
	$(DOCKER) run --rm -p $(PORT):$(PORT) -e PORT=$(PORT) --env CHECK_INTERVAL_MS --env TELECOM_PROBE_URLS $(IMAGE)

clean:
	rm -rf _build