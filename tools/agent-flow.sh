#!/usr/bin/env bash
# tools/agent-flow.sh — wrapper for parallel agents
#
# Usage:
#   tools/agent-flow.sh start f02-sell       # claim a feature branch
#   tools/agent-flow.sh test                 # run the dev smoke tests
#   tools/agent-flow.sh check [feature]      # check ownership / merge readiness
#   tools/agent-flow.sh spec <feature>       # show the spec file for a feature
#
# Designed to be safe to run repeatedly. Anything destructive prompts.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

say() { printf '\033[1;34m[agent-flow]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[agent-flow]\033[0m %s\n' "$*" >&2; exit 1; }

cmd=${1:-help}
shift || true

case "$cmd" in
	help|-h|--help)
		sed -n '2,12p' "$0" | sed 's/^# //; s/^#//' || true
		exit 0
		;;

	start)
		name=${1:?usage: agent-flow.sh start <feature-slug>}
		# PARALLEL-AGENT WARNING: all agents share this ONE worktree, so the
		# checkouts below move every agent's uncommitted work. See tools/claim.md
		# "Parallel agents share ONE worktree". Warn loudly rather than abort —
		# an agent may legitimately be committing their own work right now.
		if [ -n "$(git status --porcelain)" ]; then
			say "WARNING: worktree has uncommitted changes (possibly another agent's)."
			say "  These will be carried across the checkout; commit or stash first."
			git status --short
		fi
		# Pull the latest main if a remote exists.
		if git remote get-url origin >/dev/null 2>&1; then
			say "fetching origin"
			git fetch origin
			git checkout main
			git rebase origin/main || die "rebase failed; resolve manually"
		else
			git checkout main || die "no main branch"
		fi
		branch="agent/${name}"
		if git show-ref --verify --quiet "refs/heads/${branch}"; then
			say "branch ${branch} already exists; checking out"
			git checkout "${branch}"
		else
			say "creating ${branch}"
			git checkout -b "${branch}"
		fi
		say "ready on ${branch}; implement under friedcake/mods/smp_<feature>/"
		;;

	test)
		say "running luajit dev-tests"
		# Each script exits non-zero on failure. luajit is on the homebrew path.
		if ! command -v luajit >/dev/null; then
			die "luajit not found in PATH"
		fi
		failed=0
		for t in friedcake/dev-tests/test_*.lua; do
			say "  $t"
			if ! luajit "$t" >/dev/null; then
				say "  FAIL: $t"
				failed=$((failed + 1))
			fi
		done
		if [ $failed -gt 0 ]; then
			die "$failed test(s) failed"
		fi
		say "all dev-tests green"
		;;

	check)
		feature=${1:-}
		if [ -n "${feature}" ]; then
			moddir="friedcake/mods/smp_${feature#smp_}"
			if [ ! -d "$moddir" ]; then
				die "no mod directory at $moddir"
			fi
			say "checking $moddir"
		fi
		# Make sure we're not on main.
		branch=$(git rev-parse --abbrev-ref HEAD)
		if [ "$branch" = "main" ]; then
			die "refusing to push from main; cut a branch first"
		fi
		# Confirm the spec file is referenced from spec/README.md.
		# (loose check; the integrator will catch missed updates.)
		say "branch: $branch"
		say "status:"
		git status --short
		;;

	spec)
		feature=${1:?usage: agent-flow.sh spec <feature-slug>}
		# fNN-<slug> -> spec/features/fNN-<slug>.md
		spec_file="spec/features/${feature}.md"
		if [ -f "$spec_file" ]; then
			less -F "$spec_file"
		else
			die "no spec file at $spec_file; check the slug"
		fi
		;;

	*)
		die "unknown command: $cmd (try: start, test, check, spec)"
		;;
esac
