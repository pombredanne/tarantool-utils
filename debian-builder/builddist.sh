#!/bin/sh

builddist_prompt=`basename $0`
builddist_root=`pwd`
builddist_build_name="build"
builddist_build="${builddist_root}/${builddist_build_name}"

builder="./builder.sh"

log() {
	echo "$builddist_prompt: $*"
}

#sync() {
#	sitecopy -u ${builddist_update_site}
#	sitecopy -u ${builddist_update_site_ubuntu}
#}

build() {
	build_name=$1
	log "building ${build_name}"
	${builder} build ${build_name}
	if [ $? -gt 0 ]; then
		log "failed (see ${builddist_build}/${build_name}/log for details)"
	fi
	${builder} import ${build_name}
}

build $1
