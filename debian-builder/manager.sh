#!/bin/sh

#
# Tarantool Debian package builder manager.
#
manager_prompt=`basename $0`
manager_cmd=""
manager_root=`pwd`
manager_build_name="build"
manager_build="${manager_root}/${manager_build_name}"
manager_update_debian_site="debian"
manager_update_debian_stable_site="debian_stable"
manager_update_ubuntu_site="ubuntu"
manager_update_ubuntu_stable_site="ubuntu_stable"

builder="./builder.sh"

log() {
	echo "$manager_prompt: $*"
}

usage() {
	log "Tarantool Debian package builder manager."
	log "usage: $0 <build|import|clean|status|sync|process>"
}

foreach_do() {
	for build_name in `ls -1 ${manager_build}`; do
		${builder} ${1} ${build_name}
	done
}

build() {
	for build_name in `ls -1 ${manager_build}`; do
		log "building ${build_name}"
		${builder} build ${build_name}
		if [ $? -gt 0 ]; then
			log "failed (see ${manager_build}/${build_name}/log for details)"
		fi
		${builder} status ${build_name}
	done
}

sync() {
	sitecopy -u ${manager_update_debian_site}
	sitecopy -u ${manager_update_debian_stable_site}
	sitecopy -u ${manager_update_ubuntu_site}
	sitecopy -u ${manager_update_ubuntu_stable_site}
}

case $1 in
  status) foreach_do status
  ;;
  clean) foreach_do clean
  ;;
  import) foreach_do import
  ;;
  build) build
  ;;
  sync) sync
  ;;
  process)
	build
	foreach_do import
	sync
	sudo pbuilder --clean
  ;;
  *) usage
  ;;
esac
