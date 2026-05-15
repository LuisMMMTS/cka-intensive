# Slides

Source format: **Marp** (markdown). Renders to PDF, HTML, or PPTX.

## Files

- `day1.md` — Day 1 deck (foundations, architecture, workloads, config)
- `day2.md` — Day 2 deck (services, DNS, ingress, Gateway API, NetworkPolicy)
- `day3.md` — Day 3 deck (scheduling, storage, RBAC, Helm, Kustomize, HPA)
- `day4.md` — Day 4 deck (kubeadm, TLS, etcd, CRDs, troubleshooting, mock)

## Render to PDF

Install once:
```sh
npm install -g @marp-team/marp-cli
# or, no-install one-shot:
# npx @marp-team/marp-cli@latest day1.md --pdf
```

Render:
```sh
marp day1.md --pdf
marp day2.md --pdf
marp day3.md --pdf
marp day4.md --pdf
# or all at once:
marp --pdf *.md
```

Outputs `day1.pdf`, etc.

## Render to HTML (for live presenting in a browser)

```sh
marp day1.md --html --output day1.html
open day1.html
```

Marp also has a [VS Code extension](https://marketplace.visualstudio.com/items?itemName=marp-team.marp-vscode) that previews live as you edit.

## Render to PowerPoint

```sh
marp day1.md --pptx
```

## Use the Makefile

From this directory:
```sh
make pdf      # all decks → PDF
make html     # all decks → HTML
make pptx     # all decks → PPTX
make clean    # remove generated files
```

## Editing tips

- Slides are separated by `---`
- Headings (`#`, `##`) become slide titles
- The frontmatter at the top sets theme, size, paginate, footer
- Code blocks render with the dark style defined in the frontmatter
- For speaker notes, use HTML comments: `<!-- this is a speaker note -->`

## Sharing with trainees

Render to PDF and commit alongside the markdown:
```sh
make pdf
git add *.md *.pdf && git commit -m "slides v1"
```

Or share PDF only (smaller download, no edit risk).
