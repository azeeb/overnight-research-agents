#!/usr/bin/env bash
# overnight-research-agents: one fresh, headless Claude Code run per paper, then a synthesis.
# Usage: ./run.sh [max-papers]      e.g. ./run.sh 1 to test on a single paper
set -u

# ---- Configuration (override with environment variables) -------------------
PAPERS_DIR="${PAPERS_DIR:-papers}"              # PDFs to process
REPORTS_DIR="${REPORTS_DIR:-reports}"           # one Markdown report per paper
CONTEXT_GLOB="${CONTEXT_GLOB:-context/*.md}"    # project brief(s) passed to every run
LOG_DIR="${LOG_DIR:-logs}"
CACHE_DIR="${CACHE_DIR:-.cache}"                # extracted text, git-ignored
PAPER_TOOLS="${PAPER_TOOLS:-Read,WebSearch,WebFetch}"
SYNTH_TOOLS="${SYNTH_TOOLS:-Read,Glob}"
GIT_SYNC="${GIT_SYNC:-true}"                    # pull before, commit + push after
NTFY_TOPIC="${NTFY_TOPIC:-}"                    # optional phone notification via ntfy.sh
MAX="${1:-999999}"
# -----------------------------------------------------------------------------

cd "$(dirname "$0")"
for cmd in claude pdftotext; do
  command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

mkdir -p "$REPORTS_DIR" "$LOG_DIR" "$CACHE_DIR"
LOG="$LOG_DIR/$(date +%F).log"
log() { echo "$(date +%T) $*" | tee -a "$LOG"; }

if [ "$GIT_SYNC" = true ] && git rev-parse --git-dir >/dev/null 2>&1; then
  git pull -q --rebase || log "WARN git pull failed, continuing with local copy"
fi

CONTEXT=""
for f in $CONTEXT_GLOB; do [ -f "$f" ] && CONTEXT+=$'\n\n'"$(cat "$f")"; done
[ -z "$CONTEXT" ] && log "WARN no context files matched $CONTEXT_GLOB; reports will be generic"

NEW=0; FAILED=0
for pdf in "$PAPERS_DIR"/*.pdf; do
  [ -e "$pdf" ] || { log "no PDFs in $PAPERS_DIR"; break; }
  [ "$NEW" -ge "$MAX" ] && break
  id=$(basename "$pdf" .pdf)
  out="$REPORTS_DIR/$id.md"
  [ -s "$out" ] && continue                                  # already done
  txt="$CACHE_DIR/$id.txt"
  pdftotext -layout "$pdf" "$txt" 2>>"$LOG" || { log "FAILED $id (pdftotext)"; FAILED=$((FAILED+1)); continue; }
  log "start $id"
  if claude -p "$(cat prompts/paper.md)

## Project context
$CONTEXT

## Paper
ID: $id. Extracted text: $txt. Original PDF: $pdf" \
      --allowedTools "$PAPER_TOOLS" > "$out.tmp" 2>>"$LOG" && [ -s "$out.tmp" ]; then
    mv "$out.tmp" "$out"; NEW=$((NEW+1)); log "done $id"
  else
    rm -f "$out.tmp"; FAILED=$((FAILED+1)); log "FAILED $id (will retry next run)"
  fi
done

if [ "$NEW" -gt 0 ]; then
  log "start synthesis"
  claude -p "$(cat prompts/synthesis.md)

Reports are in $REPORTS_DIR/.

## Project context
$CONTEXT" --allowedTools "$SYNTH_TOOLS" > "$REPORTS_DIR/_synthesis-$(date +%F).md" 2>>"$LOG" \
    && log "done synthesis" || log "FAILED synthesis"
fi

log "finished: $NEW new, $FAILED failed"

if [ "$GIT_SYNC" = true ] && git rev-parse --git-dir >/dev/null 2>&1 && [ "$NEW" -gt 0 ]; then
  git add "$REPORTS_DIR" "$LOG_DIR" && git commit -qm "research $(date +%F): $NEW new, $FAILED failed" \
    && git push -q || log "WARN git commit/push failed"
fi

if [ -n "$NTFY_TOPIC" ]; then
  curl -s -d "Research run: $NEW new, $FAILED failed" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || true
fi
