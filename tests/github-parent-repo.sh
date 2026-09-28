#!/bin/bash
# Regression test: `--github` / `--github-org` must never touch a git repository
# that merely ENCLOSES the project.
#
# 2026-09-28: PROJECTS_DIR (~/podium-projects) sat inside a git-backed home
# directory. create_github_repo saw "inside a work tree", skipped git init,
# re-pointed the HOME repo's origin at the new GitHub repo and pushed the whole
# home backup to it. This runs create_github_repo against a fake gh and local
# bare repos, with no network, and checks that the parent repo is untouched.
#
#   bash tests/github-parent-repo.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global init.defaultBranch master

# Fake gh: authenticated; "creating" a repo makes a local bare repo, and
# `repo view` reports that bare repo's path as its sshUrl.
mkdir -p "$T/bin" "$T/remotes"
cat > "$T/bin/gh" <<EOF
#!/bin/bash
R="$T/remotes"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "repo create") git init -q --bare "\$R/\$(echo "\$3" | tr / _).git"; echo "\$3" >> "$T/gh-created"; exit 0 ;;
  "repo view")   [ -d "\$R/\$(echo "\$3" | tr / _).git" ] || exit 1
                 case " \$* " in *" --json "*) echo "\$R/\$(echo "\$3" | tr / _).git" ;; esac; exit 0 ;;
esac
exit 1
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

run_create() { # <dir> <project name> -> exit code of create_github_repo
    ( set +u; cd "$1" && NO_COLOR=1 source "$REPO/src/scripts/functions.sh" >/dev/null 2>&1 \
        && create_github_repo "$2" org TestOrg "" private ) >"$T/out" 2>&1
}

# --- A parent repo with an origin and history, like a git-backed home dir ---
git init -q --bare "$T/remotes/home-backup.git"
HOME_REPO="$T/home"
mkdir -p "$HOME_REPO/projects"
git -C "$HOME_REPO" init -q
echo "secret" > "$HOME_REPO/CREDENTIALS.md"
git -C "$HOME_REPO" add -A && git -C "$HOME_REPO" commit -qm "home backup"
git -C "$HOME_REPO" remote add origin "$T/remotes/home-backup.git"
git -C "$HOME_REPO" push -q origin master
HOME_HEAD="$(git -C "$HOME_REPO" rev-parse HEAD)"
HOME_ORIGIN="$(git -C "$HOME_REPO" remote get-url origin)"

echo "Project inside a parent repo:"
P="$HOME_REPO/projects/demo-app"
mkdir -p "$P"; echo "<?php echo 1;" > "$P/index.php"; echo "APP_KEY=abc" > "$P/.env"
run_create "$P" demo-app; code=$?
[ "$code" = 0 ] && ok "create_github_repo succeeded" || bad "create_github_repo exit $code: $(cat "$T/out")"
[ "$(git -C "$HOME_REPO" remote get-url origin)" = "$HOME_ORIGIN" ] && ok "parent origin untouched" || bad "parent origin changed to $(git -C "$HOME_REPO" remote get-url origin)"
[ "$(git -C "$HOME_REPO" rev-parse HEAD)" = "$HOME_HEAD" ] && ok "parent history untouched" || bad "parent HEAD moved"
[ "$(git -C "$HOME_REPO" remote | wc -l)" = 1 ] && ok "parent has no new remotes" || bad "parent remotes: $(git -C "$HOME_REPO" remote | tr '\n' ' ')"
[ -d "$P/.git" ] && ok "project got its own .git" || bad "project has no .git"
NEW="$T/remotes/TestOrg_demo-app.git"
files="$(git -C "$NEW" ls-tree -r --name-only HEAD 2>/dev/null | sort | tr '\n' ' ')"
[ "$files" = ".gitignore index.php " ] && ok "only the project's files were pushed" || bad "pushed files: '$files'"
git -C "$NEW" log --all --format=%s 2>/dev/null | grep -q "home backup" && bad "home history reached the new repo" || ok "no parent history in the new repo"
grep -qxF .env "$P/.gitignore" && ok ".env is gitignored" || bad ".env not in .gitignore"
[ "$(git -C "$P" remote get-url origin)" = "$NEW" ] && ok "project origin is the new repo" || bad "project origin: $(git -C "$P" remote get-url origin 2>&1)"

echo "Wrong directory:"
: > "$T/gh-created"
run_create "$HOME_REPO/projects" demo-two; code=$?
[ "$code" != 0 ] && ok "refused when not in the project directory (exit $code)" || bad "did not refuse"
[ ! -s "$T/gh-created" ] && ok "nothing created on GitHub" || bad "created: $(cat "$T/gh-created")"
[ "$(git -C "$HOME_REPO" remote get-url origin)" = "$HOME_ORIGIN" ] && ok "parent origin still untouched" || bad "parent origin changed"

echo "No parent repo:"
Q="$T/plain/solo-app"; mkdir -p "$Q"; echo "print(1)" > "$Q/main.py"
run_create "$Q" solo-app; code=$?
[ "$code" = 0 ] && [ "$(git -C "$T/remotes/TestOrg_solo-app.git" ls-tree -r --name-only HEAD | sort | tr '\n' ' ')" = ".gitignore main.py " ] \
    && ok "plain project is created and pushed" || bad "plain project: exit $code, $(cat "$T/out")"

echo "Project that already has its own repo inside a parent repo:"
R="$HOME_REPO/projects/has-repo"; mkdir -p "$R"; echo x > "$R/a.txt"
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -qm "own history"
run_create "$R" has-repo; code=$?
[ "$code" = 0 ] && git -C "$T/remotes/TestOrg_has-repo.git" log --format=%s | grep -q "own history" \
    && ok "existing project repo pushed with its own history" || bad "has-repo: exit $code, $(cat "$T/out")"
[ "$(git -C "$HOME_REPO" rev-parse HEAD)" = "$HOME_HEAD" ] && [ "$(git -C "$HOME_REPO" remote get-url origin)" = "$HOME_ORIGIN" ] \
    && ok "parent still untouched" || bad "parent changed"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
