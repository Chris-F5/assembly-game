OBJFORMAT = elf64

game: game.o
	ld $< -o $@

%.o: %.asm
	nasm -f $(OBJFORMAT) -o $@ $<

.PHONY = run clean

run: game
	./game

clean:
	rm -f game game.o
