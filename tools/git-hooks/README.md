# Git hooks for the fork

These hooks check the fork's commit rules. They block a commit or a push
that has any of these:

- An upstream reference: `#` followed by 4 to 6 digits, `roc-lang/roc#N`, or
  a github.com/roc-lang/roc issue or PR link. This applies to commit messages
  and to the lines a commit adds. Write upstream numbers without `#` in
  files, and leave them out of commit messages. An ARM immediate after a
  register (`r11, #4080`) is fine, and so are fork PR numbers like `#9`.
- A Co-Authored-By or Claude-Session line, or a claude.ai session link.
- The words "personal" and "note" side by side.
- An unsigned commit. This is checked at push time.

Text that comes from upstream is never checked: commits upstream already
has (anything reachable from an `upstream/*` remote branch), and lines a
merge takes unchanged from the merged branch.

| Hook | What it checks |
|---|---|
| `pre-commit` | the staged lines |
| `commit-msg` | the message |
| `pre-push` | every commit being pushed: message, added lines, signature |

`pre-push` also covers commits made with `git commit-tree`, which skips the
other two hooks. The `notes` branch is pushed that way.

## Install

Hooks live in the shared `.git`, so this covers every worktree. Copy this
folder to `.git/verify-tools/git-hooks/` and link the hooks:

```sh
mkdir -p .git/verify-tools/git-hooks
cp .workspaces/notes/tools/git-hooks/* .git/verify-tools/git-hooks/
chmod +x .git/verify-tools/git-hooks/{fork_rules.py,pre-commit,commit-msg,pre-push}
for h in pre-commit commit-msg pre-push; do
  ln -sf ../verify-tools/git-hooks/$h .git/hooks/$h
done
```

The `upstream` remote must be fetched, or every upstream commit in a merge
counts as ours.

## Test it

```sh
printf 'Filed as %s12345\n' "#" > /tmp/msg.txt
python3 .git/verify-tools/git-hooks/fork_rules.py msg /tmp/msg.txt
```

That prints one problem and exits with 1.
