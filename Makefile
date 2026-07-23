NAME := program

AS := ca65 --verbose
LD := ld65
LD_CFG := nes.cfg

SRCS := src/main.s src/header.s src/player.s
INCLUDES := --include-dir src
OBJS := $(patsubst src/%.s,build/%.o,$(SRCS))
DEPS := $(patsubst %.o,%.d,$(OBJS))

ROM := $(NAME).nes
DBG := $(NAME).dbg

.PHONY: clean

$(ROM): $(OBJS) ${LD_CFG}
	$(LD) $(OBJS) -o "$(ROM)" --dbgfile "$(DBG)" -C "${LD_CFG}"

build/%.o: src/%.s
	mkdir -p $(@D)
	$(AS) -g $< -o $@ --create-dep "$(basename $@).d"

-include $(DEPS)

clean:
	rm -rf build
	rm -rf $(ROM) $(DBG)
