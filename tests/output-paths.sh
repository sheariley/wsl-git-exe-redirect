#!/usr/bin/env bash
# Checks that paths in git.exe's output come back as WSL paths (rev-parse,
# worktree list --porcelain) and that other output and the exit status pass
# through unchanged. Needs WSL with Git for Windows; makes a scratch repository
# under /mnt/c/Users/Public and removes it afterwards.
#
#   bash tests/output-paths.sh

set -u
wrapper=$(realpath "$(dirname "$0")/../git")
base=/mnt/c/Users/Public
scratch=$(mktemp -d "$base/wsl-git-exe-redirect-test.XXXXXX") || exit 1
trap 'rm -rf "$scratch"' EXIT
failures=0

check() {   # check <description> <expected> <actual>
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected '$2', got '$3'"
    failures=$((failures + 1))
  fi
}

repo=$scratch/repo
"$wrapper" init -q "$repo"
"$wrapper" -C "$repo" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m test
mkdir -p "$repo/sub/dir"

cd "$repo/sub/dir" || exit 1
check "rev-parse --show-toplevel" "$repo" "$("$wrapper" rev-parse --show-toplevel)"
check "rev-parse --absolute-git-dir" "$repo/.git" "$("$wrapper" rev-parse --absolute-git-dir)"
check "rev-parse --git-dir (absolute from a subdirectory)" "$repo/.git" "$("$wrapper" rev-parse --git-dir)"
check "rev-parse --show-prefix (relative, unchanged)" "sub/dir/" "$("$wrapper" rev-parse --show-prefix)"
check "rev-parse with several outputs" "$repo"$'\n'"sub/dir/" \
      "$("$wrapper" rev-parse --show-toplevel --show-prefix)"
check "rev-parse HEAD (not a path, unchanged)" "$("$wrapper" log -1 --format=%H)" "$("$wrapper" rev-parse HEAD)"

cd ~ || exit 1
check "-C from a Linux directory" "$repo" "$("$wrapper" -C "$repo" rev-parse --show-toplevel)"

"$wrapper" -C "$repo" rev-parse --verify --quiet refs/heads/does-not-exist
check "exit status passes through" 1 "$?"

check "worktree list --porcelain" "worktree $repo" \
      "$("$wrapper" -C "$repo" worktree list --porcelain | head -1)"

if (( failures )); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
