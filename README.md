## GIT commit splitter

Split commits in GIT repository which contains files by specified path and branch.

Script writter in Perl. Requires `perl` and `git` installed packages. Execute script in git repository.
Put search path and optionally branch as arguments.

Result of script work is two files: `splitter.sh` and `todo_editor.sh`.
`splitter.sh` contains commands that starts interactive rebase and processes each found commit.
Rebase stops at each found commit, resets and readds its files in two commits separating original files and specified by path.
