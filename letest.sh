#!/usr/bin/env sh

STAGE=1

lezip="https://github.com/acmesh-official/acme.sh/archive"
legit="https://github.com/acmesh-official/acme.sh.git"

PROJECT="https://github.com/acmesh-official/acmetest"

NGROK_WIKI="https://github.com/acmesh-official/acmetest"


DEFAULT_HOME="$HOME/.acme.sh"


PROJECT_ENTRY="acme.sh"
FILE_NAME="letest.sh"


ENV_FILE="./loadenv.sh"
if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi



BEGIN_CERT="-----BEGIN CERTIFICATE-----"
END_CERT="-----END CERTIFICATE-----"

if [ -z "$CA" ]; then
  CA="(STAGING) Artificial Apricot R3"
fi

if [ -z "$CA_ECDSA" ]; then
  CA_ECDSA="(STAGING) Ersatz Edamame E1"
fi



if [ "$TEST_CA" ]; then
  CA="$TEST_CA"
  CA_ECDSA="$TEST_CA"
fi




ECC_SEP="_"
ECC_SUFFIX="${ECC_SEP}ecc"

STAGE_CA="https://acme-staging.api.letsencrypt.org"

_API_HOST="$(echo "$STAGE_CA" | cut -d : -f 2 | tr -d '/')"







_startswith(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "^$_sub" >/dev/null 2>&1
}

if [ -z "$LOG_FILE" ] ; then
  LOG_FILE="letest.log"
else
  if ! _startswith "$LOG_FILE" "/" ; then
    LOG_FILE="$(pwd)/$LOG_FILE"
    export LOG_FILE
  fi  
fi

export LOG_FILE

if [ -z "$LOG_LEVEL" ] ; then
  LOG_LEVEL=2
fi

export LOG_LEVEL


#we need color in travis
if [ "$TRAVIS" = "true" ] || [ "$GITHUB_REF" ]; then
  export ACME_FORCE_COLOR=1
elif [ "$CI" = "1" ]; then
  #In our cron testing server
  export ACME_NO_COLOR=1  
fi


__INTERACTIVE=""
if [ -t 1 ]; then
  __INTERACTIVE="1"
fi


__green() {
  if [ "${__INTERACTIVE}${ACME_NO_COLOR:-0}" = "10" -o "${ACME_FORCE_COLOR}" = "1" ]; then
    printf '\033[1;31;32m%b\033[0m' "$1"
    return
  fi
  printf -- "%b" "$1"
}

__red() {
  if [ "${__INTERACTIVE}${ACME_NO_COLOR:-0}" = "10" -o "${ACME_FORCE_COLOR}" = "1" ]; then
    printf '\033[1;31;40m%b\033[0m' "$1"
    return
  fi
  printf -- "%b" "$1"
}

__ok() {
  __green " [PASS]"
  printf "\n"
}



__fail() {
  __red " [FAIL] $1" >&2
  printf "\n" >&2
  return 1
}

_head_n() {
  head -n "$1"
}

_dlgVersions() {

  if _exists openssl ; then
    openssl version
  fi
  
  if _exists curl ; then
    curl -V
  fi
  
  if _exists wget ; then
    wget -V
  fi
}

_date_u () {
  date -u +"%a, %d %b %Y %T %Z"
}

#a + b
_math() {
  _m_opts="$@"
  printf "%s" "$(($_m_opts))"
}

_log() {
  if [ "$LOG_FILE" ] ; then
    echo "$@" >> "$LOG_FILE"
  fi
}

_info() {
  if [ -z "$2" ] ; then
    echo "$1"
    _log "$1"
  else
    echo "$1"="'$2'"
    _log "$1"="'$2'"
  fi
}

_err() {
  __red "$(_info "$@")\n" >&2
  return 1
}

_debug() {
  if [ -z "$DEBUG" ] ; then
    return
  fi
  _info "$@" >&2
  return 0
}

_exists() {
  cmd="$1"
  if [ -z "$cmd" ] ; then
    _err "Usage: _exists cmd"
    return 1
  fi
  command -v $cmd >/dev/null 2>&1
  ret="$?"
  _debug "$cmd exists=$ret"
  return $ret
}

_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}

