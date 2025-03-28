cmake_minimum_required(VERSION 3.20)
include_guard(GLOBAL)

if (NOT CMAKE_SYSTEM_NAME MATCHES "Linux")
  message(WARNING "Cannot determine linux distro on non-linux system.")
  set(LINUX_DISTRO_ID NOTFOUND CACHE STRING "List of linux distribution IDs")
  return()
endif()

# TODO parse /etc/os-release
# For now, guess based on if dpkg or dnf are installed
find_program(LINUX_DISTRO_dpkg dpkg)
find_program(LINUX_DISTRO_dnf dnf)
if (LINUX_DISTRO_dpkg)
  set(distro_ids ubuntu debian)
elseif (LINUX_DISTRO_dnf)
  set(distro_ids fedora rhel)
else()
  set(distro_ids "")
endif()

# Set cache variable with doc string
set(LINUX_DISTRO_ID ${distro_ids} CACHE STRING "List of linux distribution IDs")
