#!/bin/bash

exe=$(realpath -e "$0")
CONFIG="$HOME/.config/pupdate.d"

[ -d "$CONFIG/." ] || mkdir -p "$CONFIG"

tmpd=$(mktemp -td pupdate.XXXXXXXXXX.logs)
cleanup() {
	rm -rf "$tmpd"
}
trap cleanup EXIT

on_error() {
	echo "ERROR IN ${BASH_SOURCE@Q} +${BASH_LINENO} @${FUNCNAME[1]}"
	sed -ne "${BASH_LINENO}p" < "${BASH_SOURCE}"
} >/dev/tty
trap on_error ERR

do_help() {
	cat <<EOT
	$(basename $exe .sh) [command [config...]]
	Commands:
		-h|--help			-- this help
		-l|-ls|--ls|--list [cf ...]	-- list configs (default for no config specified)
		-C|--create cf ...		-- create new configs
		-e|-vi|--edit cf ...		-- edit configs
		-v|-cat|--cat|--view cf ...	-- view configs
		-D|-rm|--remove|--delete cf ...	-- remove configs
		--copy|-cp cf1 cf2		-- copy <cf1> to <cf2>
		--move|-mv|--rename cf1 cf2	-- rename <cf1> to <cf2>
		--clone-to <host>...		-- clone pupdate and config to <host>s
						   if <host> looks like '@<name>', then <name> is a config name
						   and its 'hosts=' entry will be used to expand the <host>
		-R|-run|--run cf		-- run config (default for config specified)
EOT
	exit 0
}