_mktemp() {
  if _exists mktemp; then
    if mktemp 2>/dev/null; then
      return 0
    elif _contains "$(mktemp 2>&1)" "-t prefix" && mktemp -t "$PROJECT_NAME" 2>/dev/null; then
      #for Mac osx
      return 0
    fi
  fi
  if [ -d "/tmp" ]; then
    echo "/tmp/${PROJECT_NAME}wefADf24sf.$(_time).tmp"
    return 0
  elif [ "$LE_TEMP_DIR" ] && mkdir -p "$LE_TEMP_DIR"; then
    echo "/$LE_TEMP_DIR/wefADf24sf.$(_time).tmp"
    return 0
  fi
  _err "Can not create temp file."
}

_egrep_o() {
  if ! egrep -o "$1" 2>/dev/null; then
    sed -n 's/.*\('"$1"'\).*/\1/p'
  fi
}

_ss() {
  _port="$1"
  
  if _exists "ss" ; then
    _debug "Using: ss"
    ss -ntpl | grep ":$_port "
    return 0
  fi

  if _exists "netstat" ; then
    _debug "Using: netstat"
    if netstat -h 2>&1 | grep "\-p proto" >/dev/null ; then
      #for windows version netstat tool
      netstat -anb -p tcp | grep "LISTENING" | grep ":$_port "
    else
      if netstat -help 2>&1 | grep "\-p protocol" >/dev/null ; then
        netstat -an -p tcp | grep LISTEN | grep ":$_port "
      elif netstat -help 2>&1 | grep -- '-P protocol' >/dev/null ; then
        #for solaris
        netstat -an -P tcp | grep "\.$_port " | grep "LISTEN"
      else
        netstat -ntpl | grep ":$_port "
      fi
    fi
    return 0
  fi

  return 1
}

#Usage: multiline
_base64() {
  if [ "$1" ] ; then
    openssl base64 -e
  else
    openssl base64 -e | tr -d '\r\n'
  fi
}

#Usage: hashalg  [outputhex]
#Output Base64-encoded digest
_digest() {
  alg="$1"
  if [ -z "$alg" ] ; then
    _usage "Usage: _digest hashalg"
    return 1
  fi
  
  outputhex="$2"
  
  if [ "$alg" = "sha256" ] ; then
    if [ "$outputhex" ] ; then
      echo $(openssl dgst -sha256 -hex | cut -d = -f 2)
    else
      openssl dgst -sha256 -binary | _base64
    fi
  else
    _err "$alg is not supported yet"
    return 1
  fi

}

_hasfield() {
  _str="$1"
  _field="$2"
  _sep="$3"
  if [ -z "$_field" ]; then
    _usage "Usage: str field  [sep]"
    return 1
  fi

  if [ -z "$_sep" ]; then
    _sep=","
  fi

  for f in $(echo "$_str" | tr "$_sep" ' '); do
    if [ "$f" = "$_field" ]; then
      _debug "'$_str' contains '$_field'"
      return 0 #contains ok
    fi
  done
  _debug "'$_str' does not contain '$_field'"
  return 1 #not contains
}


NGROK_MAC="https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-darwin-amd64.zip"
NGROK_Linux="https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip"
NGROK_Win="https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-windows-amd64.zip"
NGROK_BSD="https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-freebsd-amd64.zip"


CF_Linux="https://bin.equinox.io/c/VdrWdbjqyF/cloudflared-stable-linux-amd64.tgz"
CF_MAC="https://bin.equinox.io/c/VdrWdbjqyF/cloudflared-stable-darwin-amd64.zip"
CF_Win="https://bin.equinox.io/c/VdrWdbjqyF/cloudflared-stable-windows-amd64.zip"




