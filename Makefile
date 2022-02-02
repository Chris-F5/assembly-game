OBJFORMAT = elf64

pong: pong.o
	ld $< -o $@

pong.o: pong.asm config.asm
	nasm -f $(OBJFORMAT) -o $@ $<

.PHONY = run clean

run: pong
	./pong

clean:
	rm -f pong pong.o