do_list() {
	(( $# == 0 )) && ( cd "$CONFIG" && exec "$exe" -l * )
	local a f

	for a; do
		f="$CONFIG/$a"
		[ -f "$f" ] || { echo "No ${a@Q}.">&2; continue; }
		t=$(grep '^title=' "$f" | cut -d= -f2-)
		echo -n "$a" # ($f)"
		[ -n "$t" ] && echo $'\t'"- $t" || echo
	done
	exit
}

do_view() {
	local a f
	for a; do
		f="$CONFIG/$a"
		[ -f "$f" ] || { echo "No ${a@Q}.">&2; continue; }
		echo "### $a ($f)"
		cat -n "$f"
	done
	exit
}

do_create() {
	local a f
	for a; do
		f="$CONFIG/$a"
		[ -f "$f" ] && { echo "The ${a@Q} already exists.">&2; continue; }
		echo "### $a ($f)"
		cat >> "$f" <<-EOT
			title='$a farm update'
			hosts=( $a-web $a-db $a-vip $a-whois )
			# cwd=/some/directory/to/cd/to/first/of/all
			# files=( ~/files.to-copy ./to/target/system /before/the-command/will.be.ran )
			command='cd /srv/node && sudo -E ./node.sh'
			# lookup='text to lookup in command output'
			# EOF #
EOT
	done
	exit
}

do_remove() {
	local a f
	for a; do
		f="$CONFIG/$a"
		[ -f "$f" ] || { echo "No ${a@Q}.">&2; continue; }
		echo "### $a ($f)"
		rm -vi "$f"
	done
	exit
}

do_edit() {
	local a f
	for a; do
		f="$CONFIG/$a"
		[ -f "$f" ] || { echo "No ${a@Q}.">&2; continue; }
		echo "### $a ($f)"
		edit "$f"
	done
	exit
}

pager_if_term() {
	[ -t 1 ] && less -R -F || tee -ai /dev/null
}

copy_files() {
	local -a files=()
	local -a hosts=()
	local a file=yes
	local -i rc=999
	local -a pids=()

	for a; do
		[ "$a" = -- ] && { file=no; continue; }
		[ "$file" = yes ] && files+=( "$a" ) || hosts+=( "$a" )
	done
	echo "Copying ${files[@]} ..."
	for a in "${hosts[@]}"; do
		{ echo "# $(date '+%F %T %z')"; echo "# scp ${files[*]} $a:"; } > "$tmpd/$a.scp.log"
		{ scp -p "${files[@]}" "$a:"; local rx=$?; echo; echo "# RC=$rx @ $(date '+%F %T %z') #"; return $rx; } >> "$tmpd/$a.scp.log" 2>&1 &
		pids+=( $! )
		echo "[${pids[-1]}] $a - copying..." >&2
	done
	wait "${pids[@]}"; rc=$? # ; echo "!! $rc !!"

	if (( rc == 0 )); then
		echo 'Everything were copied ok.'
		# for a in "${hosts[@]}"; do cat -An "$tmpd/$a.scp.log"; done | pager_if_term
		return 0
	fi

	echo "Something went wrong! ($rc)" >&2
	for a in "${hosts[@]}"; do
		echo '##################################################'
		ls -l "$tmpd/$a.scp.log" | sed -e 's/^/# /' -
		cat "$tmpd/$a.scp.log"
		echo '##################################################'
	done | pager_if_term
	return 1
}

run_command() {
	local cmd="$1" host
	shift
	local -a pids=()
	local -i rc=999
	echo "Running \`$cmd\`..."
	for host; do
		{ echo "# $(date '+%F %T %z')"; echo "# ssh $host \"$cmd\""; } > "$tmpd/$host.ssh.log"
		{ ssh "$host" "$cmd"; local rx=$?; echo; echo "# RC=$rx @ $(date '+%F %T %z') #"; return $rx; } >> "$tmpd/$host.ssh.log" 2>&1 &
		pids+=( $! )
		echo "[${pids[-1]}] $host - starting..." >&2
	done
	wait "${pids[@]}"; rc=$? # ; echo "!! $rc !!"
	if (( rc == 0 )); then
		echo 'All commands returned zero.'
	else
		echo "Something went wrong! ($rc)" >&2
		for host; do
			echo '##################################################'
			echo "### HOST: $host"
			ls -l "$tmpd/$host.ssh.log" | sed -e 's/^/### /' -
			cat "$tmpd/$host.ssh.log"
			echo '##################################################'
		done | pager_if_term
		return 1
	fi
}

validate_output() {
	local term="$1" host fn
	[ -z "$term" ] && return 0
	local -i rc=0
	local -a failed=()
	shift
	for host; do
		fn="$tmpd/$host.ssh.log"
		grep -q "$term" "$fn" && continue
		echo "! No ${term@Q} in ${fn@Q} !">&2
		let rc+=1
		failed+=( $host )
		{ echo '##################################################'
		  echo "# LOOKUP FOR ${term@Q} FAILED FOR HOST: $host"
		  cat "$tmpd/$host.ssh.log"
		  echo '##################################################'
		} | pager_if_term
	done
	local m; IFS='|' m="${failed[*]}"; m="${m//|/\', \'}"
	(( rc > 0 )) && echo "! The log checkup failed for ${term@Q} at '${m}' !">&2
	return $rc
}

run_it() {
	local f="$1"
	local -i rc=0
	eval $(sed -e 's/#.*$//' -e 's/^/local PUPDATE_/' < "$f" | tr '\n' ';')
	declare -p ${!PUPDATE_*} | sed -e 's/^[^_]\+_/# /' - >&2
	[ -n "$PUPDATE_title" ] && echo "[$PUPDATE_title]" || echo "[[$(basename "$f")]]"
	[ -n "$PUPDATE_cwd" ] && { cd "$PUPDATE_cwd" || { echo "Cannot cd ${PUPDATE_cwd@Q} ($?)"; return 1; }; }
	[ -z "$PUPDATE_hosts" ] && { echo "No hosts">&2; return 1; }
	[ -n "$PUPDATE_files" ] && { time copy_files "${PUPDATE_files[@]}" -- "${PUPDATE_hosts[@]}" || return $?; }
	[ -n "$PUPDATE_command" ] && { time run_command "${PUPDATE_command}" "${PUPDATE_hosts[@]}" || rc=$?; }
	[ -n "$PUPDATE_lookup" ] && { validate_output "${PUPDATE_lookup}" "${PUPDATE_hosts[@]}" || let rc+=$?; }
	return $rc
}

do_run() {
	local a f
	local -i rc=0
	local -i fd=100
	echo '# Parallel Update' >&2
	declare -p ${!SSH_*} | sed -e 's/^[^_]\+_/# /' - >&2
	for a; do
		f="$CONFIG/$a"
		[ -f "$f" ] || { echo "No ${a@Q}.">&2; continue; }
		echo "### $a"

		eval "exec $fd<${f@Q}"
		flock -n $fd || { echo "!! Locked out !!">&2; continue; }

		run_it "$f"; let rc+=$?
		(( rc > 0 )) && { echo "!! Aborted ($rc) !!">&2; break; }

		let fd+=1
	done
	exit $rc
}

do_copy() {
	local src="$1" dst="$2"
	[ -e "$src" ] || src="$CONFIG/$src"
	[ -e "$src" ] || { echo "No source config.">&2; exit 1; }
	[[ "$dst" =~ / ]] || dst="$CONFIG/$dst"
	cp -vi "$src" "$dst"
	exit
}

do_move() {
	local src="$1" dst="$2"
	[ -e "$src" ] || src="$CONFIG/$src"
	[ -e "$src" ] || { echo "No source config.">&2; exit 1; }
	[[ "$dst" =~ / ]] || dst="$CONFIG/$dst"
	mv -vi "$src" "$dst"
	exit
}

do_clone_to() {
	local host
	for host; do
		echo "<$host>"
		if [ "${host:0:1}" = '@' ]; then
			local name="${host:1}"
			local file="$CONFIG/$name"
			[ -r "$file" ] || { echo "No file for ${host@Q}!">&2; return 1; }
			unset ${!PUPDATE_*}
			eval $(sed -e 's/#.*$//' -e 's/^/local PUPDATE_/' < "$file" | tr '\n' ';')
			declare -p ${!PUPDATE_*} | sed -e 's/^[^_]\+_/# /' - >&2
			[ -n "$PUPDATE_title" ] && echo "[$PUPDATE_title]" || echo "[[$name]]"
			[ -n "$PUPDATE_cwd" ] && { cd "$PUPDATE_cwd" || { echo "Cannot cd ${PUPDATE_cwd@Q} ($?)"; return 1; }; }
			[ -z "$PUPDATE_hosts" ] && { echo "No hosts">&2; return 1; }
			[ -n "$PUPDATE_files" ] || :
			[ -n "$PUPDATE_command" ] || :
			[ -n "$PUPDATE_lookup" ] || :
			do_clone_to "${PUPDATE_hosts[@]}" || return $?
			continue
		fi
		ssh "$host" "mkdir -p ~/.local/bin ~/.config/pupdate.d" || { echo "No way to setup ${host@Q}!">&2; return 1; }
		scp -p "$exe" "$host":.local/bin/ || { echo "Cannot copy binary to ${host@Q}!">&2; return 1; }
		pushd "$CONFIG" >/dev/null
			scp -p * "$host":.config/pupdate.d/ || { echo "Cannot copy configs to ${host@Q}!">&2; return 1; }
		popd >/dev/null
	done
}

(( $# == 0 )) && { do_list; exit; }

while (( $# > 0 )); do
	a="$1"
	shift
	case "$a" in
	-h|--help)		do_help "$@";;
	-l|-ls|--ls|--list)	do_list "$@";;
	-C|--create)		do_create "$@";;
	-e|-vi|--edit)		do_edit "$@";;
	-v|-cat|--cat|--view)	do_view "$@";;
	-D|-rm|--remove|--delete)	do_remove "$@";;
	--copy|-cp)		do_copy "$@";;
	--rename|--move|-mv)	do_move "$@";;
	-R|-run|--run)		do_run "$@";;
	--clone-to)		do_clone_to "$@" || exit $?; exit;;
	*)			echo "WTF ${a@Q}?">&2; exit 1;;
	esac
done

# EOF #
