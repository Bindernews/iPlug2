
CWD = $(shell pwd)
SCRIPTS_DIR := ../Scripts
EMBEDC_PY := $(SCRIPTS_DIR)/embedc.py
EMBEDC_OUTPUT := $(CWD)/embedc-bundle.c
EMBEDC_INPUTS := \
	fonts/=../IPlug/resource/Roboto-Regular.ttf \
	$(SCRIPTS_DIR)/SetFileIcon \
	renamed.sh=$(SCRIPTS_DIR)/notarise.sh \
	/python/=$(SCRIPTS_DIR)/s*.py \
	$(SCRIPTS_DIR)/icons/*.ico

.PHONY: test-embedc
test-embedc: $(EMBEDC_OUTPUT)

$(EMBEDC_OUTPUT): $(EMBEDC_PY)
#	python $(EMBEDC_PY) --show -C $(SCRIPTS_DIR) -o saved.txt $(EMBEDC_INPUTS)
	python $(EMBEDC_PY) --bundle --convert -C $(SCRIPTS_DIR) -o $(EMBEDC_OUTPUT) $(EMBEDC_INPUTS)
