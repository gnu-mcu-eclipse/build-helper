# -----------------------------------------------------------------------------

# Helper script used in the second edition of the GNU MCU Eclipse build 
# scripts. As the name implies, it should contain only functions and 
# should be included with 'source' by the container build scripts.

# -----------------------------------------------------------------------------

function start_timer() 
{
  CONTAINER_BEGIN_SECOND=$(date +%s)
  echo
  echo "Script \"$0\" started at $(date)."
}

function stop_timer() 
{
  local end_second=$(date +%s)
  echo
  echo "Script \"$0\" completed at $(date)."
  local delta_seconds=$((end_second-CONTAINER_BEGIN_SECOND))
  if [ ${delta_seconds} -lt 100 ]
  then
    echo "Duration: ${delta_seconds} seconds."
  else
    local delta_minutes=$(((delta_seconds+30)/60))
    echo "Duration: ${delta_minutes} minutes."
  fi
}

# -----------------------------------------------------------------------------

function detect() 
{
  echo
  uname -a

  CONTAINER_DISTRO_NAME=""
  CONTAINER_UNAME="$(uname)"

  if [ "${CONTAINER_UNAME}" == "Darwin" ]
  then

    CONTAINER_BITS="64"
    CONTAINER_MACHINE="x86_64"

    CONTAINER_DISTRO_NAME=Darwin
    CONTAINER_DISTRO_LC_NAME=darwin

  elif [ "${CONTAINER_UNAME}" == "Linux" ]
  then
    # ----- Determine distribution name and word size -----

    set +e
    CONTAINER_DISTRO_NAME=$(lsb_release -si)
    set -e

    if [ -z "${CONTAINER_DISTRO_NAME}" ]
    then
      echo "Please install the lsb core package and rerun."
      CONTAINER_DISTRO_NAME="Linux"
    fi

    CONTAINER_MACHINE="$(uname -m)"
    if [ "${CONTAINER_MACHINE}" == "x86_64" ]
    then
      CONTAINER_BITS="64"
    elif [ "${CONTAINER_MACHINE}" == "i686" ]
    then
      CONTAINER_BITS="32"
    else
      echo "Unknown uname -m ${CONTAINER_MACHINE}"
      exit 1
    fi

    CONTAINER_DISTRO_LC_NAME=$(echo ${CONTAINER_DISTRO_NAME} | tr "[:upper:]" "[:lower:]")

  else
    echo "Unknown uname ${CONTAINER_UNAME}"
    exit 1
  fi

  echo
  echo "Container running on ${CONTAINER_DISTRO_NAME} ${CONTAINER_BITS}-bits."
}