if [ -z "$TestingDomain" ]; then
    if [ -z "$CF_BIN" ] || [ ! -x "$CF_BIN" ]; then
      if _exists "cloudflared" ; then
        _info "Command cloudflared is found, so, use it."
        CF_BIN="cloudflared"
      else
        _os_name="$(uname)"
        _info _os_name "$_os_name"
        case "$_os_name" in
          CYGWIN_NT* | MINGW*)
            _debug "cygwin"
            export CF_BIN="$(pwd)/cloudflared.exe"
            CF_LINK="$CF_Win"
            ;;
          Linux)
            _debug "Linux"
            export CF_BIN="$(pwd)/cloudflared"
            CF_LINK="$CF_Linux"
            ;;
          Darwin)
            _debug "Darwin"
            export CF_BIN="$(pwd)/cloudflared"
            CF_LINK="$CF_MAC"
            ;;            
          *)
            _err "Not supported: $_os_name"
            exit 1
            ;;
        esac

        if [ ! -f "$CF_BIN" ]; then
          _info "Download from $CF_LINK"
          if [ "$CF_LINK" = "$CF_Linux" ]; then
            if ! curl "$CF_LINK" >cf.tgz; then
              _err "Download error."
              exit 1
            fi
            if ! tar -xzf cf.tgz; then
              _err "unzip error."
              exit 1
            fi
          else
            if ! curl "$CF_LINK" >cf.zip; then
              _err "Download error."
              exit 1
            fi
            if [ "$CF_LINK" = "$CF_MAC" ]; then
              if ! 7za e -y cf.zip; then
                _err "unzip error."
                exit 1
              fi
            else
              if ! unzip cf.zip; then
                _err "unzip error."
                exit 1
              fi
            fi
          fi
        fi

        if [ ! -f "$CF_BIN" ]; then
          _err "Please install cloudflared command, or specify CF_BIN=$CF_BIN pointing to the ngrok binary. see: $NGROK_WIKI"
          exit 1
        fi
      fi
    fi

    ng_temp_1="cf.tmp"
    _info "ng_temp_1" "$ng_temp_1"
    $CF_BIN update
    if [ "$Le_HTTPPort" ]; then
      $CF_BIN tunnel --url http://localhost:$Le_HTTPPort >$ng_temp_1 2>&1 &
    else
      $CF_BIN tunnel --url http://localhost >$ng_temp_1 2>&1 &
    fi
    CF_PID="$!"
    _debug "cf pid: $CF_PID"
    
    MaxWait=60;#seconds
    _wait=0;
    while [ $_wait -le $MaxWait ]; do
      sleep 10
      _wait=$((_wait + 10))
      ng_domain_1="$(cat "$ng_temp_1" | grep https:// | grep trycloudflare.com | head -1 | cut -d '|' -f 2 | tr -d ' ' | cut -d '/' -f 3)"
      _info "ng_domain_1" "$ng_domain_1"

      if [ -z "$ng_domain_1" ] ; then
        cat "$ng_temp_1"
        _err "Can not get cf domain."
        continue
      fi
      TestingDomain="$ng_domain_1"
      break
    done;
    if [ -z "$TestingDomain" ] ; then
      cat "$ng_temp_1"
      _err "Can not get cf domain."
      exit 1
    fi
    #TEST_NGROK=1




#  if [ -z "$NGROK_TOKEN" ]; then
#    if [ -f "$USERPROFILE/.ngrok2/ngrok.yml" ]; then
#      #cygwin
#      NGROK_TOKEN=$(grep "authtoken:" "$USERPROFILE/.ngrok2/ngrok.yml" | cut -d : -f 2| tr -d " '")
#    fi
#    if [ -z "$NGROK_TOKEN" ] && [ -f "$HOME/.ngrok2/ngrok.yml" ]; then
#      #linux
#      NGROK_TOKEN=$(grep "authtoken:" "$HOME/.ngrok2/ngrok.yml" | cut -d : -f 2 | tr -d " '")
#    fi
#  fi
#  
#  if [ -z "$NGROK_TOKEN" ]; then
#    _err "The TestingDomain or TestingAltDomains is not specified, see: $PROJECT"
#    _err "You can also specify NGROK_TOKEN to test automatically, see: $NGROK_WIKI"
#    exit 1
#  fi
#
#  if [ "$NGROK_TOKEN" ]; then   
#    if [ -z "$NGROK_BIN" ] || [ ! -x "$NGROK_BIN" ]; then
#      if _exists "ngrok" ; then
#        _info "Command ngrok is found, so, use it."
#        NGROK_BIN="ngrok"
#      else
#        _os_name="$(uname)"
#        _info _os_name "$_os_name"
#        case "$_os_name" in
#          FreeBSD | OpenBSD)
#            _debug "BSD"
#            export NGROK_BIN="$(pwd)/ngrok"
#            NGROK_LINK="$NGROK_BSD"
#            ;;
#          CYGWIN_NT* | MINGW*)
#            _debug "cygwin"
#            export NGROK_BIN="$(pwd)/ngrok.exe"
#            NGROK_LINK="$NGROK_Win"
#            ;;
#          Linux)
#            _debug "Linux"
#            export NGROK_BIN="$(pwd)/ngrok"
#            NGROK_LINK="$NGROK_Linux"
#            ;;
#          Darwin)
#            _debug "Darwin"
#            export NGROK_BIN="$(pwd)/ngrok"
#            NGROK_LINK="$NGROK_MAC"
#            ;;            
#          *)
#            _err "Not supported: $_os_name"
#            exit 1
#            ;;
#        esac
#
#        if [ ! -f "$NGROK_BIN" ]; then
#          _info "Download from $NGROK_LINK"
#          if ! curl "$NGROK_LINK" >ngrok.zip; then
#            _err "Download error."
#            exit 1
#          fi
#          if ! unzip ngrok.zip; then
#            _err "unzip error."
#            exit 1
#          fi
#        fi
#
#        if [ ! -f "$NGROK_BIN" ]; then
#          _err "The NGROK_TOKEN is specified, it seems that you want to use ngrok to test, but the executable ngrok is not found."
#          _err "Please install ngrok command, or specify NGROK_BIN=$NGROK_BIN pointing to the ngrok binary. see: $NGROK_WIKI"
#          exit 1
#        fi
#      fi
#    fi
#    
#    _info "Using ngrok, register auth token first."
#    if ! $NGROK_BIN authtoken "$NGROK_TOKEN" ; then
#      _err "Register ngrok auth token failed."
#      exit 1
#    fi
#    
#    ng_temp_1="ngrok.tmp"
#    _info "ng_temp_1" "$ng_temp_1"
#    if [ "$Le_HTTPPort" ]; then
#      $NGROK_BIN http $Le_HTTPPort --log stdout --log-format logfmt --log-level debug > "$ng_temp_1" &
#    else
#      $NGROK_BIN http 80 --log stdout --log-format logfmt --log-level debug > "$ng_temp_1" &
#    fi
#    NGROK_PID="$!"
#    _debug "ngrok pid: $NGROK_PID"
#    
#    sleep 20
#    
#    ng_domain_1="$(_egrep_o 'Hostname:.+.ngrok.io' <"$ng_temp_1" | _head_n 1 | cut -d':' -f2)"
#    _info "ng_domain_1" "$ng_domain_1"
#    
#    if [ -z "$ng_domain_1" ] ; then
#      cat "$ng_temp_1"
#      _err "Can not get ngrok domain."
#      exit 1
#    fi
#    TestingDomain="$ng_domain_1"
#    TEST_NGROK=1
#  fi
fi

