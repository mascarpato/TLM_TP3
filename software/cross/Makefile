ifndef CROSS_COMPILE
CROSS_COMPILE=microblaze-unknown-linux-gnu-
endif

TARGET_CC = $(CROSS_COMPILE)gcc
TARGET_LD = $(CROSS_COMPILE)ld
TARGET_OBJDUMP = $(CROSS_COMPILE)objdump
TARGET_READELF = $(CROSS_COMPILE)readelf
HOST_CC = gcc
HOST_LD = ld
HOST_OBJDUMP = objdump
HOST_READELF = readelf

INCLUDE = -I. -I../..

OBJS = main.o boot.o it.o
EXEC = a.out
DEP_MAIN = ../main.c hal.h ../../address_map.h ../../hardware/offsets/*.h
# Disassembly of the generated executable.
dump.txt: $(EXEC)
	$(TARGET_OBJDUMP) -d $< > $@

# Summary of the sections and their size.
sections.txt: $(EXEC)
	$(TARGET_READELF) -S $< > $@


$(EXEC): $(OBJS)
	$(TARGET_LD) -T ldscript $(OBJS)

main.o: $(DEP_MAIN)
	$(TARGET_CC) $(INCLUDE) -c $< -o $@
	
%.o: %.s main.o
	$(TARGET_CC) -c $< -o $@

.PHONY: clean realclean
clean:
	-$(RM) $(OBJS) $(EXEC) dump.txt

realclean: clean
	-$(RM) *~
