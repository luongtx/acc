#!/system/bin/sh
# acca: acc for front-ends (faster and more efficient than acc)
# © 2020, VR25 (xda-developers)
# License: GPLv3+


daemon_ctrl() {
  case "${1-}" in
    start|restart)
      exec /dev/accd $config
    ;;
    stop)
      . ./release-lock.sh
      exit 0
    ;;
    *)
      flock -n 0 <>$TMPDIR/acc.lock && exit 9 || exit 0
    ;;
  esac
}


set -eu
cd /data/adb/acc/
export TMPDIR=/dev/.acc verbose=false
. ./setup-busybox.sh

config=/data/adb/acc-data/config.txt
defaultConfig=$PWD/default-config.txt

mkdir -p ${config%/*}
[ -f $config ] || cp $defaultConfig $config

# config backup
! [ -d /data/media/0/?ndroid -a $config -nt /data/media/0/.acc-config-backup.txt ] \
  || cp -f $config /data/media/0/.acc-config-backup.txt

# custom config path
case "${1-}" in
  */*)
    [ -f $1 ] || cp $config $1
    config=$1
    shift
  ;;
esac


case "$@" in

  # check daemon status
  -D*|--daemon*)
    daemon_ctrl ${2-}
  ;;

  # print battery uevent data
  -i*|--info*)
    cd /sys/class/power_supply/
    for batt in $(ls */uevent); do
      chmod u+r $batt \
         && grep -q '^POWER_SUPPLY_CAPACITY=' $batt \
         && grep -q '^POWER_SUPPLY_STATUS=' $batt \
         && batt=${batt%/*} && break
    done 2>/dev/null || :
    . /data/adb/acc/batt-info.sh
    batt_info "${2-}"
    exit 0
  ;;


  # set multiple properties
  -s\ *=*|--set\ *=*)

    ${async:-false} || {
      async=true setsid $0 "$@" > /dev/null 2>&1 < /dev/null
      exit 0
    }

    set +o sh 2>/dev/null || :
    exec 4<>$0
    flock 0 <&4
    shift

    # since this runs asynchronously, restarting accd from here is potentially troublesome
    # the front-end itself should do it
    # case "$*" in
    #   s=*|*\ s=*|*charging_switch=*|*sc=*|*shutdown_capacity=*)
    #     ! daemon_ctrl stop > /dev/null || restartDaemon=true
    #     trap 'e=$?; ! ${restartDaemon:-false} || /dev/accd; exit $e' EXIT
    #   ;;
    # esac

    . $defaultConfig
    . $config

    export "$@"

    case "$*" in
      *ab=*|*apply_on_boot=*)
        apply_on_boot
      ;;
    esac

    [ .${mcc-${max_charging_current-x}} == .x ] || {
      . ./set-ch-curr.sh
      set_ch_curr ${mcc:-${max_charging_current:--}} || :
    }

    [ .${mcv-${max_charging_voltage-x}} == .x ] || {
      . ./set-ch-volt.sh
      set_ch_volt ${mcv:-${max_charging_voltage:--}} || :
    }

    . ./write-config.sh
    exit 0
  ;;


  # print default config
  -s\ d*|-s\ --print-default*|--set\ d*|--set\ --print-default*|-sd*)
    [ $1 == -sd ] && shift || shift 2
    . $defaultConfig
    . ./print-config.sh | grep -E "${1:-...}" || :
    exit 0
  ;;

  # print current config
  -s\ p*|-s\ --print|-s\ --print\ *|--set\ p|--set\ --print|--set\ --print\ *|-sp*)
    [ $1 == -sp ] && shift || shift 2
    . $config
    . ./print-config.sh | grep -E "${1:-...}" || :
    exit 0
  ;;

esac


# other acc commands
set +eu
exec /dev/acc $config "$@"
