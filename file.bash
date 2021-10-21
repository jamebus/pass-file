# shellcheck shell=bash
# shellcheck enable=quote-safe-variables

print_usage() {
	echo "Usage: $PROGRAM file action pass-name [path]"
	echo 'Actions:'
	echo '  store|add|attach: add new file to password store'
	echo '  retrieve|show|cat: retrieve file from password store and print it to stdout'
	echo '  edit|vi: edit a file (warning: unencrypted file will be opened with $EDITOR)'
	exit
}

cmd_store() {
	local path="$1"
	local file="$2"

	if [[ ${path: -4} != '.b64' ]]; then
		path="${path}.b64"
	fi

	local passfile="${PREFIX}/${path}.gpg"

	cd "$OLDPWD" || return 1 # fix for relative paths

	check_sneaky_paths "$1"
	set_git "$passfile"

	if [[ -z $path || -z $file ]]; then
		print_usage
	elif [[ ! -f $file ]]; then
		die "Error: $file does not exist."
	fi

	if [[ -f $passfile ]] && [[ "$PASS_FILE_FORCE_OVERWRITE" != 'true' ]]; then
		read -r -p 'A file with this name already exists in the store. Do you want to overwrite it? [y/N] ' response
		if [[ $response != [yY] ]]; then
			exit
		fi
	fi

	mkdir -p "$(dirname "$passfile")"

	set_gpg_recipients "$(dirname "$path")"

	base64 "$file" | $GPG -e "${GPG_RECIPIENT_ARGS[@]}" -o "$passfile" "${GPG_OPTS[@]}"

	git_add_file "$passfile" "Store arbitary file for $path to store."
}

cmd_retrieve() {
	local path="$1"

	if [[ ${path: -4} != '.b64' ]]; then
		path="${path}.b64"
	fi

	local passfile="${PREFIX}/${path}.gpg"

	if [[ -z $path ]]; then
		print_usage
	else
		check_sneaky_paths "$path"
		$GPG -d "${GPG_OPTS[@]}" "$passfile" | base64 -d || exit $?
	fi
}

cmd_edit() {
	local path="$1"

	if [[ -z $path ]]; then
		print_usage
	fi

	if [[ ${path: -4} != '.b64' ]]; then
		path="${path}.b64"
	fi

	local passfile="${PREFIX}/${path}.gpg"

	if [[ -z $EDITOR ]]; then
		echo "\$EDITOR not set, don't know how to open file."
		exit 1
	else
		local tmpfile
		tmpfile=$(mktemp)

		if [[ -f $passfile ]]; then
			cmd_retrieve "$path" > "$tmpfile"
			if [[ $? -ne 0 ]]; then
				rm "$tmpfile"
				exit 1
			fi
		else
			echo 'File does not exist, creating new file...'
			sleep 3
		fi

		$EDITOR "$tmpfile"
		if [[ $? -ne 0 ]]; then
			rm "$tmpfile"
			exit 1
		fi

		PASS_FILE_FORCE_OVERWRITE='true' cmd_store "$path" "$tmpfile"
		if [[ $? -ne 0 ]]; then
			echo 'Could not save file, please check yourself.'
			echo "Tempfile: $tmpfile"
			exit 1
		fi

		rm "$tmpfile"
	fi
}

case $1 in
store | add | attach)
	shift && cmd_store "$@"
	;;
retrieve | show | cat)
	shift && cmd_retrieve "$@"
	;;
edit | vi)
	shift && cmd_edit "$@"
	;;
*)
	print_usage
	;;
esac
