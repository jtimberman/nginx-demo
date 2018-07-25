pkg_name=nginx-demo
pkg_origin=chefops
pkg_version="0.2.0"
pkg_maintainer="Chef Operations <ops@chef.io>"
pkg_deps=(core/nginx core/curl)
pkg_svc_user="root"

do_build() {
  return 0
}

do_install() {
  return 0
}
