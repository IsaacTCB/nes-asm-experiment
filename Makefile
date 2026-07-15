NAME := cart

AS := ca65 --verbose
LD := ld65

SRCS := src/main.s
INCLUDES := --include-dir src
OBJS := $(patsubst src/%.s,build/%.o,$(SRCS))
DEPS := $(patsubst %.o,%.d,$(OBJS))

BUILD_ROM := $(NAME).nes

.PHONY: clean

$(BUILD_ROM): $(OBJS)
	$(LD) $(OBJS) -o $(BUILD_ROM) -t nes --dbgfile $(NAME).dbg

build/%.o: src/%.s
	mkdir -p $(@D)
	$(AS) -g $< -o $@ --create-dep "$(basename $@).d" -t nes

-include $(DEPS)

clean:
	rm -rf build
	rm -rf $(BUILD_ROM)
