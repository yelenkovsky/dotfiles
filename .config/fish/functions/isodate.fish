function isodate --description 'Display and copy ISO date (YYYY-MM-DD)'
    set -l iso_date (date -I)
    echo $iso_date
    
    # Try to copy to clipboard using available utilities
    if command -q wl-copy
        echo -n $iso_date | wl-copy
    else if command -q xclip
        echo -n $iso_date | xclip -selection clipboard
    else if command -q xsel
        echo -n $iso_date | xsel --clipboard
    else
        echo "Warning: No clipboard utility found (wl-copy, xclip, or xsel)" >&2
        return 1
    end
    
    echo "Copied to clipboard!" >&2
end