function prepare_prerequisites() 
{
  if [ -f "/opt/xbb/xbb.sh" ]
  then
    source "/opt/xbb/xbb.sh"
  elif [ -f "$HOME/opt/homebrew/xbb/bin/xbb-source.sh" ]
  then
    source "$HOME/opt/homebrew/xbb/bin/xbb-source.sh"
  else
    echo "Missing XBB tools, exit."
    exit 1
  fi

  # Compute the BUILD/HOST/TARGET for configure.
  CROSS_COMPILE_PREFIX=""
  if [ "${TARGET_OS}" == "win" ]
  then
    TARGET_FOLDER_NAME="${TARGET_OS}${TARGET_BITS}"

    # For Windows targets, decide which cross toolchain to use.
    if [ ${TARGET_BITS} == "32" ]
    then
      CROSS_COMPILE_PREFIX="i686-w64-mingw32"
    elif [ ${TARGET_BITS} == "64" ]
    then
      CROSS_COMPILE_PREFIX="x86_64-w64-mingw32"
    fi

    BUILD="$(${XBB_FOLDER}/share/libtool/build-aux/config.guess)"
    HOST="${CROSS_COMPILE_PREFIX}"
    TARGET=${HOST}

  elif [ "${TARGET_OS}" == "osx" ]
  then

    TARGET_BITS="64" # Only 64-bits macOS binaries
    TARGET_FOLDER_NAME="${TARGET_OS}"

    BUILD="$(${XBB_FOLDER}/share/libtool/build-aux/config.guess)"
    HOST=${BUILD}
    TARGET=${HOST}

  elif [ "${TARGET_OS}" == "linux" ]
  then

    if [ "${TARGET_BITS}" == "-" ]
    then
      TARGET_BITS="${CONTAINER_BITS}"
    else
      if [ "${TARGET_BITS}" != "${CONTAINER_BITS}" ]
      then
        echo "Cannot build ${TARGET_BITS} target on the ${CONTAINER_BITS} container."
        exit 1
      fi
    fi

    TARGET_FOLDER_NAME=${CONTAINER_DISTRO_LC_NAME}${TARGET_BITS:-""}

    BUILD="$(${XBB_FOLDER}/share/libtool/build-aux/config.guess)"
    HOST=${BUILD}
    TARGET=${HOST}

  else
    echo "Unsupported target os ${TARGET_OS}"
    exit 1
  fi

  if [ -f "/.dockerenv" ]
  then
    WORK_FOLDER_PATH="${CONTAINER_WORK_FOLDER_PATH}"
    DOWNLOAD_FOLDER_PATH="${CONTAINER_CACHE_FOLDER_PATH}"
  else
    WORK_FOLDER_PATH="${HOST_WORK_FOLDER_PATH}"
    DOWNLOAD_FOLDER_PATH="${HOST_CACHE_FOLDER_PATH}"
  fi

  if [ \( "${IS_DEVELOP}" != "y" \) -a \( -f "/.dockerenv" \) ]
  then
    BUILD_FOLDER_PATH="/tmp/build/${TARGET_FOLDER_NAME}"
    INSTALL_FOLDER_PATH="/tmp/install/${TARGET_FOLDER_NAME}"
  else
    BUILD_FOLDER_PATH="${WORK_FOLDER_PATH}/build/${TARGET_FOLDER_NAME}"
    INSTALL_FOLDER_PATH="${WORK_FOLDER_PATH}/install/${TARGET_FOLDER_NAME}"
  fi

  DEPLOY_FOLDER_PATH="${WORK_FOLDER_PATH}/${DEPLOY_FOLDER_NAME}/${TARGET_FOLDER_NAME}"

  mkdir -p "${BUILD_FOLDER_PATH}"
  mkdir -p "${INSTALL_FOLDER_PATH}"
  mkdir -p "${DEPLOY_FOLDER_PATH}"
}

# -----------------------------------------------------------------------------

# $1 - absolute path to input folder
# $2 - name of output folder below INSTALL_FOLDER
function copy_license() 
{
  # Iterate all files in a folder and install some of them in the
  # destination folder
  echo "$2"
  for f in "$1/"*
  do
    if [ -f "$f" ]
    then
      if [[ "$f" =~ AUTHORS.*|NEWS.*|COPYING.*|README.*|LICENSE.*|FAQ.*|DEPENDENCIES.*|THANKS.* ]]
      then
        /usr/bin/install -d -m 0755 \
          "${INSTALL_FOLDER_PATH}/${APP_LC_NAME}/gnu-mcu-eclipse/licenses/$2"
        /usr/bin/install -v -c -m 644 "$f" \
          "${INSTALL_FOLDER_PATH}/${APP_LC_NAME}/gnu-mcu-eclipse/licenses/$2"
      fi
    fi
  done

  (
    xbb_activate

    if [ "${TARGET_OS}" == "win" ]
    then
      find "${INSTALL_FOLDER_PATH}/${APP_LC_NAME}/gnu-mcu-eclipse/licenses" \
        -type f \
        -exec unix2dos '{}' ';'
    fi
  )
}

