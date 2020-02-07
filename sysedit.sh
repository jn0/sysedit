#!/bin/bash

exe="$0"

DEFAULT_EDITOR=vi
CONFIG=~/.sysedit.conf
THE_REPO=~/.se
FS=$(hostname -s)

create=no
remove=no

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

if [ -f "$CONFIG" ] && [ -r "$CONFIG" ]; then
	repo=$(grep '^[ \t]*repo=' "$CONFIG") || error $? "No 'repo=' in '$CONFIG'."
	repo=$(eval echo -n $(echo -n $repo | cut -d= -f2-))
	[ -d "$repo/." ] || error $? "No directory '$repo'."
	[ -f "$repo/.git/config" ] || error $? "Not a GIT repo '$repo'."
	THE_REPO="$repo"
	unset repo
fi

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

create_file() {
	local fn="$1"
	local dn=$(dirname "$fn")
	local sudo=''
	[ -d "$dn/." ] || {
		mkdir -pv "$dn" || {
			sudo=sudo; sudo mkdir -pv "$dn" ||
				error $? "Cannot create '$dn/'"
		}
	}
	[ -z "$sudo" -a ! -w "$dn/." ] && sudo=sudo
	$sudo touch "$fn"
}

empty_dir() {
	local dn="$1"
	[ -d "$dn/." ] || return 0
	pushd "$dn" || error $? "Cannot pushd '$dn'."
	local files="$(echo -n *)"
	popd
	[ "$files" = '*' ] && true || false
}

try_remove() {
	local f="$1"
	local d="$(dirname "$f")"
	[ -w "$d/." ] || return 1
	rm -f "$f" # >/dev/null 2>&1
	return $?
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
			mkdir -pv "$FS/" && touch "$FS/.init" && git add "$FS/.init" &&
			git commit -m genesis &&
			git checkout -b $FS &&
			mkdir -pv "$FS/" && LANG=C date > "$FS/.init" && git add "$FS/.init" &&
			git commit -m "genesis of $FS" &&
		:)
	fi
}

repo_local() {
	local f="$1"
	echo -n "$FS/${f:1}"
}

repo_file() {
	echo -n "$THE_REPO/$(repo_local "$1")"
}

repo_is_remote() {
	grep -sq '\[remote ' "$THE_REPO/.git/config"
}

update_remote() {
	repo_is_remote && git push # origin "$FS"
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

clear_dirs() {
	local dn="$1" stop="$THE_REPO/$FS" xn=''
	[ "${dn:0:${#stop}}" = "$stop" ] || error 1 "Cannot clear '$dn' (not in '$stop')."
	while [ -n "$dn" ] && [ "$dn" != "$stop" ]; do
		if empty_dir "$dn"; then
			[ -d "$dn/." ] && rmdir "$dn"
			[ -e "$dn" ] && error 1 "Cannot remove '$dn'."
			dn="$(dirname "$dn")"
		else
			break
		fi
	done
}

untrack_file() {
	local f="$1"
	local l="$(repo_local "$f")"
	local d="$(dirname "$f")"; d="${d:1}"

	test -d "$THE_REPO/$FS/$d/." || return
	(cd "$THE_REPO" && { git rm "$l" || error $? "Cannot git rm '$l'."; })
	clear_dirs "$(dirname `repo_file "$f"`)"

	(cd "$THE_REPO/$FS" && git commit -am "remove $l") ||
		error $? "git commit 'remove $l' error"
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
	local -a files=( "$@" )
	for ((i=0; i<${#files[@]}; i++)); do
		files[$i]=$(repo_local ${files[$i]})
	done
	(cd "$THE_REPO/$FS" && git commit -am "changed ${files[*]}") ||
		error $? "git commit '${files[*]}' error"
}

set_remote() {
	local arg="$1" # --remote=<URL>
	case "$arg" in
	--remote=*)	arg="${arg:9}";;
	*)		error 1 "Wrong format '$arg'";;
	esac
	pushd "$THE_REPO" || error $? "Cannot chdir($THE_REPO)."
set -x
	git remote add origin "$arg"
	git checkout "$FS"
	git fetch
	git branch --set-upstream-to=origin/"$FS" "$FS"
	git pull -r origin "$FS"

	while [ -n "$(git status --porcelain)" ]; do
		git rebase --skip
	done

	LANG=C date > "$FS/.init"
	git commit -m "update '$FS/.init'" "$FS/.init"

	# git push --set-upstream origin "$FS"
	# git push origin "$FS"
	git push # origin "$FS"
set +x
	popd
}

################################################################################

do_help() {
cat <<-EOT
	$(basename $exe) --list | --ls	# show some info about backend
	$(basename $exe) --remote=<GIT-URL>	# setup backend to track upstream
	$(basename $exe) <filespec> ...	# work with files

	<filespec> ::= [ <option> ] <filename> ...
	<option> ::= '--create' | '--remove' | '--rm'
	<filename> ::= mere local file name

	ALL filenames after --create will be created.
	ALL filenames after --remove will be removed.

	It's quite possible to enable BOTH options to
	do some tricks...
EOT
	exit 0
}

do_list() {
	pushd "$THE_REPO" && git status && git log --oneline -n10 && ls -ltraF && popd
	exit $?
}

################################################################################

init_repo

declare -a args=( "$@" )
declare -a files=()
declare -a flags=()

declare -i j=0
declare -i k=0
for ((i=0; i<${#args[@]}; i++)); do
	a="${args[$i]}"
	f="$(realpath -qe -- "$a")"
	if [ -z "$f" ]; then # no file!
		if [ "${a:0:1}" = '-' ]; then
			flags[$k]="$a"
			let k+=1
			case "$a" in
			--help|-h)	do_help;;
			--list|--ls)	do_list;;
			--create)	create=yes;;
			--remove|--rm)	remove=yes;;
			--remote=*)	set_remote "$a";;
			*)		error 1 "Unknow flag '$a'.";;
			esac
			continue
		fi
		[ "$create" != 'yes' ] &&
			error 1 "There is no file '$a'. Use '--create $a' if needed."
		create_file "$(realpath -qm -- "$a")"
		f="$(realpath -qe -- "$a")"
		[ -z "$f" ] && error 1 "Cannot create '$f' for '$a'."
	fi
	if [ "$remove" = 'yes' ]; then
		try_remove "$f" || { sudo rm -iv "$f" || error $? "Cannot remove '$f'."; }
		file_is_tracked "$f" && untrack_file "$f"
		continue
	fi
	files[$j]="$f"
	let j+=1
	unset -v a f d
done
unset -v i j k

(( ${#files[@]} == 0 )) && { cd $THE_REPO && git log --oneline -n 40; exit; }

for f in "${files[@]}"; do
	file_is_tracked "$f" || track_file "$f"
done
unset f

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