if [ -z "$TestingDomain" ] && [ -z "$TEST_DNS" ]; then
  _err "The TestingDomain or TestingAltDomains is not specified, see: $PROJECT"
  _err "You can also specify NGROK_TOKEN to test automatically, see: $NGROK_WIKI"
  exit 1
fi

if [ "$TEST_IDN" ] ; then
  if [ -z "$TestingIDNDomain" ] ; then
    TestingIDNDomain="中$TestingDomain"
  fi
fi


if [ "$DOCKER_OS" = "centos:5" ] \
 || [ "$DOCKER_OS" = "gentoo/stage3-amd64" ] ; then
 NO_ECC_CASES="1"
 if ! grep "insecure" ~/.curlrc >/dev/null 2>&1; then
   echo insecure >>~/.curlrc
 fi
 NO_HMAC_CASES="1"
 TEST_DNS=""
fi 



#file subname issuername
_assertcert() {
  filename="$1"
  subname="$2"
  issuername="$3"
  printf "$filename is cert ? "
  subj="$(echo  $(openssl x509  -in $filename  -text  -noout | grep 'Subject:.*CN *=' | _egrep_o  " CN *=.*" | cut -d '=' -f 2 | cut -d / -f 1))"
  printf "'$subj'"
  if _contains "$subj" "$subname"; then
    if [ "$issuername" ] ; then
      issuer="$(echo $(openssl x509 -in $filename -text -noout | grep 'Issuer:' | _egrep_o "CN *=[^,]*" | cut -d = -f 2))"
      printf " '$issuer'"
      if ! _contains "$issuer" "$issuername"; then
        __fail "Expected issuer is: '$issuername', but was: '$issuer'"
        return 1
      fi
    fi
    __ok ""
    return 0
  else
    __fail "Expected subject is: '$subname', but was: '$subj'"
    return 1
  fi
}

#cmd
_assertcmd() {
  __cmd="$1"
  printf "%b" "$__cmd"
  
  eval "$__cmd > \"cmd.log\" 2>&1"
  
  if [ "$?" = "0" ] ; then 
    __ok ""
  else
    __fail ""
    if [ "$DEBUG" ] ; then
      cat "cmd.log" >&2
    fi
    return 1
  fi
  return 0
}

#file
_assertexists() {
  __file="$1"
  if [ -e "$__file" ] ; then
    printf "$__file exists."
    __ok ""
  else
    printf "$__file missing."
    __fail ""
    return 1
  fi
  return 0
}

