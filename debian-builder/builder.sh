#!/bin/sh
#

#
# Tarantool Debian package builder.
#
builder_prompt=`basename $0`
builder_cmd=""
builder_root=`pwd`
builder_base_name="base"
builder_base="${builder_root}/${builder_base_name}"
builder_build_name="build"
builder_repository="/home/buildbot/repository"
builder_version=""

instance_git_head=""
instance_conf_name="instance.conf"
instance_conf=""
instance_build_name="build"
instance_build=""
instance_last_name="last_head"
instance_last_version_name="last_version"
instance_status_name="status"
instance_status="${instance_status_name}"
instance_status_import_name="status_import"
instance_log_name="log"
instance_log=""
instance_log_import_name="log_import"
instance_log_import=""
instance_result_name="result"
instance_result=""
instance_root=""

# utility routines
#
log() {
	echo "$builder_prompt: $*"
}

status() {
	# write to log
	log "$*"
	# updating status files
	echo "$*" > $instance_status
}

error() {
	status "FAILED $*"
	exit 1
}

run() {
	eval "$*"
	[ $? -gt 0 ] && error "$*"
}

usage() {
	log "Tarantool Debian package builder."
	log "usage: ${builder_prompt} <command> <directory>"
	log "   build   -- build packages"
	log "   import  -- import packages to the local repository"
	log "   clean   -- clean builder files"
	log "   status  -- show current status"
	exit 0
}

# instance configuration
#
configure() {
	# checking instance config file existence
	conf_errmsg="failed to access instance config '${instance_conf}'"
	[ ! -f $instance_conf ] && error $conf_errmsg

	# loading instance config file
	. ${instance_conf}
	[ $? -gt 0 ] && error $conf_errmsg

	# checking required instance variables
	[ -z $instance_arch ] && error "instance_arch is not set"
	[ -z $instance_distribution ] && error "instance_distribuiton is not set"
	[ -z $instance_base_file ] && error "instance_base_file is not set"
	[ -z $instance_tag ] && error "instance_tag is not set"
	[ -z $instance_sign_id ] && error "instance_sign_id is not set"
	[ -z $instance_sign_email ] && error "instance_sign_email is not set"
	[ -z $instance_tarantool_git ] && error "instance_tarantool_git is not set"
	[ -z $instance_tarantool_branch ] && error "instance_tarantool_branch is not set"
	[ -z $instance_repository ] && error "instance_repository is not set"

	# updating instance base var
	instance_base="${builder_base}/${instance_base_file}"

	# checking base file 
	if [ ! -f "${instance_base}" ]; then
		error "failed to access base file '${instance_base}'"
	fi
}

# checking previous build and version 
#
check() {
	# updating status
	status "checking ${instance_root}"

	cd ${instance_root}

	[ ! -f ${instance_last_name} ] && return 0
	[ ! -f ${instance_last_version_name} ] && return 0

	instance_last_head=`cat ${instance_last_name}`
	[ $? -gt 0 ] && error "failed to read last_head file"

	instance_last_version=`cat ${instance_last_version_name}`
	[ $? -gt 0 ] && error "failed to read last_version file"

	[ ! -d ${instance_build} ] && return 0
	cd "${instance_build}"

	instance_last_build="tarantool-${instance_last_version}"
	[ ! -d ${instance_last_build} ] && return 0

	cd "${instance_last_build}"
	run "git pull"

	instance_git_head=`git describe HEAD~1`
	if [ "${instance_git_head}" = "${instance_last_head}" ]; then
		log "git version $instance_last_head is equal to last build, skipping."
		status "SKIPPED ($instance_last_head)"
		exit 0
	fi
}

# building functions
#
prepare() {
	# updating status
	status "preparing ${instance_root}"

	cd ${instance_root}

	# recreating build directory
	run "rm -rf ${instance_build} ${instance_result}"
	run "mkdir ${instance_build} ${instance_result}"

	# clonning tarantool repository
	run "git clone ${instance_tarantool_git} ${instance_build}/tarantool"
	cd "${instance_build}/tarantool"

	# checking out the specified branch
	run "git checkout ${instance_tarantool_branch}"

	# getting current git HEAD
	instance_git_head=`git describe HEAD`

	# updating version
	builder_version=`echo ${instance_git_head} | sed -e s/-/+/g`
	builder_time=`date +%Y%m%d+%H%M`
	builder_version="${builder_version}+${builder_time}"

	# updating debian changelog
	build_msg="automatic build of ${instance_git_head}"
	export NAME="$instance_sign_id"
	export DEBEMAIL="$instance_sign_email"
	run "dch -D ${instance_tag} -b --force-distribution -v '${builder_version}-1' '${build_msg}'"
	run "git commit -a -m '${build_msg}'"

	# preparing directory to work with dpkg-source
	build_prepared_dir="tarantool-${builder_version}"
	cd ..
	run "mv tarantool ${build_prepared_dir}"

	# creating .orig file
	run "tar --exclude=.git --exclude=debian \
	-czf tarantool_${builder_version}.orig.tar.gz ${build_prepared_dir}"

	# producing .dsc file
	run "dpkg-source -b ${build_prepared_dir}"
}

