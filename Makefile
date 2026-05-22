LAZARUS ?= /usr/share/lazarus
UNITDIR ?= build/units
OUTFILE ?= lutifer
FPC ?= fpc
FPCSRC ?= /usr/lib/fpc/3.2.2/source
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Linux)
  ifeq ($(UNAME_M),x86_64)
    ARCH := x86_64-linux
  else ifeq ($(UNAME_M),aarch64)
    ARCH := aarch64-linux
  else ifeq ($(UNAME_M),armv7l)
    ARCH := arm-linux
  else ifeq ($(UNAME_M),armv6l)
    ARCH := arm-linux
  else
    ARCH := $(UNAME_M)-linux
  endif
else
  ARCH := unknown
endif

PARAMS = \
  -FU$(UNITDIR) \
  -MObjFPC -Scgi \
  -O1 -gl \
  -vewnhi -l \
  -Fu$(LAZARUS)/lcl/units/$(ARCH) \
  -Fu$(LAZARUS)/lcl/units/$(ARCH)/gtk2 \
  -Fu$(LAZARUS)/components/lazutils/lib/$(ARCH) \
  -Fu$(LAZARUS)/packager/units/$(ARCH) \
  -Fu$(LAZARUS)/components/multithreadprocs/lib/$(ARCH) \
  -Fu$(FPCSRC)/packages/fcl-image/src \
  -Fu$(FPCSRC)/packages/fcl-base/src \
  -Fu. \
  -dLCL -dLCLgtk2 \
  -o$(OUTFILE)

.PHONY: all clean show

all: $(OUTFILE)

$(OUTFILE): lutifer.pas haldclut.pas | $(UNITDIR)
	$(FPC) $(PARAMS) lutifer.pas

$(UNITDIR):
	mkdir -p $(UNITDIR)

show:
	@echo UNAME_S=$(UNAME_S)
	@echo UNAME_M=$(UNAME_M)
	@echo ARCH=$(ARCH)
	@echo LAZARUS=$(LAZARUS)

clean:
	rm -rf build $(OUTFILE)

