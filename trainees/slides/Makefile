DECKS := day1 day2 day3 day4
MARP  := npx --yes @marp-team/marp-cli@latest

.PHONY: pdf html pptx clean all

all: pdf

pdf:
	@for d in $(DECKS); do echo "→ $$d.pdf"; $(MARP) $$d.md --pdf --allow-local-files; done

html:
	@for d in $(DECKS); do echo "→ $$d.html"; $(MARP) $$d.md --html --allow-local-files; done

pptx:
	@for d in $(DECKS); do echo "→ $$d.pptx"; $(MARP) $$d.md --pptx --allow-local-files; done

clean:
	rm -f $(addsuffix .pdf,$(DECKS)) $(addsuffix .html,$(DECKS)) $(addsuffix .pptx,$(DECKS))