#file
_assertnotexists() {
  __file="$1"
  if [ ! -e "$__file" ] ; then
    printf "$__file no exists."
    __ok ""
  else
    printf "$__file is there."
    __fail ""
    return 1
  fi
  return 0
}

_assertequals() {
  if [ "$1" = "$2" ] ; then
    printf "equals $1"
    __ok ""
  else
    __fail "Failed"
    _err "Expected:$1"
    _err "But was:$2"
  fi
}

#file1 file2
_assertfileequals(){
  file1="$1"
  file2="$2"
  if [ "$(cat "$file1" | _digest  sha256)" = "$(cat "$file2" | _digest  sha256)" ] ; then
    printf -- "'$file1' equals '$2'"
    __ok
  else
    __fail "Failed"
  fi
}

_run() {
  _test="$1"
  _info "==Running $_test please wait"
  lehome="$DEFAULT_HOME"
  export STAGE
  export DEBUG
  
  if [ "$_test" != "le_test_installtodir" ] && [ "$_test" != "le_test_uninstalltodir" ] && [ "$_test" != "le_test_install_config_home" ]; then
    cd acme.sh;
    ./$PROJECT_ENTRY install > /dev/null
    cd ..
  fi
  
  _r="0"
  __CASE_SKIPPED=""
  if ! ( $_test ) ; then
    _r="1"
  fi
  if [ "$_r" = "0" ]; then
    _debug "Run Success"
  else
    _err "Run Failed"
  fi
  DEFAULT_CA_HOME="$lehome/ca"

  if [ -z "$CA_HOME" ] ; then
    CA_HOME="$DEFAULT_CA_HOME"
  fi
    
  CA_DIR="$CA_HOME/$_API_HOST"

  if _contains "$_test" "SAN"; then
    _deactivateDomains="$TestingDomain$TestingAltDomains"
  else
    _deactivateDomains="$TestingDomain"
  fi
  _debug "_deactivateDomains" "$_deactivateDomains"
  if [ ! "$DEBUG" ] ; then
    rm -rf "$lehome/$TestingDomain"
    rm -rf "$lehome/$TestingDomain$ECC_SUFFIX"
    if [ -f "$lehome/$PROJECT_ENTRY" ] ; then
      if [ -z "$__CASE_SKIPPED" ] && [ -f "$CA_DIR/account.key" ] ; then
        $lehome/$PROJECT_ENTRY --deactivate -d "$_deactivateDomains" >deactivate.log 2>&1
      fi
      __dr="$?"
      if [ "$__dr" != "0" ]; then
        _err "deactivate failed"
        cat deactivate.log
      fi
      if [ "$_r" = "0" ] ; then
        _r="$__dr"
      fi
      $lehome/$PROJECT_ENTRY --uninstall >/dev/null
    fi
  else
    if [ -f "$CA_DIR/account.key" ] ; then
      $lehome/$PROJECT_ENTRY --deactivate -d "$_deactivateDomains" >/dev/null 2>&1
    fi
  fi
  rm -f "$lehome/account.conf"
  _debug "_r" "$_r"
  _info "------------------------------------------"
  return $_r
}

####################################################
_setup() {
  if [ "$TEST_LOCAL" = "1" ] ; then
    _info "TEST_LOCAL skip setup."
    return 0
  fi
  if [ -d acme.sh ] ; then
    rm -rf acme.sh 
  fi
  if [ ! "$BRANCH" ] ; then
    BRANCH="master"
  fi
  _info "Testing branch: $BRANCH"
  if command -v tar > /dev/null ; then
    link="$lezip/$BRANCH.tar.gz"
    curl -OL "$link" >/dev/null 2>&1
    tar xzf "$BRANCH.tar.gz"  >/dev/null 2>&1
    mv "acme.sh-$BRANCH" acme.sh
  elif command -v git > /dev/null ; then
    rm -rf acme.sh
    git clone $legit -b $BRANCH
  else
    _err "Can not get acme.sh source code. tar or git must be installed"
    return 1
  fi
  lehome="$DEFAULT_HOME"
  if [ -f "$lehome/$PROJECT_ENTRY" ] ; then
    $lehome/$PROJECT_ENTRY --uninstall >/dev/null 2>&1
  fi
  
  if [ -d $DEFAULT_HOME ] ; then 
    rm -rf $DEFAULT_HOME
  fi
  
  #reuse ca account keys for the low acount rate limit
  if [ -d "ca" ]; then
    mkdir -p "$DEFAULT_HOME"
    cp -r ca "$DEFAULT_HOME/"
    rm -f "$DEFAULT_HOME/ca/*/ca.conf"
  fi

}


