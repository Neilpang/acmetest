#!/usr/bin/env sh

STAGE=1

lezip="https://github.com/Neilpang/acme.sh/archive"
legit="https://github.com/Neilpang/acme.sh.git"

Default_Home="$HOME/.acme.sh"

PROJECT_ENTRY="acme.sh"
FILE_NAME="letest.sh"

BEGIN_CERT="-----BEGIN CERTIFICATE-----"
END_CERT="-----END CERTIFICATE-----"

CA="Fake LE Intermediate X1"

ECC_SEP="_"
ECC_SUFFIX="${ECC_SEP}ecc"

STAGE_CA="https://acme-staging.api.letsencrypt.org"

_API_HOST="$(echo "$STAGE_CA" | cut -d : -f 2 | tr -d '/')"




_startswith(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}



if [ -z "$LOG_FILE" ] ; then
  LOG_FILE="letest.log"
else
  if ! _startswith "$LOG_FILE" "/" ; then
    LOG_FILE="$(pwd)/$LOG_FILE"
    export LOG_FILE
  fi  
fi

if [ -z "$LOG_LEVEL" ] ; then
  LOG_LEVEL=2
fi

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

#a + b
_math(){
  expr "$@"
}

_log() {
  if [ "$LOG_FILE" ] ; then
    echo "$@" >> $LOG_FILE
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
  _info "$@" >&2
  return 1
}

_debug() {
  if [ -z "$DEBUG" ] ; then
    return
  fi
  _err "$@"
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

SUDO="$(command -v sudo | grep 'sudo')"

if command -v yum > /dev/null ; then
 INSTALL="$SUDO yum install -y "
elif command -v apt-get > /dev/null ; then
 INSTALL="$SUDO apt-get install -y "
fi


__green() {
  printf '\033[1;31;32m'
  printf -- "$1"
  printf '\033[0m'
}

__ok() {
  __green " [PASS]"
  printf "\n"
}

__red() {
  printf '\033[1;31;40m'
  printf -- "$1"
  printf '\033[0m'
}

__fail() {
  __red " [FAIL] $1" >&2
  printf "\n" >&2
  return 1
}

#file subname
_assertcert() {
  filename="$1"
  subname="$2"
  issuername="$3"
  printf "$filename is cert ? "
  subj="$(echo  $(openssl x509  -in $filename  -text  -noout | grep 'Subject: CN *=' | cut -d '=' -f 2 | cut -d / -f 1))"
  printf "'$subj'"
  if [ "$subj" = "$subname" ] ; then
    if [ "$issuername" ] ; then
      issuer="$(echo  $(openssl x509  -in $filename  -text  -noout | grep 'Issuer: CN *=' | cut -d '=' -f 2))"
      printf " '$issuer'"
      if [ "$issuername" != "$issuer" ] ; then
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
  printf "$__cmd"
  
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
  _info "==Running $1 please wait"
  lehome="$Default_Home"
  export STAGE
  export DEBUG
  
  if [ "$1" != "le_test_installtodir" ] && [ "$1" != "le_test_uninstalltodir" ] ; then
    cd acme.sh;
    ./$PROJECT_ENTRY install > /dev/null
    cd ..
  fi
  
  _r="0"
  if ! ( $1 ) ; then
    _r="1"
  fi
  
  DEFAULT_CA_HOME="$lehome/ca"

  if [ -z "$CA_HOME" ] ; then
    CA_HOME="$DEFAULT_CA_HOME"
  fi
    
  CA_DIR="$CA_HOME/$_API_HOST"

  if [ ! "$DEBUG" ] ; then
    rm -rf "$lehome/$TestingDomain"
    rm -rf "$lehome/$TestingDomain$ECC_SUFFIX"
    if [ -f "$lehome/$PROJECT_ENTRY" ] ; then
      if [ -f "$CA_DIR/account.key" ] ; then
        $lehome/$PROJECT_ENTRY --deactivate -d "$TestingDomain"  -d "$TestingAltDomains" >/dev/null
      fi
      __dr="$?"
      if [ "$_r" = "0" ] ; then
        _r="$__dr"
      fi
      $lehome/$PROJECT_ENTRY uninstall >/dev/null
    fi
  else
    if [ -f "$CA_DIR/account.key" ] ; then
      $lehome/$PROJECT_ENTRY --deactivate -d "$TestingDomain"  -d "$TestingAltDomains"
    fi
  fi  
  _debug "_r" "$_r"
  _info "------------------------------------------"
  return $_r
}

####################################################
_setup() {
  if [ "$TEST_LOCAL" ] ; then
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
  lehome="$Default_Home"
  if [ -f "$lehome/$PROJECT_ENTRY" ] ; then
    $lehome/$PROJECT_ENTRY uninstall >/dev/null 2>&1
  fi
  
  if [ -d $Default_Home ] ; then 
    rm -rf $Default_Home
  fi
  

}


le_test_dependencies() {
  dependencies="curl crontab openssl nc"
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
  lehome="$Default_Home"
  
  cd acme.sh;
  _assertcmd  "./$PROJECT_ENTRY install" || return
  cd ..
  
  _assertexists "$lehome/$PROJECT_ENTRY" || return
  _assertequals "0 0 * * * \"$lehome\"/$PROJECT_ENTRY --cron --home \"$lehome\" > /dev/null"  "$(crontab -l | grep $PROJECT_ENTRY)" || return
  _assertcmd "$lehome/$PROJECT_ENTRY uninstall  > /dev/null" ||  return
}

le_test_uninstall() {
  lehome="$Default_Home"
  cd acme.sh;
  _assertcmd  "./$PROJECT_ENTRY install" || return
  cd ..
  _assertcmd "$lehome/$PROJECT_ENTRY uninstall" ||  return
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
  _assertcmd "./$PROJECT_ENTRY install" ||  return
  LE_WORKING_DIR=""
  cd ..
  
  _assertexists "$lehome/$PROJECT_ENTRY" ||  return
  _assertequals "0 0 * * * \"$lehome\"/$PROJECT_ENTRY --cron --home \"$lehome\" > /dev/null"  "$(crontab -l | grep $PROJECT_ENTRY)" ||  return
  _assertcmd "$lehome/$PROJECT_ENTRY uninstall" ||  return
}

le_test_uninstalltodir() {
  lehome="$HOME/myle"
  
  if [ -d $lehome ] ; then
    rm -rf $lehome
  fi
  
  cd acme.sh;
  LE_WORKING_DIR=$lehome
  export LE_WORKING_DIR
  _assertcmd "./$PROJECT_ENTRY install" ||  return
  LE_WORKING_DIR=""
  cd ..
  
  _assertcmd "$lehome/$PROJECT_ENTRY uninstall" ||  return
  _assertnotexists "$lehome/$PROJECT_ENTRY" ||  return
  _assertequals "" "$(crontab -l | grep $PROJECT_ENTRY)" ||  return

}

#
le_test_standandalone_renew() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  
  lehome="$Default_Home"

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
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain" ||  return
  sleep 5
  _assertcmd "FORCE=1 $lehome/$PROJECT_ENTRY renew $TestingDomain" ||  return

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi  
  

}