# pbuilder base image file update
#
update() {
	# updating status
	status "updating base ${instance_git_head}"

	# invoking pbuilder
	update_cmd="pbuilder --update"
	update_cmd="${update_cmd} --basetgz ${instance_base}"
	update_cmd="${update_cmd} --distribution ${instance_distribution}"
	update_cmd="${update_cmd} --architecture ${instance_arch}"
	update_cmd="${update_cmd} --autocleanaptcache"
	run "sudo $update_cmd"
}

# package builder routine
#
build() {
	# updating status
	status "building ${instance_git_head}"

	# invoking pbuilder
	build_cmd="pbuilder --build"
	build_cmd="${build_cmd} --basetgz ${instance_base}"
	build_cmd="${build_cmd} --buildresult ${instance_result}"
	build_cmd="${build_cmd} --autocleanaptcache"
	build_cmd="${build_cmd} tarantool_${builder_version}-1.dsc"
	run "sudo $build_cmd"
}

# signing package files
#
sign() {
	# updating status
	status "signing ${instance_git_head}"
	# signing changes file
	cd ${instance_result}
	build_changes="tarantool_${builder_version}-1_${instance_arch}.changes"
	run "debsign -m${instance_sign_id} ${build_changes}"
}

# mark completion
#
complete() {
	# updating last git build version
	run "echo -n $instance_git_head > ../${instance_last_name}"

	# updating last build version
	run "echo -n $builder_version > ../${instance_last_version_name}"

	# updating status
	status "OK ${instance_git_head}"
}

# import build packages to the repository
#
import() {
	# updating status
	status "importing ${instance_root}"

	cd ${instance_root}

	[ ! -f ${instance_last_version_name} ] && return 0

	instance_last_version=`cat ${instance_last_version_name}`
	[ $? -gt 0 ] && error "failed to read last_version file"

	changes="tarantool_${instance_last_version}-1_${instance_arch}.changes"

	# adding packages to the repository 
	rep_cmd="reprepro -b ${instance_repository}"
	rep_cmd="${rep_cmd} include ${instance_tag} ${instance_result}/${changes}"
	run "${rep_cmd}"

	# updating status
	status "OK"
}

# cleanup instance files
#
clean() {
	run "rm -f ${instance_log}"
	run "rm -f ${instance_log_import}"
	run "rm -f ${instance_status}"
	run "rm -f ${instance_root}/${instance_status_import_name}"
	run "rm -f ${instance_root}/${instance_last_name}"
	run "rm -f ${instance_root}/${instance_last_version_name}"
	run "rm -fr ${instance_build}"
	run "rm -fr ${instance_result}"
}

[ ! $# -eq 2 ] && usage
builder_cmd="$1"

# configuring pathes
instance_root="${builder_root}/${builder_build_name}/$2"
instance_conf="${instance_root}/${instance_conf_name}"
instance_build="${instance_root}/${instance_build_name}"
instance_result="${instance_root}/${instance_result_name}"
instance_status="${instance_root}/${instance_status_name}"
instance_log="${instance_root}/${instance_log_name}"
instance_log_import="${instance_root}/${instance_log_import_name}"

# checking instance dir
if [ ! -d $instance_root ]; then
	error "failed to access instance '${instance_root}'"
fi
# checking base directory
[ ! -d $builder_base ] && error "base directory not found"

# reading instance config file
configure

# processing command
case $builder_cmd in
  build)
#	exec 1>  "${instance_log}"
#	exec 2>> "${instance_log}"
#	check
	prepare
	update
	build
	sign
	complete
  ;;
  import)
	instance_status="${instance_root}/${instance_status_import_name}"
#	exec 1>  "${instance_log_import}"
#	exec 2>> "${instance_log_import}"
	import
  ;;
  status)
	status="unknown"
	if [ -f ${instance_status} ]; then
		status=`cat ${instance_status}`
		[ $? -gt 0 ] && error "failed to read instance status"
	fi
	status_import="unknown"
	status_import_file="${instance_root}/${instance_status_import_name}"
	if [ -f ${status_import_file} ]; then
		status_import=`cat ${status_import_file}`
		[ $? -gt 0 ] && error "failed to read instance import status"
	fi
	echo "\033[32;1m${2}\033[0m"
	echo "   build: ${status}"
	echo "  import: ${status_import}"
  ;;
  clean)
	clean
  ;;
  *) usage
  ;;
esac
