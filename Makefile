NAME := program

AS := ca65 --verbose
LD := ld65

SRCS := src/main.s src/player.s
INCLUDES := --include-dir src
OBJS := $(patsubst src/%.s,build/%.o,$(SRCS))
DEPS := $(patsubst %.o,%.d,$(OBJS))

ROM := $(NAME).nes
DBG := $(NAME).dbg

.PHONY: clean

$(ROM): $(OBJS)
	$(LD) $(OBJS) -o "$(ROM)" -t nes --dbgfile "$(DBG)"

build/%.o: src/%.s
	mkdir -p $(@D)
	$(AS) -g $< -o $@ --create-dep "$(basename $@).d" -t nes

-include $(DEPS)

clean:
	rm -rf build
	rm -rf $(ROM) $(DBG)
