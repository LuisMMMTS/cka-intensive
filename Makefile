# PDF generation for the CKA Intensive materials.
#
# Two converters:
#   - marp-cli   for slide decks (trainees/slides/dayN.md → dist/slides/dayN.pdf)
#   - pandoc     for everything else (labs, primers, cheatsheet, trainer notes)
#
# Install once:
#   sudo apt-get install -y pandoc texlive-xetex texlive-fonts-recommended
#   npm install -g @marp-team/marp-cli
#
# Targets:
#   make            # everything (alias for `make all`)
#   make all        # slides + labs + handouts + trainer
#   make slides     # just the Marp decks  → dist/slides/
#   make labs       # all 20 labs          → dist/labs/
#   make handouts   # README + cheatsheet + setup guides + primers
#   make trainer    # trainer handbook     → dist/trainer/
#   make clean      # nuke dist/
#
# Re-running any target replaces (overwrites) the existing PDFs in place.

# ---------- tools ----------------------------------------------------------
PANDOC      := pandoc
MARP        := marp
PANDOC_OPTS := --pdf-engine=xelatex \
               -V geometry:margin=2cm \
               -V mainfont="DejaVu Sans" \
               -V monofont="DejaVu Sans Mono" \
               -V fontsize=10pt \
               --highlight-style=tango \
               --toc --toc-depth=2

# ---------- discovery ------------------------------------------------------
SLIDE_SRCS    := $(wildcard trainees/slides/day*.md)
LAB_SRCS      := $(wildcard trainees/day*/labs/*.md)
HANDOUT_SRCS  := trainees/README.md \
                 trainees/pre-course-setup.md \
                 trainees/vm-setup.md \
                 trainees/cheatsheet.md \
                 trainees/lab-reset.md \
                 trainees/resources.md \
                 trainees/linux-primer.md \
                 trainees/docker-primer.md
TRAINER_SRCS  := $(wildcard trainer/*.md)

# Map src.md → dist/<sub>/src.pdf (preserves filename, drops directory)
SLIDE_PDFS    := $(patsubst trainees/slides/%.md,dist/slides/%.pdf,$(SLIDE_SRCS))
LAB_PDFS      := $(patsubst trainees/%.md,dist/labs/%.pdf,$(LAB_SRCS))
HANDOUT_PDFS  := $(patsubst trainees/%.md,dist/handouts/%.pdf,$(HANDOUT_SRCS))
TRAINER_PDFS  := $(patsubst trainer/%.md,dist/trainer/%.pdf,$(TRAINER_SRCS))

# ---------- public targets -------------------------------------------------
.PHONY: all slides labs handouts trainer clean help
.DEFAULT_GOAL := all

all: slides labs handouts trainer
	@echo
	@echo "[make] all PDFs in dist/"

slides:   $(SLIDE_PDFS)
labs:     $(LAB_PDFS)
handouts: $(HANDOUT_PDFS)
trainer:  $(TRAINER_PDFS)

clean:
	rm -rf dist/

help:
	@sed -n '1,/^# ---------- tools/p' $(MAKEFILE_LIST) | sed 's/^# \?//'

# ---------- rules ----------------------------------------------------------
# Marp slide decks: lossless export via Marp CLI. Marp picks up the frontmatter
# (`marp: true`, theme, footer) automatically.
dist/slides/%.pdf: trainees/slides/%.md
	@mkdir -p $(@D)
	@echo "[marp] $< → $@"
	@$(MARP) --pdf --allow-local-files -o $@ $<

# Lab PDFs. Lab paths look like trainees/day1/labs/lab2.md; the patsubst
# above flattens them into dist/labs/day1/labs/lab2.pdf which is a directory
# we want to create.
dist/labs/%.pdf: trainees/%.md
	@mkdir -p $(@D)
	@echo "[pandoc] $< → $@"
	@$(PANDOC) $(PANDOC_OPTS) -o $@ $<

# Handouts (cheatsheet, setup guides, primers).
dist/handouts/%.pdf: trainees/%.md
	@mkdir -p $(@D)
	@echo "[pandoc] $< → $@"
	@$(PANDOC) $(PANDOC_OPTS) -o $@ $<

# Trainer notes.
dist/trainer/%.pdf: trainer/%.md
	@mkdir -p $(@D)
	@echo "[pandoc] $< → $@"
	@$(PANDOC) $(PANDOC_OPTS) -o $@ $<
