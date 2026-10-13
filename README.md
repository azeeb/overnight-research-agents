# overnight-research-agents

Drop research papers into a folder in the evening. Wake up to one structured report per
paper and a cross-paper synthesis.

It's a bash loop around [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
in headless mode: one fresh agent per paper, never one long session, then a final pass
that ranks what to act on. No framework, no queue, no database. That's the point.

Write-up: <link to your blog post>

## How it works

```
papers/*.pdf ──► pdftotext ──► fresh `claude -p` per paper ──► reports/<id>.md
                                                                    │
                                     reports/_synthesis-DATE.md ◄───┘
```

- **Fresh agent per paper.** Long sessions degrade as context fills; one failure can't sink the rest.
- **Text first, PDF second.** The agent reads the extracted text, then opens only the PDF
  pages with key tables and figures, which text extraction tends to scramble.
- **Same project brief every run.** `context/*.md` is passed into every prompt, so reports
  say how each paper applies to *your* project, not just what it says.
- **Idempotent.** Papers that already have a report are skipped, so a failed or
  rate-limited paper is simply retried on the next run.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code), logged in (`claude` on `PATH`)
- `pdftotext` (Ubuntu/Debian: `sudo apt install poppler-utils`; macOS: `brew install poppler`)
- git (optional, for syncing papers and reports between machines)

## Quick start

```bash
git clone https://github.com/<you>/overnight-research-agents.git
cd overnight-research-agents
cp context/brief.md.example context/brief.md   # describe your project, one page
cp ~/Downloads/*.pdf papers/
./run.sh 1                                      # test on one paper first
cat reports/*.md
./run.sh                                        # then the rest
```

Watch progress from another terminal with `tail -f logs/$(date +%F).log`.

## Configuration

Set environment variables before `./run.sh`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PAPERS_DIR` | `papers` | Where PDFs live |
| `REPORTS_DIR` | `reports` | Where reports are written |
| `CONTEXT_GLOB` | `context/*.md` | Project brief(s) passed to every run |
| `PAPER_TOOLS` | `Read,WebSearch,WebFetch` | Tools each paper run may use |
| `GIT_SYNC` | `true` | `git pull` before, commit and push reports after |
| `NTFY_TOPIC` | empty | Send a phone notification via [ntfy.sh](https://ntfy.sh) when done |

Edit `prompts/paper.md` to change the report format, and `prompts/synthesis.md` for the final pass.

## Running it overnight on a server

The pipeline is most useful on an always-on machine:

1. Create a dedicated, unprivileged user for the agent: no sudo, no access to other users' files.
2. Run the script inside a persistent terminal session (tmux, or [herdr](https://herdr.dev)
   for agent status at a glance) so it survives disconnects.
3. Use a repo-scoped **deploy key** for git, not your personal key.
4. Optionally cap the user's CPU and memory with a systemd slice.

## Security: read this

Papers are untrusted input. A PDF can contain hidden instructions ("prompt injection"),
and the agent reads it with tools that can read files and fetch URLs. In the worst case it
could be told to read a secret and send it to an attacker's URL.

Mitigations in this repo:

- Each paper run is headless with an explicit tool allow-list; nothing else is allowed.
- `.claude/settings.json` denies reads of common secret locations (`~/.ssh`, `~/.aws`,
  `~/.config`, `.env`) and denies Bash, Edit and Write.
- The prompts tell the agent to ignore instructions found inside papers. This helps, but
  is **not** a security boundary.

What you should still do:

- Run it as a low-privilege user on a machine with nothing truly secret on it.
- Verify the deny rules work in your setup before trusting them.
- Assume anything in the project folder, including your brief, could leak. If your fork
  is public, your `context/brief.md` is public too.

## License

MIT
