SOURCES := sysedit.sh
INSTALL := install -v
TARGET := /usr/local/bin
SHELL := /bin/bash

all:
	:

install: $(SOURCES)
	@declare -A map=( [sysedit.sh]=se ); \
	for s in $^; do $(INSTALL) $$s $(TARGET)/$${map[$$s]}; done
