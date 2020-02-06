#!/bin/bash

DEFAULT_EDITOR=vi
THE_REPO=~/.se
FS=$(hostname -s)

say() {
	echo "$@" >&2
}

error() {
	local -i rc=$1
	shift
	say "$*"
	exit $rc
}

################################################################################

has_executable() {
	local cmd="$1"
	local bin="$(type -p "$cmd")"
	if [ -e "$bin" ] && [ -x "$bin" ]; then true; else false; fi
}

env_bin() {
	local value="$1"
	if [ -n "$value" ]; then has_executable "$value"; else false; fi
}

run_if_env_bin() {
	local cmd="$1"
	local fn sudo
	shift
	for fn; do [ -w "$fn" ] || sudo=sudo; done
	env_bin "$cmd" && $sudo "$cmd" "$@" || false
}

edit() {
	local fn sudo
	for fn; do [ -w "$fn" ] || sudo=sudo; done
	run_if_env_bin "$VISUAL" "$@" ||
	run_if_env_bin "$EDITOR" "$@" ||
	run_if_env_bin "$GIT_EDITOR" "$@" ||
	$sudo "$DEFAULT_EDITOR" "$@"
}

################################################################################

init_repo() {
	if [ -d "$THE_REPO/.git/." ]; then
		:
	else
		mkdir -pv "$THE_REPO/"
		(cd "$THE_REPO" &&
			touch README &&
			git init &&
			git add README &&
			git commit -m genesis &&
			git checkout -b $FS &&
			mkdir -pv "$FS/" &&
			touch "$FS/.init" &&
			git add "$FS/.init" &&
			git commit -m "genesis of $FS" &&
		:)
	fi
}

repo_file() {
	local f="$1"
	echo -n "$THE_REPO/$FS/${f:1}"
}

repo_is_remote() {
	grep -sq '\[remote ' "$THE_REPO/.git/config"
}

update_remote() {
	repo_is_remote && git push origin "$FS"
}

file_is_tracked() {
	test -f "$(repo_file "$1")"
}

track_file() {
	local f="$1"
	local r="$(repo_file "$f")"
	local d="$(dirname "$f")"; d="${d:1}"

	mkdir -pv "$THE_REPO/$FS/$d"
	cp -v "$f" "$r" || error $? "Cannot copy '$f' to '$r'."

	local a="$(cd $THE_REPO && realpath --relative-to="$FS" "$r")"
	(cd "$THE_REPO/$FS" && git checkout "$FS") || error $? "git checkout '$FS' error"
	(cd "$THE_REPO/$FS" && git add "$a") || error $? "git add '$a' error"
	(cd "$THE_REPO/$FS" && git commit -am "add $a") || error $? "git commit '$a' error"
	update_remote
}

file_is_changed() {
	local f="$1"
	local r="$(repo_file "$f")"
	if cmp -s "$f" "$r"; then say "intact"; false; else say "changed"; true; fi
}

update_file() {
	local f="$1"
	local r="$(repo_file "$f")"
	cp -v "$f" "$r" || error $? "Cannot copy '$f' to '$r'."
	local a="$(cd $THE_REPO && realpath --relative-to="$FS" "$r")"
	(cd "$THE_REPO/$FS" && git add "$a") || error $? "git add '$a' error"
}

commit_changes() {
	local files="$*"
	(cd "$THE_REPO/$FS" && git commit -am "changed $files") || error $? "git commit '$files' error"
}

################################################################################

init_repo

declare -a files=( "$@" )

(( ${#files[@]} == 0 )) && { cd $THE_REPO && git log --oneline -n 40; exit; }

for ((i=0; i<${#files[@]}; i++)); do
	f="$(realpath -e "${files[$i]}")"
	files[$i]="$f"
	file_is_tracked "$f" || track_file "$f"
	unset f
done

edit "${files[@]}"
typeset -i changed=0
declare -a updated=()

for ((i=0; i<${#files[@]}; i++)); do
	f="${files[$i]}"
	file_is_changed "$f" && { updated[$changed]="$f"; let changed+=1; update_file "$f"; }
	unset f
done
if (( changed > 0 )); then
	commit_changes "${updated[@]}" && update_remote
fi

# EOF #