#
le_test_standandalone_renew_v2() {
  lehome="$Default_Home"

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
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain --standalone --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
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
  
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


#
le_test_standandalone_renew_localaddress_v2() {

  lehome="$Default_Home"

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
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain --standalone --local-address 0.0.0.0 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
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
  
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}


#
le_test_standandalone_listen_v4_v2() {
  lehome="$Default_Home"

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
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain --standalone --listen-v4 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
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
    _info "Skip"
    return 0
  fi

  lehome="$Default_Home"

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
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain --standalone --listen-v6 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
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
  
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

#
le_test_standandalone_deactivate_v2() {
  lehome="$Default_Home"

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
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain --standalone --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain/fullchain.cer" "$full" ||  return
  
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


#
le_test_standandalone() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  
  lehome="$Default_Home"

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
  
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain" ||  return
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

le_test_standandalone_SAN() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  lehome="$Default_Home"

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
  
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain $TestingAltDomains" ||  return
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi
  
  
}

le_test_standandalone_ECDSA_256() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  lehome="$Default_Home"

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
 
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain no ec-256" ||  return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$CA" || return
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi
  
  

}

le_test_standandalone_ECDSA_256_renew() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  lehome="$Default_Home"

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
  
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain no ec-256" ||  return
  sleep 5
  _assertcmd "FORCE=1 $lehome/$PROJECT_ENTRY renew $TestingDomain" ||  return

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi
  

}


le_test_standandalone_ECDSA_256_SAN_renew() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  lehome="$Default_Home"

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
  
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain $TestingAltDomains ec-256" ||  return
  sleep 5
  _assertcmd "FORCE=1 $lehome/$PROJECT_ENTRY renew $TestingDomain" ||  return

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

