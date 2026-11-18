#!/usr/bin/env bash
# Checks that repositories created from WSL on a Windows drive (clone, init)
# record core.autocrlf=false, so their work trees keep the line endings WSL git
# would check out, and that an explicit setting, an existing repository and the
# opt-out are left alone. Needs WSL with Git for Windows; makes scratch
# repositories under /mnt/c/Users/Public and removes them afterwards.
#
#   bash tests/new-repo-line-endings.sh

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

local_autocrlf() { "$wrapper" -C "$1" config --local --get core.autocrlf; }
crs() { tr -cd '\r' < "$1" | wc -c; }

cd "$scratch" || exit 1

"$wrapper" init -q source
check "init records core.autocrlf=false" false "$(local_autocrlf source)"
printf '#!/bin/sh\necho ok\n' > source/run.sh
"$wrapper" -C source add run.sh
"$wrapper" -C source -c user.name=test -c user.email=test@example.com commit -q -m test

"$wrapper" clone -q source clone
check "clone records core.autocrlf=false" false "$(local_autocrlf clone)"
check "clone checks out LF line endings" 0 "$(crs clone/run.sh)"

"$wrapper" -c core.autocrlf=true clone -q source explicit
check "an explicit core.autocrlf is left alone" "" "$(local_autocrlf explicit)"

"$wrapper" -C source config core.autocrlf input
"$wrapper" init -q source
check "git init of an existing repository keeps its setting" input "$(local_autocrlf source)"

WSL_GIT_NEW_REPO_AUTOCRLF= "$wrapper" clone -q source opted-out
check "WSL_GIT_NEW_REPO_AUTOCRLF= leaves git.exe's setting" "" "$(local_autocrlf opted-out)"

WSL_GIT_NEW_REPO_AUTOCRLF=input "$wrapper" init -q chosen
check "WSL_GIT_NEW_REPO_AUTOCRLF chooses the value" input "$(local_autocrlf chosen)"

if (( failures )); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
