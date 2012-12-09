CC=gcc
INCLUDE=-I. -I../../
CFLAGS=$(INCLUDE)

DEP_MAIN = ../main.c hal.h ../../address_map.h ../../hardware/offsets/*.h

main.o: $(DEP_MAIN)
	$(CC) $(CFLAGS) -c $< -o $@

.PHONY: clean realclean
clean:
	$(RM) main.o

realclean: clean
	-$(RM) *~
