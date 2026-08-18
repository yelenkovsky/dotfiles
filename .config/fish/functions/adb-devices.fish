function adb-devices --description 'List Android USB / network devices seen by adb'
    if not command -q adb
        echo "adb is not installed; run ./secure-install.sh or pacman -S android-tools" >&2
        return 127
    end
    adb devices -l
end
