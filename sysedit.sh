#!/bin/bash

exe=$(realpath -e "$0")

on_err() {
	echo SCRIPT ERROR
} >/dev/tty
trap on_err ERR
set -e

declare -a required_packages=(
	dpkg		# for dpkg, he-he.
	coreutils	# for date, touch, etc...
	mime-support	# for edit
	git		# for git
	sed		# for sed
	grep		# for grep
	diffutils	# for cmp
	util-linux	# for flock
)

declare -a install_packages=()
for p in "${required_packages[@]}"; do
	if dpkg -l "$p" >/dev/null 2>&1; then
		: ok
	else
		install_packages+=( "$p" )
	fi
done
if (( ${#install_packages[@]} > 0 )); then
	echo 'Please, run the'
	echo $'\t'"sudo apt install ${install_packages[*]}"
	echo 'command first!'
	exit 1
fi >&2

# BEGIN CONFIGURABLE STUFF
_se__data_d="$HOME/.local/sysedit"
_se__upstream=''
# END CONFIGURABLE STUFF

se_list_config() {
	echo '# SYSEDIT CONFIG BEGIN #'
	declare -p ${!_se__*} | cut -d' ' -f3- | cut -d_ -f4-
	echo '# SYSEDIT CONFIG END #'
}

CONFIG_D="$HOME/.config/sysedit.d"
[ -d "$CONFIG_D/." ] || { mkdir -p "$CONFIG_D" && chmod g+s,o= "$CONFIG_D"; }

CONFIG="$HOME/.config/sysedit.conf"
[ -e "$CONFIG" ] || { se_list_config | tee "$CONFIG" >/dev/null; }

for f in "$CONFIG" "$CONFIG_D"/*; do
	if [ -s "$f" -a -r "$f" ]; then
		eval $(sed -e 's/#.*$//' -e 's/^\s*//' -e 's/^/_se__/' - < "$f" | grep -v '^_se__$' | tr '\n' ';')
	fi
done

se_init() {
	local host=$(hostname -f)
	local has_dir=yes
	[ -d "$_se__data_d/." ] || has_dir=no
	umask 07
	if [ -n "$_se__upstream" ]; then
		git clone "$_se__upstream" "$_se__data_d/." || return $?
		mkdir -p "$_se__data_d/$host/."
		chmod g+s,o= "$_se__data_d/." "$_se__data_d/$host/."
		pushd "$_se__data_d/." >/dev/null
			local stamp=$(date '+%F %T %z' | tee -a "$host/.init.stamp")
			echo "## Created by '$USER' at '$host' on $stamp ##" >> README.md
			git add README.md "$host/.init.stamp"
			git commit -am "New user $USER@$host, $stamp"
		popd >/dev/null
	else
		mkdir -p "$_se__data_d/$host/."
		[ "$has_dir" = no ] && chmod g+s,o= "$_se__data_d/." "$_se__data_d/$host/."
		pushd "$_se__data_d/." >/dev/null
			git init
			local stamp=$(date '+%F %T %z' | tee "$host/.init.stamp")
			echo '.*.swp' > .gitignore
			echo '# SysEdit Git Backend Directory #' > README.md
			echo "## Created at '$host' on $stamp ##" >> README.md
			git add .gitignore README.md "$host/.init.stamp"
			git commit -am "Genesis (host $host at $stamp)"
		popd >/dev/null
	fi
}

se_log() {
	pushd "$_se__data_d/." >/dev/null
	{ cat README.md; git log --dense --color; } | less -R
	popd >/dev/null
}

_se_add() {
	local ffn="$1"
	local host=$(hostname -f)
	local dfn="$_se__data_d/$host$ffn"
	[ -e "$dfn" ] && return
	local ddn="$(dirname "$dfn")"
	[ -d "$ddn/." ] || { mkdir -p "$ddn/." && chmod g+s,o= "$ddn/."; }

	pushd "$_se__data_d" >/dev/null
		umask 07
		local r=$(git remote | wc -l)
		(( r > 0 )) && git pull -r
			cp "$ffn" "$dfn"
			git add "$host$ffn"
			git commit -m "add '$host$ffn'"
		(( r > 0 )) && git push
	popd >/dev/null
}

_se_edit() {
	local fn="$1"
	local -i rc=0
	edit --norun "$fn" >/dev/null 2>&1 || rc=$?
	(( $rc == 0 )) && { edit "$fn"; return; }
	(( $rc == 3 )) && { edit "text/plain:$fn"; return; }
	echo "Cannot edit '$fn': $rc">&2
	return $rc
}

_se_update() {
	local ffn="$1"
	local host=$(hostname -f)
	local dfn="$_se__data_d/$host$ffn"

	cmp -s "$ffn" "$dfn" && { echo "Unchanged '$ffn'.">&2; return; }

	pushd "$_se__data_d" >/dev/null
		umask 07
		local r=$(git remote | wc -l)
		(( r > 0 )) && git pull -r
			cp "$ffn" "$dfn"
			git commit -m "update '$host$ffn'" "$host$ffn"
		(( r > 0 )) && git push
	popd >/dev/null
}

declare -i _se_FD=100
se_edit() {
	local fn="$(realpath -e "$1")"

	[ -w "$fn" ] || { echo "Cannot write to '$fn'.">&2; return 1; }

	eval "exec $_se_FD<'$fn'"
	flock -n $_se_FD || { echo "!! Locked out '$fn' !!">&2; return 2; }
	let _se_FD+=1

	_se_add "$fn"
	_se_edit "$fn"
	_se_update "$fn"
}

se_status() {
	local host=$(hostname -f)
	pushd "$_se__data_d" >/dev/null
	git status --short
		pushd "$host" >/dev/null
		ls -lAR
		popd >/dev/null
	popd >/dev/null
}

se_help() {
	cat <<-EOT
	$(basename "$exe") [-h|--help] [--clone=URL] [--config] [-S|--status] [-H|--history] file...
	$(basename "$exe") --git git-command...
	$(basename "$exe") --git \\!command...
EOT
}

se_history() {
	local fn="$(realpath -e "$1")"
	local host=$(hostname -f)

	pushd "$_se__data_d" >/dev/null
	git log -- "$host$fn"
	popd >/dev/null
}

se_git() {
	local -i rc=0
	pushd "$_se__data_d" >/dev/null
	umask 07
	if [ "${1:0:1}" = '!' ]; then
		local cmd="$1"
		shift
		cmd="${cmd:1}"
		"$cmd" "$@"
	else
		git "$@"
	fi; rc=$?
	popd >/dev/null
	return $rc
}

[ -d "$_se__data_d/." ] || se_init

(( $# == 0 )) && { se_log; exit; }

declare -i fails=0
only_history=no
git_mode=no
while (( $# > 0 )); do
	arg="$1"; shift
	if [ -e "$arg" ]; then
		if [ "$only_history" = yes ]; then
			se_history "$arg"
		else
			se_edit "$arg"
		fi || let fails+=1
	else
		case "$arg" in
		-h|--help)	se_help; exit 0;;
		--git)		git_mode=yes;;
		--config)	se_list_config;;
		--status|-S)	se_status;;
		--history|-H)	only_history=yes;;
		--clone=*)	_se__upstream="${arg#*=}";;
		*)		echo "WTF '$arg'?">&2; let fails+=1;;
		esac
	fi
	if [ "$git_mode" = yes ]; then
		se_git "$@" || let fails+=1
		break
	fi
done

exit $fails

# EOF #
