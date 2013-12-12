#! /bin/bash

function cleanup {
  if [ x$EMULATOR_PID != x ]; then
    kill $EMULATOR_PID
  fi
  if [ x$CHROMEDRIVER_PID != x ]; then
    kill $CHROMEDRIVER_PID
  fi
}
trap cleanup EXIT

# Update git submodules
git submodule init
git submodule update

# Set up the android environment
source tools/android/setup.sh

if [ "x$DISPLAY" == x ]; then
  export DISPLAY=:99.0
  /sbin/start-stop-daemon --start --quiet --pidfile /tmp/custom_xvfb_99.pid --make-pidfile --background --exec /usr/bin/Xvfb -- :99 +extension GLX -ac -screen 0 1280x1024x16
  sleep 15
  glxinfo
fi

echo $DISPLAY

while true; do
  # Start up the emulator
  $ADB kill-server
  $ADB start-server
  # Chrome requires a GPU
  $EMULATOR -verbose -gpu on -no-audio -no-boot-anim -partition-size 1024 -no-snapshot-save -wipe-data $EMULATOR_ARGS @Android-Chrome &
  EMULATOR_PID=$!
  $ADB wait-for-device shell true
  while true; do
    BOOTED=$($ADB shell getprop sys.boot_completed | sed -e's/[^0-9]*//g')
    BOOTANIM=$($ADB shell getprop init.svc.bootanim | sed -e's/[^a-zA-Z]*//g')
    echo "Waiting for emulator to boot... Booted? $BOOTED Animation? $BOOTANIM"
    if [ x$BOOTED == x1 -a x$BOOTANIM == xstopped ]; then
      break
    fi
    sleep 5
  done

  # The emulator crashes if you access it too fast :/
  sleep 5

  # Make localhost refer to the host machine, not the emulator.
  # See http://developer.android.com/tools/devices/emulator.html#emulatornetworking
  echo "Redirecting localhost"
  $ADB shell mount -o remount,rw -t yaffs2 /dev/block/mtdblock0 /system
  $ADB shell echo "10.0.2.2 localhost" \> /etc/hosts

  # Install the apk
  echo "Installing Chrome"
  $ADB install $CHROME_APK
  $ADB shell input keyevent 82   # Send the menu key to unlock the screen
  $ADB shell am start -a android.intent.action.MAIN -n $CHROME_APP/.Main  # Start chrome

  if kill -0 $EMULATOR_PID; then
    break
  else
    echo "Emulator has crashed, try to start it again..."
  fi
done

# Start up the chrome driver
echo "Starting ChromeDriver"
echo $CHROMEDRIVER
$CHROMEDRIVER &
CHROMEDRIVER_PID=$!
sleep 5

./run-tests.sh -b Remote --remote-executor http://localhost:9515 --remote-caps="chromeOptions=androidPackage=$CHROME_APP" "$@"
