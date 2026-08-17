function cpwd --description 'Copy the current working directory to the clipboard'
    echo -n (pwd) | wl-copy
end