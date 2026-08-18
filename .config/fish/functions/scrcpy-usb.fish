function scrcpy-usb --description 'Mirror the USB-attached Android device with scrcpy'
    if not command -q scrcpy
        echo "scrcpy is not installed; run ./secure-install.sh or pacman -S scrcpy" >&2
        return 127
    end
    scrcpy $argv
end
