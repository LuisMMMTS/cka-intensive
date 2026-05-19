# PDF generation for the CKA Intensive (public) materials.
#
# One converter: pandoc + weasyprint (HTML+CSS engine, no LaTeX needed).
# Slide decks render as paginated documents — not Marp-styled slides,
# but readable and self-contained. If you want Marp's actual slide
# rendering, install marp-cli separately and override the `marp` target.
#
# Trainer-only PDFs (handbook, schedule, scripts, solutions, quizzes) build
# from the private cka-intensive-trainer repo and have their own Makefile.
#
# Install once (macOS):
#   brew install pandoc weasyprint
# Install once (Debian):
#   sudo apt-get install -y pandoc python3-weasyprint
#
# Targets:
#   make            # everything (alias for `make all`)
#   make all        # slides + labs + handouts
#   make slides     # slide decks         → dist/slides/
#   make labs       # all 20 labs          → dist/labs/
#   make handouts   # README + cheatsheet + setup guides + primers
#   make clean      # nuke dist/
#
# Re-running any target replaces (overwrites) the existing PDFs in place.

# ---------- tools ----------------------------------------------------------
PANDOC      := pandoc
PANDOC_OPTS := --pdf-engine=weasyprint \
               --highlight-style=tango \
               --toc --toc-depth=2 \
               -V geometry:margin=2cm
PANDOC_SLIDE_OPTS := --pdf-engine=weasyprint \
                     --highlight-style=tango \
                     -V geometry:margin=1.5cm

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

SLIDE_PDFS    := $(patsubst trainees/slides/%.md,dist/slides/%.pdf,$(SLIDE_SRCS))
LAB_PDFS      := $(patsubst trainees/%.md,dist/labs/%.pdf,$(LAB_SRCS))
HANDOUT_PDFS  := $(patsubst trainees/%.md,dist/handouts/%.pdf,$(HANDOUT_SRCS))

# ---------- public targets -------------------------------------------------
.PHONY: all slides labs handouts clean help
.DEFAULT_GOAL := all

all: slides labs handouts
	@echo
	@echo "[make] all PDFs in dist/"

slides:   $(SLIDE_PDFS)
labs:     $(LAB_PDFS)
handouts: $(HANDOUT_PDFS)

clean:
	rm -rf dist/

help:
	@sed -n '1,/^# ---------- tools/p' $(MAKEFILE_LIST) | sed 's/^# \?//'

# ---------- rules ----------------------------------------------------------
# Slide decks rendered as paginated PDFs via pandoc + weasyprint. Marp
# frontmatter (`marp: true`, theme, footer) is ignored by pandoc; the
# document still reads well as study material.
dist/slides/%.pdf: trainees/slides/%.md
	@mkdir -p $(@D)
	@echo "[pandoc] $< → $@"
	@$(PANDOC) $(PANDOC_SLIDE_OPTS) -o $@ $<

# Lab PDFs. Lab paths look like trainees/day1/labs/lab2.md; the patsubst
# above flattens them into dist/labs/day1/labs/lab2.pdf.
dist/labs/%.pdf: trainees/%.md
	@mkdir -p $(@D)
	@echo "[pandoc] $< → $@"
	@$(PANDOC) $(PANDOC_OPTS) -o $@ $<

# Handouts (cheatsheet, setup guides, primers).
dist/handouts/%.pdf: trainees/%.md
	@mkdir -p $(@D)
	@echo "[pandoc] $< → $@"
	@$(PANDOC) $(PANDOC_OPTS) -o $@ $<