le_test_dependencies() {
  dependencies="curl crontab openssl socat"
  for cmd in $dependencies 
  do
    if command -v $cmd > /dev/null ; then
      printf "$cmd installed." 
      __ok
    else
      printf "$cmd not installed"
      __fail
      return 1
    fi
  done
}

le_test_install() {
  lehome="$DEFAULT_HOME"
  
  cd acme.sh;
  _assertcmd  "./$PROJECT_ENTRY --install" || return
  cd ..
  
  _assertexists "$lehome/$PROJECT_ENTRY" || return
  _c_entry="$(crontab -l | grep $PROJECT_ENTRY)"
  _assertcmd "_contains '$_c_entry' ' \\* \\* \\* \"$lehome\"/$PROJECT_ENTRY --cron --home \"$lehome\" > /dev/null'" || return
  _assertcmd "$lehome/$PROJECT_ENTRY --uninstall  > /dev/null" ||  return
}

le_test_uninstall() {
  lehome="$DEFAULT_HOME"
  cd acme.sh;
  _assertcmd  "./$PROJECT_ENTRY --install" || return
  cd ..
  _assertcmd "$lehome/$PROJECT_ENTRY --uninstall" ||  return
  _assertnotexists "$lehome/$PROJECT_ENTRY" ||  return
  _assertequals "" "$(crontab -l | grep $PROJECT_ENTRY)"||  return

}


le_test_installtodir() {
  lehome="$HOME/myle"
  if [ -d $lehome ] ; then
    rm -rf $lehome
  fi
  cd acme.sh;
  LE_WORKING_DIR=$lehome
  export LE_WORKING_DIR
  _assertcmd "./$PROJECT_ENTRY --install" ||  return
  LE_WORKING_DIR=""
  cd ..
  
  _assertexists "$lehome/$PROJECT_ENTRY" ||  return
  _c_entry="$(crontab -l | grep $PROJECT_ENTRY)"
  _assertcmd "_contains '$_c_entry' ' \\* \\* \\* \"$lehome\"/$PROJECT_ENTRY --cron --home \"$lehome\" > /dev/null'" || return
  _assertcmd "$lehome/$PROJECT_ENTRY --uninstall" ||  return
  if [ -z "$DEBUG" ]; then
    rm -rf $lehome
  fi
}

le_test_uninstalltodir() {
  lehome="$HOME/myle"
  
  if [ -d $lehome ] ; then
    rm -rf $lehome
  fi
  
  cd acme.sh;
  LE_WORKING_DIR=$lehome
  export LE_WORKING_DIR
  _assertcmd "./$PROJECT_ENTRY --install" ||  return
  LE_WORKING_DIR=""
  cd ..
  
  _assertcmd "$lehome/$PROJECT_ENTRY --uninstall" ||  return
  _assertnotexists "$lehome/$PROJECT_ENTRY" ||  return
  _assertequals "" "$(crontab -l | grep $PROJECT_ENTRY)" ||  return
  if [ -z "$DEBUG" ]; then
    rm -rf $lehome
  fi
}

le_test_install_config_home() {
  lehome="$DEFAULT_HOME"
  confighome="$HOME/etc/acme"
  
  cd acme.sh;
  _assertcmd  "./$PROJECT_ENTRY --install --config-home $confighome" || return
  cd ..
  
  _assertexists "$lehome/$PROJECT_ENTRY" || return
  _c_entry="$(crontab -l | grep $PROJECT_ENTRY)"
  _assertcmd "_contains '$_c_entry' ' \\* \\* \\* \"$lehome\"/$PROJECT_ENTRY --cron --home \"$lehome\" --config-home \"$confighome\" > /dev/null'" || return
  _assertexists "$confighome/account.conf" || return
  _assertnotexists "$lehome/account.conf" || return
  _assertcmd "$lehome/$PROJECT_ENTRY --cron --config-home $confighome > /dev/null" ||  return
  _assertcmd "$lehome/$PROJECT_ENTRY --uninstall --config-home $confighome > /dev/null" ||  return
  _assertexists "$confighome/account.conf" || return
  _assertnotexists "$lehome/account.conf" || return
  if [ -z "$DEBUG" ]; then
    rm -rf "$confighome"
  fi
}


