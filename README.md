# sysedit
System Editor with GIT backend

It was born in Ubuntu and, hence, have some dependancies to be generalized.


The main idea is to keep copies of the system config files under git control.

When you first start the editor, it will create a git repo and store the first file you're about to edit there.
Then it will save a copy of any file it changes there.
So, enabling you to see the log and diffs.

It may use an "upstream" to push the changes into. Multi-host updates are supported.
Use `se --git remote add ...` to configure upstreaming.

Per-user config may refer a common repo, `sudo` may be needed to provide "cross-owner" usage.

The file being edited is locked (by `flock(1)`) to avoid multi-user access.
