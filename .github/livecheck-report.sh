#!/bin/bash
# The weekly check from .github/workflows/livecheck.yml: is anything in this tap behind?
#
# - every formula, through `brew livecheck` (a newer release tag than the formula builds)
# - for each formula whose homepage is a GitHub repository: commits on its default branch that
#   the release the formula builds doesn't include yet (a reason to tag a new release)
#
# Writes a Markdown report to $REPORT (the job summary in Actions, stdout otherwise). When something
# is behind, opens an issue, or comments on the open one; DRY_RUN=1 only prints what it would post.
# Exits 1 when something couldn't be checked, so GitHub reports the run as failed.
set -euo pipefail

tap="${TAP:?set TAP, e.g. gtmn/tap}"
report="${REPORT:-/dev/stdout}"
issue_title="Updates available"

behind=()      # one Markdown line per outdated formula
problems=()    # one line per thing that couldn't be checked
unreleased=()  # one line per formula with commits after its release

# GitHub's API, with the workflow's token when there is one (public repositories work without).
api() { curl -sSf -m 30 ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "https://api.github.com/repos/$1"; }

if json="$(brew livecheck --tap "$tap" --json 2>/dev/null)"; then
  while IFS= read -r line; do behind+=("$line"); done < <(jq -r '.[]
    | select(.version.outdated == true)
    | "- `\(.formula // .cask)`: \(.version.current) → **\(.version.latest)**"' <<<"$json")
  while IFS= read -r line; do problems+=("$line"); done < <(jq -r '.[]
    | select(.status == "error")
    | "- `\(.formula // .cask)`: \((.messages // ["no version found"]) | join("; "))"' <<<"$json")
  checked="$(jq -r '.[] | "| `\(.formula // .cask)` | \(.version.current // "–") | \(.version.latest // .status // "–") |"' <<<"$json")"
else
  problems+=("- \`brew livecheck --tap $tap\` failed")
  json="[]"; checked=""
fi

# Commits after the release each formula builds (tag v<version> or <version>).
while IFS=$'\t' read -r name current; do
  homepage="$(brew info --json=v2 "$tap/$name" | jq -r '.formulae[0].homepage // empty')"
  [[ "$homepage" =~ ^https://github\.com/([^/]+/[^/]+)/?$ ]] || continue
  repo="${BASH_REMATCH[1]}"
  branch="$(api "$repo" | jq -r '.default_branch')" || { problems+=("- couldn't read $repo"); continue; }
  for tag in "v$current" "$current"; do
    if ahead="$(api "$repo/compare/$tag...$branch" 2>/dev/null | jq -r '.ahead_by')"; then break; fi
    ahead=""
  done
  if [[ -z "$ahead" ]]; then
    problems+=("- \`$name\`: no tag \`v$current\` in $repo")
  elif ((ahead > 0)); then
    unreleased+=("- \`$name\`: $ahead commit(s) on \`$branch\` since \`$tag\` ([compare](https://github.com/$repo/compare/$tag...$branch))")
  fi
done < <(jq -r '.[] | select(.formula and .version.current) | [.formula, .version.current] | @tsv' <<<"$json")

{
  echo "## Weekly version check for \`$tap\`"
  echo
  if ((${#behind[@]})); then echo "**Behind:**"; printf '%s\n' "${behind[@]}"; else echo "Every formula is current."; fi
  if ((${#problems[@]})); then echo; echo "**Couldn't check:**"; printf '%s\n' "${problems[@]}"; fi
  echo
  echo "| Name | Tap has | Latest |"; echo "|---|---|---|"; echo "$checked"
  echo
  if ((${#unreleased[@]})); then echo "**Not released yet:**"; printf '%s\n' "${unreleased[@]}"
  else echo "No unreleased commits."; fi
} >>"$report"

# Tell the owner through an issue when something is behind (one open issue, commented on after that).
if ((${#behind[@]})); then
  body="$(printf '%s\n' "These are newer upstream than in the tap:" "" "${behind[@]}")"
  if [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "DRY_RUN: would post to the \"$issue_title\" issue:"; echo "$body"
  else
    repo="${GITHUB_REPOSITORY:?}"
    open="$(gh issue list -R "$repo" --state open --search "in:title \"$issue_title\"" --json number --jq '.[0].number // empty')"
    if [[ -n "$open" ]]; then
      gh issue comment "$open" -R "$repo" --body "$body"
    else
      gh issue create -R "$repo" --title "$issue_title" --body "$body"
    fi
  fi
fi

((${#problems[@]} == 0))
