#!/bin/bash

# SpamTitan Hook Script for cPanel Domain Lifecycle Events
# Author: Russ Lohman
# Created on April 22nd 2025
# Usage: Hooked via manage_hooks with the appropriate --script-args or --manual
# Description: Replacement for PHP/Perl scripts used previously as PHP disabled_function should now include exec, so needed workaround
# Events: Accounts::Create, Accounts::Remove, Domain::park, Domain::unpark, Api2::Email::setmxcheck

# User Editable Fields (domain name) (token)
BASEURL="https://spamtitan.example.com/restapi/domains"
TOKEN="Put Token Here"

------------------ No more editing below here unless you know what you are doing ------------------------
ACTION="$1"
TMPFILE="/tmp/domains_${USER}.json"
STDIN_DATA=$(cat)
CURUSER=$(echo "$STDIN_DATA" | jq -r '.data.user // empty')
CURDOMAIN=$(echo "$STDIN_DATA" | jq -r '.data.domain // .data.new_domain // .data.args.domain // empty')
IS_LOCAL=$(echo "$STDIN_DATA" | jq -r '.data.output[0].local // 0')

function create_domain {
    local domain="$1"
    echo "Function: Creating domain: $domain"
    curl -sk -X POST "$BASEURL" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"domain\":\"$domain\",\"destination\":\"mail.$domain\"}"
    curl -sk -X PUT "$BASEURL/$domain/policy" -H "Authorization: Bearer $TOKEN" --data "qreport_enabled=true&qreport_frequency=D&qreport_contains=N"
    curl -sk -X PUT "$BASEURL/$domain/auth" -H "Authorization: Bearer $TOKEN" --data "auth_type=imap&imap[server]=mail.$domain&imap[port]=993&imap[secure]=true&imap[address_type]=user@domain"
}

function delete_domain {
    local domain="$1"
    echo "Function: Deleting domain: $domain"
    local id=$(curl -sk -H "Authorization: Bearer $TOKEN" "$BASEURL/$domain" | jq -r '.id')
    if [ "$id" != "null" ]; then
        curl -sk -X DELETE -H "Authorization: Bearer $TOKEN" "$BASEURL/$id"
    else
        echo "Domain $domain not found in SpamTitan."
    fi
}

# Handle --describe for manage_hooks auto-registration
if [[ "$1" == "--describe" ]]; then
    echo '[
        {"category":"Whostmgr","event":"Accounts::Create","stage":"post","hook":"'"$0"' createaccount","exectype":"script"},
        {"category":"Whostmgr","event":"Domain::park","stage":"post","hook":"'"$0"' domainpark","exectype":"script"},
        {"category":"Whostmgr","event":"Accounts::Remove","stage":"pre","blocking":1,"hook":"'"$0"' removeaccount","exectype":"script"},
        {"category":"Whostmgr","event":"Domain::unpark","stage":"pre","blocking":1,"hook":"'"$0"' domainunpark","exectype":"script"},
        {"category":"Cpanel","event":"Api2::Email::setmxcheck","stage":"post","hook":"'"$0"' checkmx","exectype":"script"}
    ]'
    exit 0
fi

#echo $@
#echo $STDIN_DATA

case "$ACTION" in
    createaccount)
	echo "Create Account: Current Domain $CURDOMAIN"
        create_domain "$CURDOMAIN"
        ;;

    removeaccount)
	echo "Removing Account $CURUSER"
        uapi --user="$CURUSER" DomainInfo list_domains --output=json > "$TMPFILE"
        if [ ! -s "$TMPFILE" ]; then
            echo "Failed to fetch domain list for $CURUSER"
            echo "0 Failed to fetch domain list"
            exit 1
        fi

        MAIN=$(jq -r '.result.data.main_domain' "$TMPFILE")
        PARKED=$(jq -r '.result.data.parked_domains[]?' "$TMPFILE")
        ADDONS=$(jq -r '.result.data.addon_domains[]?' "$TMPFILE")

        ALL_DOMAINS=("$MAIN" $PARKED $ADDONS)

        for domain in "${ALL_DOMAINS[@]}"; do
	    echo "Deleting Domain: $domain"
            delete_domain "$domain"
        done

        rm -f "$TMPFILE"
        ;;

    domainpark)
	echo "Creating Domain $CURDOMAIN"
        create_domain "$CURDOMAIN"
        ;;

    domainunpark)
	echo "Deleting Domain $CURDOMAIN"
        delete_domain "$CURDOMAIN"
        ;;

    checkmx)
	if [[ "$IS_LOCAL" == "1" ]]; then
	    echo "MX is set to local for $CURDOMAIN — adding domain"
	    create_domain "$CURDOMAIN"
	else
	    echo "MX is set to remote for $CURDOMAIN — removing domain"
	    delete_domain "$CURDOMAIN"
	fi
        ;;

    *)
        echo "Unknown action: $ACTION $CURUSER $CURDOMAIN $MXCHECK"
        exit 1
        ;;
esac

echo "0 OK"
exit 0