#
le_test_standandalone_renew_v2() {
  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  certdir="$(pwd)/certs"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return

  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return

  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return

  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


#
le_test_standandalone_renew_localaddress_v2() {

  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  certdir="$(pwd)/certs"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone --local-address 0.0.0.0 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    return 0
  fi
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


#
le_test_standandalone_listen_v4_v2() {
  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  certdir="$(pwd)/certs"
  rm -rf "$certdir"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone --listen-v4 --cert-file '$cert' --key-file '$key'  --ca-file '$ca'  --reloadcmd 'echo this is reload'  --fullchain-file  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    return 0
  fi
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


#
le_test_standandalone_listen_v6_v2() {
  if [ -z "$TEST_IPV6" ] ; then
    _info "Skipped by TEST_IPV6"
    __CASE_SKIPPED="1"
    return 0
  fi

  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  certdir="$(pwd)/certs"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone --listen-v6 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    return 0
  fi
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

#
le_test_standandalone_deactivate_v2() {
  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  certdir="$(pwd)/certs"
  rm -rf "$certdir"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --deactivate -d $TestingDomain" ||  return
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


le_test_standandalone_SAN() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    __CASE_SKIPPED="1"
    return 0
  fi
  lehome="$DEFAULT_HOME"

  lp=`_ss| grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and TestingAltDomains, and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d \"$TestingDomain\" -d \"$TestingAltDomains\" --standalone" ||  return
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi
  
  
}

le_test_standandalone_ECDSA_256_renew() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    __CASE_SKIPPED="1"
    return 0
  fi
  
  if [ "$NO_ECC_CASES" ] ; then
    _info "Skipped by NO_ECC_CASES"
    __CASE_SKIPPED="1"
    return 0
  fi
    
  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain$ECC_SUFFIX"
 
  _assertcmd "$lehome/$PROJECT_ENTRY  --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone -k ec-256" ||  return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$TestingDomain" "$CA_ECDSA" || return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$CA_ECDSA" || return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain --ecc" ||  return

  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force --ecc" ||  return

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi
  
  

}

le_test_standandalone_ECDSA_256_SAN_renew_v2() {
  if [ "$NO_ECC_CASES" ] ; then
    _info "Skipped by NO_ECC_CASES"
    __CASE_SKIPPED="1"
    return 0
  fi 
  
  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain$ECC_SUFFIX"
  
  certdir="$(pwd)/certs"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue -d \"$TestingDomain\" -d \"$TestingAltDomains\" --standalone --keylength ec-256 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/fullchain.cer" "$full" ||  return
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain --ecc" ||  return
  
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --renew --ecc -d \"$TestingDomain\" --force" ||  return
  
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$TestingDomain" "$CA_ECDSA" || return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$CA_ECDSA" || return
  
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain --ecc"||  return
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

le_test_standandalone_ECDSA_384() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    __CASE_SKIPPED="1"
    return 0
  fi
  
  if [ "$NO_ECC_CASES" ] ; then
    _info "Skipped by NO_ECC_CASES"
    __CASE_SKIPPED="1"
    return 0
  fi

  if [ "$NO_ECC_384" ] ; then
    _info "Skipped by NO_ECC_384"
    __CASE_SKIPPED="1"
    return 0
  fi

  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain$ECC_SUFFIX"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue --standalone -d \"$TestingDomain\" -k ec-384" ||  return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$TestingDomain" "$CA_ECDSA" || return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$CA_ECDSA" || return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain --ecc" ||  return

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi


}

#
le_test_standandalone_renew_idn_v2() {
  if [ -z "$TEST_IDN" ] ; then
    _info "Skipped by TEST_IDN"
    __CASE_SKIPPED="1"
    return 0
  fi
  
  lehome="$DEFAULT_HOME"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  _test_idn="$TestingIDNDomain"
  rm -rf "$lehome/$_test_idn"
  
  certdir="$(pwd)/certs"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue -d $_test_idn --standalone --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$_test_idn/$_test_idn.cer" "$cert" ||  return
  _assertfileequals "$lehome/$_test_idn/$_test_idn.key" "$key" ||  return
  _assertfileequals "$lehome/$_test_idn/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$_test_idn/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $_test_idn" ||  return
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $_test_idn --force" ||  return
  
  _assertcert "$lehome/$_test_idn/$_test_idn.cer" "$(idn $_test_idn)" "$CA" || return
  _assertcert "$lehome/$_test_idn/ca.cer" "$CA" || return
  
  _assertfileequals "$lehome/$_test_idn/$_test_idn.cer" "$cert" ||  return
  _assertfileequals "$lehome/$_test_idn/$_test_idn.key" "$key" ||  return
  _assertfileequals "$lehome/$_test_idn/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$_test_idn/fullchain.cer" "$full" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $_test_idn" ||  return
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


le_test_dnsapi() {
  if [ -z "$TEST_DNS" ]; then
    _info "Skipped by TEST_DNS"
    __CASE_SKIPPED="1"
    return 0
  fi
  _debug "$dnsapi"
  api=$TEST_DNS
  _debug api "$api"
  if [ "$NO_HMAC_CASES" = "1" ] && [ "$api" = "dns_aws" ]; then
    _info "Skipped for NO_HMAC_CASES"
    return 0
  fi

  d_sleep=$TEST_DNS_SLEEP

  if [ "$TEST_DNS_NO_WILDCARD" != "1" ]; then
    (
    _info "Testing wildcard domain. "
    _info "TestingDomain" "$TestingDomain"
    lehome="$DEFAULT_HOME"
    rm -rf "$lehome/$TestingDomain"

    _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue -d \"$TestingDomain\" -d \"*.$TestingDomain\" --dns $api --dnssleep \"$d_sleep\" " ||  return
    
    _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
    _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
    _assertcmd "$lehome/$PROJECT_ENTRY --deactivate -d \"$TestingDomain\" >/dev/null 2>&1"
    sleep 5
    _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
    ) || return
  else
    (
    _info "Testing normal domain. "
    _info "TestingDomain" "$TestingDomain"
    
    lehome="$DEFAULT_HOME"
    rm -rf "$lehome/$TestingDomain"

    _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue -d \"$TestingDomain\" -d \"www.$TestingDomain\" --dns $api --dnssleep \"$d_sleep\" " ||  return

    _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
    _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
    _assertcmd "$lehome/$PROJECT_ENTRY --deactivate -d \"$TestingDomain\" >/dev/null 2>&1"
    sleep 5
    _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return
    ) || return 
  fi

}


#
le_test_standandalone_ipcert() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    __CASE_SKIPPED="1"
    return 0
  fi
  if [ -z "$TEST_IPCERT" ] ; then
    _info "Skipped by TEST_IPCERT"
    __CASE_SKIPPED="1"
    return 0
  fi

  lehome="$DEFAULT_HOME"

  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --standalone" ||  return
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return


}

le_test_alpn_ipcert() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skipped by QUICK_TEST"
    __CASE_SKIPPED="1"
    return 0
  fi
  if [ -z "$TEST_IPCERT" ] ; then
    _info "Skipped by TEST_IPCERT"
    __CASE_SKIPPED="1"
    return 0
  fi

  lehome="$DEFAULT_HOME"

  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --server \"$TEST_ACME_Server\"  --issue -d $TestingDomain --alpn" ||  return
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return

  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --revoke -d $TestingDomain" ||  return

}


#####################################

if [ "$1" ] ; then
  CASE="$1"
fi

_date_u

_setup

_ret=0

total=$(grep ^le_test_  $FILE_NAME | wc -l | tr -d ' ')
num=1
for t in $(grep ^le_test_  $FILE_NAME | cut -d '(' -f 1) 
do
  if [ -z "$CASE" ] ; then
    __green "Progress: "
    __green "$num/"
    [ "$_ret" = "0" ] && __green "$_ret" || __red "$_ret"
    __green "/$total"

    printf "\n"
    num=$(_math $num + 1)
  fi
  _rr=0
  _debug t "$t"
  _case_log="$t.log"
  if [ -z "$CASE" ] || _hasfield "$CASE" "$t"; then
    _saved_log="$LOG_FILE"
    export LOG_FILE="$_case_log"
    _run "$t"
    _rr="$?"
    export LOG_FILE="$_saved_log"
    cat "$_case_log" >> "$LOG_FILE"
    _debug "_rr" "$_rr"
    _ret=$(_math $_ret + $_rr)
    _debug _ret "$_ret"
  fi

  if [ "$_ret" != "0" ] ; then
    if [ "$TRAVIS" = "true" ] || [ "$CI" = "true" ] ; then
      cat "$_case_log"
      break
    fi
    if [ "$DEBUG" ] || [ "$DEBUGING" ] ; then 
      break;
    fi
  fi
  if [ "$CASE" = "$t" ] ; then
    break;
  fi
done

if [ "$CF_PID" ] ; then
  kill -9 "$CF_PID"
fi

if [ "$NGROK_PID" ] ; then
  kill -9 "$NGROK_PID"
fi

exit $_ret

