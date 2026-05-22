UNITDIR ?= build/units
OUTFILE ?= lutifer
FPC ?= fpc

PARAMS = \
  -FU$(UNITDIR) \
  -MObjFPC -Scgi \
  -O3 -OoREGVAR -OoUNCERTAIN -OoLOOPUNROLL \
  -Xs -XX \
  -vewnhi \
  -Fu/usr/lib/fpc/3.2.2/units/$(shell uname -m)-linux/* \
  -Fu. \
  -o$(OUTFILE)

.PHONY: all clean

all: $(OUTFILE)

$(OUTFILE): lutifer.pas haldclut.pas | $(UNITDIR)
	$(FPC) $(PARAMS) lutifer.pas

$(UNITDIR):
	mkdir -p $(UNITDIR)

clean:
	rm -rf build $(OUTFILE) *.o *.ppu
