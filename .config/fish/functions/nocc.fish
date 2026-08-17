function nocc --description 'Run php occ in the Nextcloud app container'
    set -l compose_file /home/xbloc/Respos/nextcloud-cloudflare/dinit_setup/compose.yml

    docker compose -f $compose_file exec -T -u 33 app php $argv
end