function do_copy_scripts()
{
  cp -r "${WORK_FOLDER_PATH}"/scripts \
    "${INSTALL_FOLDER_PATH}/${APP_LC_NAME}"/gnu-mcu-eclipse/
}

# -----------------------------------------------------------------------------

function extract()
{
  local archive_name="$1"
  local folder_name="$2"
  local pwd="$(pwd)"

  if [ ! -d "${folder_name}" ]
  then
    (
      xbb_activate

      echo "Extracting ${archive_name}..."
      if [[ "${archive_name}" == *zip ]]
      then
        unzip "${archive_name}" -d "$(basename ${archive_name} ".zip")"
      else
        tar xf "${archive_name}"
      fi
    )
  else
    echo "Folder ${folder_name} already present."
  fi
}

function download()
{
  local url="$1"
  local archive_name="$2"

  if [ ! -f "${DOWNLOAD_FOLDER_PATH}/${archive_name}" ]
  then
    (
      xbb_activate

      echo "Downloading ${archive_name}..."
      rm -f "${DOWNLOAD_FOLDER_PATH}/${archive_name}.download"
      curl --fail -L -o "${DOWNLOAD_FOLDER_PATH}/${archive_name}.download" "${url}"
      mv "${DOWNLOAD_FOLDER_PATH}/${archive_name}.download" "${DOWNLOAD_FOLDER_PATH}/${archive_name}"
    )
  else
    echo "File ${archive_name} already downloaded."
  fi
}

function download_and_extract()
{
  local url="$1"
  local archive_name="$2"
  local folder_name="$3"

  download "${url}" "${archive_name}" 
  extract "${DOWNLOAD_FOLDER_PATH}/${archive_name}" "${folder_name}"
}

# -----------------------------------------------------------------------------

# Copy one folder to another
function copy_dir() 
{
  set +u
  mkdir -p "$2"

  (cd "$1" && tar cf - .) | (cd "$2" && tar xf -)
  set -u
}

# Strip binary files as in "strip binary" form, for both native
# (linux/mac) and mingw.
function strip_binary() 
{
    set +e
    if [ $# -ne 2 ] 
    then
        warning "strip_binary: Missing arguments"
        return 0
    fi

    local strip="$1"
    local bin="$2"

    file ${bin} | egrep -q "( ELF )|( PE )|( PE32 )|( Mach-O )"
    if [ $? -eq 0 ]
    then
        echo ${strip} ${bin}
        ${strip} ${bin} 2>/dev/null || true
    fi

    set -e
}

# -----------------------------------------------------------------------------

function compute_sha() 
{
  # $1 shasum program
  # $2.. options
  # ${!#} file

  file=${!#}
  sha_file="${file}.sha"
  "$@" >"${sha_file}"
  echo "SHA: $(cat ${sha_file})"
}

# -----------------------------------------------------------------------------

function fix_ownership()
{
  if [ -f "/.dockerenv" ]
  then
    # Set the owner of the folder and files created by the docker CentOS 
    # container to match the user running the build script on the host. 
    # When running on linux host, these folders and their content remain  
    # owned by root if this is not done. However, when host is 'osx' (macOS),  
    # the owner produced by docker is the same as the macOS user, so an 
    # ownership change is not realy necessary. 
    echo
    echo "Changing ownership to non-root Linux user..."

    if [ -d "${BUILD_FOLDER_PATH}" ]
    then
      chown -R ${USER_ID}:${GROUP_ID} "${BUILD_FOLDER_PATH}"
    fi
    if [ -d "${INSTALL_FOLDER_PATH}" ]
    then
      chown -R ${USER_ID}:${GROUP_ID} "${INSTALL_FOLDER_PATH}"
    fi
    chown -R ${USER_ID}:${GROUP_ID} "${WORK_FOLDER_PATH}/${DEPLOY_FOLDER_NAME}"
  fi
}

# -----------------------------------------------------------------------------
