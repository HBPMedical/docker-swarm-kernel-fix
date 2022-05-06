#!/usr/bin/env bash

version="5.4.0-104"

SEARCH_CMD="apt-cache search"
INSTALL_CMD="apt-get --yes --no-install-recommends --allow-change-held-packages install"
UNINSTALL_CMD="apt-get --yes --purge remove"

export DEBIAN_FRONTEND="noninteractive"
result=0

_check_version() {
	if [[ "${version}" != "" ]]; then
		if [[ "$(echo ${version} | grep "[0-9]$")" != "" ]]; then
			version="${version}-generic"
		fi
	fi
}

_get_full_version() {
	echo "${version}"
}

_get_short_version() {
	local version=$(_get_full_version)
	if [[ "$(echo ${version} | grep "\-generic$")" != "" ]]; then
		version=$(echo ${version} | rev | cut -d'-' -f2- | rev)
	fi

	echo "${version}"
}

_get_wanted() {
	local packages=()
	local candidate

	for candidate in $(echo "image modules headers"); do
		packages+=("linux-${candidate}-$(_get_full_version)")
		if [[ "${candidate}" = "headers" ]]; then
			packages+=("linux-${candidate}-$(_get_short_version)")
		fi
	done

	if [[ ${#packages} -gt 0 ]]; then
		echo "${packages[@]}"
	fi
}

_get_wanted_limited() {
	local packages=()
	local candidate

	for candidate in $(_get_wanted); do
		if [[ "${candidate}" != "linux-headers-$(_get_full_version)" && "${candidate}" != "linux-headers-$(_get_short_version)" ]]; then
			packages+=("${candidate}")
		fi
	done

	if [[ ${#packages} -gt 0 ]]; then
		echo "${packages[@]}"
	fi
}

_get_installed_wanted() {
	local packages=()
	local candidate
	local tmp_packages
	local package

	for candidate in $(_get_wanted); do
		while IFS=$'\n' read -r package; do
			if [[ "${package}" != "" ]]; then
				packages+=("${package}")
			fi
		done <<< $(dpkg --list | grep "^[hi]i[ ]*${candidate}[ ]" | awk '{print $2}')
	done

	if [[ ${#packages} -gt 0 ]]; then
		echo "${packages[@]}"
	fi
}

_get_avail() {
	local packages=()
	local candidate
	local tmp_packages
	local package

	local installed_wanted=$(_get_installed_wanted)
	for candidate in $(_get_wanted); do
		while IFS=$'\n' read -r package; do
			if [[ "${package}" != "" && "$(echo "${installed_wanted}" | grep -w "${package}")" = "" ]]; then
				packages+=("${package}")
			fi
		done <<< $(${SEARCH_CMD} ${candidate} | grep "^${candidate}[ ]" | awk '{print $1}')
	done

	if [[ ${#packages} -gt 0 ]]; then
		echo "${packages[@]}"
	fi
}

_get_installed_unwanted() {
	local result=0

	local packages=()
	local candidate
	local tmp_packages
	local package

	for candidate in $(echo "image modules headers"); do
		while IFS=$'\n' read -r package; do
			if [[ "${package}" != "" ]]; then
				if [[ "${package}" != "linux-image-$(uname -r)" && "${package}" != "linux-modules-$(uname -r)" ]]; then
					packages+=("${package}")
				else
					echo "As you have to remove the kernel/modules which is currently running on this machine, the package <${package}> has to be ommitted from the current removal operation! The machine has to run on the targetted $(_get_full_version) kernel prior to remove the current $(uname -r) version! This script will have to run again after rebooting on $(_get_full_version) kernel!" >/dev/stderr
					result=1
				fi
			fi
		done <<< $(dpkg --list | grep "^.*[ ]*linux-${candidate}-" | grep -v "linux-${candidate}-$(_get_short_version)" | awk '{print $2}')
	done

	if [[ ${#packages} -gt 0 ]]; then
		eval 'installed_unwanted="${packages[@]}"'
	fi

	return $result
}

_get_held_wanted() {
	local packages=()
	local candidate
	local package

	for package in $(_get_wanted_limited); do
		if [[ "$(apt-mark showhold ${package})" != "" ]]; then
			packages+=("${package}")
		fi
	done

	if [[ ${#packages} -gt 0 ]]; then
		echo "${packages[@]}"
	fi
}

_hold_wanted() {
	local result=1

	local wanted=$(_get_wanted_limited)
	local package

	for package in $(echo "${wanted}"); do
		apt-mark hold ${package}
	done

	if [[ "$(_get_held_wanted)" = "${wanted}" ]]; then
		result=0
	fi

	return $result
}

_install() {
	local result=1

	if [[ $# -gt 0 ]]; then
		${INSTALL_CMD} $@
		result=$?
	fi

	return $result
}

_uninstall() {
	local result=1

	if [[ $# -gt 0 ]]; then
		${UNINSTALL_CMD} $@
		result=$?
	fi

	return $result
}

_get_wanted_grub_entry() {
	local foundTag=""

	local AllMenusArr=()										# All menu options.
	# Default for hide duplicate and triplicate options with (upstart) and (recovery mode)?
	local HideUpstartRecovery=false
	local SkippedMenuEntry=false								# Don't change this value, automatically maintained
	local InSubMenu=false										# Within a line beginning with `submenu`?
	local InMenuEntry=false										# Within a line beginning with `menuentry` and ending in `{`?
	local NextMenuEntryNo=0										# Next grub internal menu entry number to assign
	# Major / Minor internal grub submenu numbers, ie `1>0`, `1>1`, `1>2`, etc.
	local ThisSubMenuMajorNo=0
	local NextSubMenuMinorNo=0
	local CurrTag=""											# Current grub internal menu number, zero based
	local CurrText=""											# Current grub menu option text, ie "Ubuntu", "Windows...", etc.
	local SubMenuList=""										# Only supports 10 submenus! Numbered 0 to 9. Future use.

	local line
	local BlackLine
	while read -r line; do
		# Example: "           }"
		BlackLine="${line//[[:blank:]]/}" 				# Remove all whitespace
		if [[ $BlackLine == "}" ]] ; then
			# Add menu option in buffer
			if [[ $SkippedMenuEntry == true ]] ; then
				NextSubMenuMinorNo=$(( $NextSubMenuMinorNo + 1 ))
				SkippedMenuEntry=false
				continue
			fi
			if [[ $InMenuEntry == true ]] ; then
				InMenuEntry=false
				if [[ $InSubMenu == true ]] ; then
					NextSubMenuMinorNo=$(( $NextSubMenuMinorNo + 1 ))
				else
					NextMenuEntryNo=$(( $NextMenuEntryNo + 1 ))
				fi
			elif [[ $InSubMenu == true ]] ; then
				InSubMenu=false
				NextMenuEntryNo=$(( $NextMenuEntryNo + 1 ))
			else
				continue								# Future error message?
			fi
			# Set maximum CurrText size to 68 characters.
			CurrText="${CurrText:0:67}"
			if [[ "$(echo $CurrText | grep "$(_get_full_version)$")" != "" ]]; then
				foundTag=$CurrTag
			fi
			AllMenusArr+=($CurrTag "$CurrText")
		fi

		# Example: "menuentry 'Ubuntu' --class ubuntu --class gnu-linux --class gnu" ...
		#          "submenu 'Advanced options for Ubuntu' $menuentry_id_option" ...
		if [[ $line == submenu* ]] ; then
			# line starts with `submenu`
			InSubMenu=true
			ThisSubMenuMajorNo=$NextMenuEntryNo
			NextSubMenuMinorNo=0
			SubMenuList=$SubMenuList$ThisSubMenuMajorNo
			CurrTag=$NextMenuEntryNo
			CurrText="${line#*\'}"
			CurrText="${CurrText%%\'*}"
			#AllMenusArr+=($CurrTag "$CurrText")			# ie "1 Advanced options for Ubuntu"
		elif [[ $line == menuentry* ]] && [[ $line == *"{"* ]] ; then
			# line starts with `menuentry` and ends with `{`
			if [[ $HideUpstartRecovery == true ]] ; then
				if [[ $line == *"(upstart)"* ]] || [[ $line == *"(recovery mode)"* ]] ; then
					SkippedMenuEntry=true
					continue
				fi
			fi
			InMenuEntry=true
			if [[ $InSubMenu == true ]] ; then
				: # In a submenu, increment minor instead of major which is "sticky" now.
				CurrTag=$ThisSubMenuMajorNo">"$NextSubMenuMinorNo
			else
				CurrTag=$NextMenuEntryNo
			fi
			CurrText="${line#*\'}"
			CurrText="${CurrText%%\'*}"
		else
			continue									# Other stuff - Ignore it.
		fi
	done < /boot/grub/grub.cfg

	echo "$foundTag"
}

_check_version
if [[ "$(_get_full_version)" != "" ]]; then
	wanted=$(_get_wanted)
	wanted_limited=$(_get_wanted_limited)
	installed_wanted=$(_get_installed_wanted)
	installed_unwanted=""
	_get_installed_unwanted 2>/dev/null
	unwanted_ret=$?
	held_wanted=$(_get_held_wanted)

	if [[ "${installed_wanted}" != "${wanted}" || "${installed_unwanted}" != "" || $unwanted_ret -ne 0 || "${held_wanted}" != "${wanted}" ]]; then
		if [[ "${installed_wanted}" != "${wanted}" ]]; then
			avail=$(_get_avail)
			echo "Installing required packages..."
			_install "${avail}"
			ret=$?
			if [[ $ret -ne 0 ]]; then
				result=$ret
			fi
		fi

		if [[ "${installed_unwanted}" != "" ]]; then
			echo "Uninstalling unwanted packages..."
			_uninstall "${installed_unwanted}"
			ret=$?
			if [[ $ret -ne 0 ]]; then
				result=$ret
			fi
		fi

		if [[ "${held_wanted}" != "${wanted_limited}" ]]; then
			echo "Marking wanted packages as <hold>..."
			_hold_wanted
			ret=$?
			if [[ $ret -ne 0 ]]; then
				result=$ret
			fi
		fi

		installed_wanted=$(_get_installed_wanted)
		installed_unwanted=""
		_get_installed_unwanted
		held_wanted=$(_get_held_wanted)

		if [[ "${installed_wanted}" = "${wanted}" && "${installed_unwanted}" = "" && $unwanted_ret -eq 0 && "${held_wanted}" = "${wanted_limited}" ]]; then
			echo "System OK"
		else
			echo "There was an error during the full process!" >/dev/stderr
			if [[ "$(echo "${installed_wanted}" | grep "linux-image-$(_get_full_version)")" != "" && "$(uname -r)" != "$(_get_full_version)" ]]; then
				wanted_grub_entry=$(_get_wanted_grub_entry)
				if [[ "${wanted_grub_entry}" != "" ]]; then
					echo "One of the reasons may also be that we're not currently running on the targetted <$(_get_full_version)> kernel!"
					echo "As this wanted kernel is installed, I'll mark it ('${wanted_grub_entry}' Grub menu entry) to be booted on the next reboot."
					grub-reboot "${wanted_grub_entry}"
				fi
			fi
			result=1
		fi
	fi
fi

exit $result
