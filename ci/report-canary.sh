#!/usr/bin/env bash
# ci/report-canary.sh — turn a workflow's job results into one tracker thread.
#
# W's CI is a set of canaries on a distribution that moves underneath it, and a
# canary nobody hears is not a canary. The email GitHub sends a scheduled
# workflow's author is easy to miss and goes to one person; an open issue is
# visible to anyone looking at the repository and says, plainly, that the tree is
# currently broken. So each workflow keeps exactly ONE thread: the first red run
# opens it, later red runs comment on it rather than filing duplicates, and the
# first green run closes and locks it. A closed thread is never reopened — a new
# outage is a new issue, because the interesting question about a recurrence is
# when it came back, and an endlessly reopened thread destroys that.
#
# The threads stay in the tracker after they close, alongside what the people
# running W file there. They are not deleted: a closed thread is the record of an
# outage — when it started, what each retry said, when it came back — which is the
# most useful thing a canary produces, and the API cannot delete an issue with the
# workflow's own token anyway. Telling the two apart is the title's job (every one
# of them is prefixed `[canary]`) and the label's.
#
#   ci/report-canary.sh <label> <title> <job>=<result> [<job>=<result> …]
#
# Every job of the run is passed in, name and outcome, and that is what lets the
# issue say something more useful than "it failed". The workflows are staged on
# purpose — static checks, then the image, then the install — and which stage
# went red already narrows the cause a long way: a red `check` is a defect in
# this repository, a red `iso` is usually upstream Arch, a red `e2e` means the
# image built and then did not install. stage_meaning below carries that
# sentence for each, so the person opening the issue starts in the right place
# instead of at the top of a 20 000-line log.
#
# Needs GH_TOKEN (issues:write) and RUN_URL. GH_REPO defaults to the workflow's.
set -euo pipefail

LABEL="${1:?usage: report-canary.sh <label> <title> <job>=<result>…}"
TITLE="${2:?usage: report-canary.sh <label> <title> <job>=<result>…}"
shift 2
(($#)) || { echo "report-canary.sh: no job results given" >&2; exit 2; }

: "${RUN_URL:?RUN_URL not set}"
export GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:?neither GH_REPO nor GITHUB_REPOSITORY set}}"

# What a failure at each stage usually means. Not a diagnosis — a starting point,
# and specifically an answer to the question this report could not answer before:
# is this W, or is this the world around it?
stage_meaning() { # <job name>
  case "$1" in
    check)  echo "A static suite went red. That is a defect in this repository — the tree, not upstream." ;;
    iso)    echo "The tree passed its checks and then would not build into an image. That is usually upstream Arch: an AUR package that stopped compiling, a package that left the repositories, a tool that changed its flags. Start with the failing step's log." ;;
    e2e*)   echo "The image built, and installing it did not finish or the installed system failed its assertions. The run's log artifact carries the installer and apply logs from inside the VM — read those before the job log." ;;
    *)      echo "See the failing step's log." ;;
  esac
}

# ── The verdict ───────────────────────────────────────────────────────────────
# Green requires EVERY job handed in to say `success`. Nothing else counts, and
# that is deliberate rather than strict for its own sake: the two ways this
# report could lie are both silences, not wrong words.
#
#   * `skipped` — a job that did not run tested nothing, so reading it as "fine"
#     turns a wiring mistake (a mistyped `needs`, a condition that stopped
#     matching) into a green canary over a scenario nobody ran. If a whole class
#     of run legitimately has nothing to report, the caller must not invoke this
#     script at all — that is a decision for the workflow's `if:`, where it is
#     visible, not a default buried here.
#   * an empty value — `needs.<job>.result` renders empty when the job is not in
#     `needs`, so the one typo that would silently drop a job from the verdict
#     lands as a failure instead.
#
# The roster is printed before the verdict, so the run log always shows exactly
# what was judged rather than leaving it to be inferred from a summary line.
echo "Judging ${#} job result(s):"
failed=()
for pair in "$@"; do
  job="${pair%%=*}"; result="${pair#*=}"
  printf '  %-16s %s\n' "$job" "${result:-<empty>}"
  [[ "$result" == success ]] || failed+=("$job")
done

gh label create "$LABEL" --color B60205 \
  --description "$TITLE" >/dev/null 2>&1 || true

num="$(gh issue list --label "$LABEL" --state open --limit 1 \
        --json number --jq '.[0].number // empty')"

if ((${#failed[@]} == 0)); then
  [[ -n "$num" ]] || { echo "green, and no open issue — nothing to report."; exit 0; }
  gh issue comment "$num" --body "Green again — $RUN_URL"
  gh issue close "$num"
  # Locked once it is closed, because this thread is a machine's record of one
  # outage and not a place to report anything. The tracker is shared with the
  # people running W, and a resolved canary is exactly the sort of thread someone
  # adds "I have this too" to — where no one is listening. Best-effort on purpose:
  # losing the lock is cosmetic, and it must never turn a green run red.
  gh issue lock "$num" --reason resolved >/dev/null 2>&1 || true
  echo "green: closed #$num"
  exit 0
fi

stage="${failed[0]}"
where="failed at: ${failed[*]}"

if [[ -n "$num" ]]; then
  gh issue comment "$num" --body "Still failing ($where) — $RUN_URL"
  echo "red: commented on #$num"
  exit 0
fi

gh issue create --title "$TITLE" --label "$LABEL" --body "$(cat <<EOF
$TITLE — $where.

$(stage_meaning "$stage")

Run: $RUN_URL

This issue is updated by each subsequent failure, and closed and locked by the
first green run. It is filed by CI, not by a person — if you are seeing this as a
user of W and have something to add, please open your own issue instead.
EOF
)"
echo "red: opened a new issue"