le_test_standandalone_ECDSA_256_SAN_renew_v2() {
  lehome="$Default_Home"

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
  
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain -d $TestingAltDomains --standalone --keylength ec-256 --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/fullchain.cer" "$full" ||  return
  
  sleep 5
  
  rm -rf "$certdir"
  mkdir -p "$certdir"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --renew --ecc -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$CA" || return
  
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$cert" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.key" "$key" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$TestingDomain$ECC_SUFFIX/fullchain.cer" "$full" ||  return
  
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

le_test_standandalone_ECDSA_384() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  lehome="$Default_Home"

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
  
  _assertcmd "$lehome/$PROJECT_ENTRY issue no $TestingDomain no ec-384" ||  return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain$ECC_SUFFIX/ca.cer" "$CA" || return
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi


}

le_test_standandalone_tls_renew_SAN_v2() {
  #test  standalone and tls hybrid mode.
  
  lehome="$Default_Home"

  lp=`_ss | grep ':443 '`
  if [ "$lp" ] ; then
    __fail "443 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain --tls  -d $TestingAltDomains --standalone " ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  
  lp=`_ss | grep ':443 '`
  if [ "$lp" ] ; then
    __fail "443 port is not released: $lp"
    return 1
  fi

}

le_test_tls_renew_SAN_v2() {
  if [ "$QUICK_TEST" ] ; then
    _info "Skip by QUICK_TEST"
    return 0
  fi
  
  lehome="$Default_Home"

  lp=`_ss | grep ':443 '`
  if [ "$lp" ] ; then
    __fail "443 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  rm -rf "$lehome/$TestingDomain"
  
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $TestingDomain -d $TestingAltDomains --tls" ||  return
  sleep 5
  _assertcmd "$lehome/$PROJECT_ENTRY --renew -d $TestingDomain --force" ||  return
  
  _assertcert "$lehome/$TestingDomain/$TestingDomain.cer" "$TestingDomain" "$CA" || return
  _assertcert "$lehome/$TestingDomain/ca.cer" "$CA" || return
  
  lp=`_ss | grep ':443 '`
  if [ "$lp" ] ; then
    __fail "443 port is not released: $lp"
    return 1
  fi

}



#
le_test_standandalone_renew_idn_v2() {
  lehome="$Default_Home"

  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is already used."
    return 1
  fi
  
  if [ -z "$TestingDomain" ] ; then
    __fail "Please define TestingDomain and try again."
    return 1
  fi

  _test_idn="中$TestingDomain"
  rm -rf "$lehome/$_test_idn"
  
  certdir="$(pwd)/certs"
  mkdir -p "$certdir"
  cert="$certdir/domain.cer"
  key="$certdir/domain.key"
  ca="$certdir/ca.cer"
  full="$certdir/full.cer"
  _assertcmd "$lehome/$PROJECT_ENTRY --issue -d $_test_idn --standalone --certpath '$cert' --keypath '$key'  --capath '$ca'  --reloadcmd 'echo this is reload'  --fullchainpath  '$full'" ||  return
  
  _assertfileequals "$lehome/$_test_idn/$_test_idn.cer" "$cert" ||  return
  _assertfileequals "$lehome/$_test_idn/$_test_idn.key" "$key" ||  return
  _assertfileequals "$lehome/$_test_idn/ca.cer" "$ca" ||  return
  _assertfileequals "$lehome/$_test_idn/fullchain.cer" "$full" ||  return
  
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
  
  rm -rf "$certdir"
  
  lp=`_ss | grep ':80 '`
  if [ "$lp" ] ; then
    __fail "80 port is not released: $lp"
    return 1
  fi

}

#####################################

if [ "$1" ] ; then
  CASE="$1"
fi

_setup

_ret=0

total=$(grep ^le_test_  $FILE_NAME | wc -l | tr -d ' ')
num=1
for t in $(grep ^le_test_  $FILE_NAME | cut -d '(' -f 1) 
do
  if [ -z "$CASE" ] ; then
    __green "Progress: $num/$total"
    printf "\n"
    num=$(_math $num + 1)
  fi
  _rr=0
  _debug t "$t"
  if [ -z "$CASE" ] || [ "$CASE" = "$t" ] ; then
    _run "$t"
    _rr="$?"
    _debug "_rr" "$_rr"
    _ret=$(_math $_ret + $_rr)
    _debug _ret "$_ret"
  fi

  if [ "$_ret" != "0" ] ; then
    if [ "$DEBUG" ] || [ "$DEBUGING" ] ; then 
      break;
    fi
  fi
  if [ "$CASE" = "$t" ] ; then
    break;
  fi
done

exit $_ret

