#!/usr/local/bin/php -q
<?php

// SpamTitan Rest API Interface - github@digitimber.com - 11/5/23
// File Location: /var/cpanel/spamtitan/SpamTitanDomains.php

// Configuration: Please update accordingly
    $token = 'CHANGEME';
    $baseurl = 'https://spamtitan.example.com/restapi/domains';  

// Any switches passed to this script invoke different function calls. Describe section is handled automatically by hook_manager
$switches = (count($argv) > 1) ? $argv : array();

// Argument evaluation.
if (in_array('--describe', $switches)) {
    echo json_encode( describe() );
    exit;
} elseif (in_array('--createaccount', $switches)) {
    list($status, $msg) = acctadd(get_passed_data());
    echo "$status $msg";
    exit;
} elseif (in_array('--removeaccount', $switches)) {
    list($status, $msg) = acctremove(get_passed_data());
    echo "$status $msg";
    exit;
} elseif (in_array('--domainpark', $switches)) {
    list($status, $msg) = park(get_passed_data());
    echo "$status $msg";
    exit;
} elseif (in_array('--domainunpark', $switches)) {
    list($status, $msg) = unpark(get_passed_data());
    echo "$status $msg";
    exit;
} elseif (in_array('--checkmx', $switches)) {
    list($status, $msg) = checkmx(get_passed_data());
    echo "$status $msg";
    exit;
} else {
    echo "0 SpamTitanDomains.php needs a valid switch to run (try --describe)";
    exit(1);
}

function describe() {
    $my_createaccount = array(
        'category' => 'Whostmgr',
        'event'    => 'Accounts::Create',
        'stage'    => 'post',
        'hook'     => '/var/cpanel/spamtitan/SpamTitanDomains.php --createaccount',
        'exectype' => 'script',
    );
    $my_parkdomain = array(
        'category' => 'Whostmgr',
        'event'    => 'Domain::park',
        'stage'    => 'post',
        'hook'     => '/var/cpanel/spamtitan/SpamTitanDomains.php --domainpark',
        'exectype' => 'script',
    );
    $my_removeaccount = array(
        'blocking' => 1,
        'category' => 'Whostmgr',
        'event'    => 'Accounts::Remove',
        'stage'    => 'pre',
        'hook'     => '/var/cpanel/spamtitan/SpamTitanDomains.php --removeaccount',
        'exectype' => 'script',
    );
    $my_unparkdomain = array(
        'blocking' => 1,
        'category' => 'Whostmgr',
        'event'    => 'Domain::unpark',
        'stage'    => 'pre',
        'hook'     => '/var/cpanel/spamtitan/SpamTitanDomains.php --domainunpark',
        'exectype' => 'script',
    );
    $my_checkmx = array(
        'category' => 'Cpanel',
        'event'    => 'Api2::Email::setmxcheck',
        'stage'    => 'post',
        'hook'     => '/var/cpanel/spamtitan/SpamTitanDomains.php --checkmx',
        'exectype' => 'script',
    );
    return array($my_createaccount, $my_parkdomain, $my_removeaccount, $my_unparkdomain, $my_checkmx);
}


// Process data from STDIN
function get_passed_data() {

    // Get input from STDIN.
    $raw_data = '';
    $stdin_fh = fopen('php://stdin', 'r');
    if ( is_resource($stdin_fh) ) {
        stream_set_blocking($stdin_fh, 0);
        while ( ($line = fgets( $stdin_fh, 1024 )) !== false ) {
            $raw_data .= trim($line);
        }
        fclose($stdin_fh);
    }

    // Process and JSON-decode the raw output.
    if ($raw_data) {
        $input_data = json_decode($raw_data, true);
    } else {
        $input_data = array('context'=>array(),'data'=>array(), 'hook'=>array());
    }

    // Return the output.
    return $input_data;
}

// Create the domain on the SpamTitan Appliance and setup a policy and auth method (Send daily reports and IMAPS auth)
function create_domain($domain) {

    global $token, $baseurl;

    // Create the domain data
    $domainData = [
        "domain" => $domain,
        "destination" => "mail.$domain"
    ];

    // Initialize a cURL session
    $ch = curl_init();

    // Step 1: Create the domain
    // Set cURL options for POST request
    $postOptions = [
        CURLOPT_URL => $baseurl,
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            "Authorization: Bearer $token",
            "Content-Type: application/json",
        ],
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($domainData),
    ];
    curl_setopt_array($ch, $postOptions);

    // Execute the cURL request and close the session
    $response = curl_exec($ch);
    curl_close($ch);

    // Step 2: Configure quarantine reports
    $ch = curl_init();
    $qreportData = [
        "qreport_enabled" => "true",
        "qreport_frequency" => "D",
        "qreport_contains" => "N",
    ];

    // Set cURL options for a PUT request
    $putOptions = [
        CURLOPT_URL => "$baseurl/$domain/policy",
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            "Authorization: Bearer $token",
        ],
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_CUSTOMREQUEST => "PUT",
        CURLOPT_POSTFIELDS => http_build_query($qreportData),
    ];
    curl_setopt_array($ch, $putOptions);

    $output = curl_exec($ch);
    curl_close($ch);

    // Step 3: Configure authentication settings
    $ch = curl_init();
    $authData = [
        "auth_type" => "imap",
        "imap" => [
            "server" => "mail.$domain",
            "port" => "993",
            "secure" => "true",
            "address_type" => "user@domain",
        ],
    ];

    // Set cURL options for a PUT request
    $putOptions = [
        CURLOPT_URL => "$baseurl/$domain/auth",
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            "Authorization: Bearer $token",
        ],
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_CUSTOMREQUEST => "PUT",
        CURLOPT_POSTFIELDS => http_build_query($authData),
    ];
    curl_setopt_array($ch, $putOptions);

    $output = curl_exec($ch);
    curl_close($ch);

    // End of the code
}

// Remove domain from SpamTitan Appliance
function delete_domain($domain) {
    global $token, $baseurl;

    // Initialize a cURL session
    $ch = curl_init();

    // Step 1: Find the domain ID
    // Set cURL options for GET request
    $getOptions = [
        CURLOPT_URL => "$baseurl/$domain",
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            "Authorization: Bearer $token",
            "Content-Type: application/json",
        ],
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_RETURNTRANSFER => true,
    ];
    curl_setopt_array($ch, $getOptions);

    // Execute the cURL request and get the response
    $response = curl_exec($ch);
    $data = json_decode($response, true);
    curl_close($ch);

    // Step 2: Delete the domain using the retrieved domain ID
    $ch = curl_init();

    // Set cURL options for DELETE request
    $deleteOptions = [
        CURLOPT_URL => "$baseurl/{$data['id']}",
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            "Authorization: Bearer $token",
        ],
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_CUSTOMREQUEST => "DELETE",
    ];
    curl_setopt_array($ch, $deleteOptions);

    // Execute the cURL request and close the session
    $output = curl_exec($ch);
    curl_close($ch);

    // End of the code
}


function acctadd($input) {
	$curDomain = $input['data']['domain'];		
	echo "Creating domain: $curDomain\r\n";
	create_domain($curDomain);
	return array(0, "OK");
}
// Function to remove an account and associated domains
function acctremove($input) {
    // Get the current user to remove
    $curUser = $input['data']['user'];    
    echo "Removing Account: $curUser\r\n";

    // Use uapi to list the domains associated with the user
    exec("uapi --output=jsonpretty --user=$curUser DomainInfo list_domains", $output);
    $output = json_decode(implode("\n", $output));
    $data = $output->result->data;

    // Delete the main domain
    echo "Deleting: " . $data->main_domain . "\r\n";
    delete_domain($data->main_domain);

    // Delete parked domains
    for ($i = 0; $i < sizeof($data->parked_domains); $i++) {
        echo "Deleting: " . $data->parked_domains[$i] . "\r\n";
        delete_domain($data->parked_domains[$i]);
    }

    // Delete addon domains
    for ($i = 0; $i < sizeof($data->addon_domains); $i++) {
        echo "Deleting: " . $data->addon_domains[$i] . "\r\n";
        delete_domain($data->addon_domains[$i]);
    }

    // Return a status array
    return array(0, "OK");
}

function park($input) {
	$curDomain = $input['data']['new_domain'];		
	echo "Creating domain: $curDomain\r\n";
	create_domain($curDomain);
	return array(0, "OK");
}

function unpark($input) {
	$curDomain = $input['data']['domain'];
	echo "Deleting domain: $curDomain\r\n";
	delete_domain($curDomain);
	return array(0, "OK");
}

// Function to check and modify MX settings for a domain
function checkmx($input) {
    // Set the default value for $checkmx to "local"
    $checkmx = "local";

    // Check the value of 'mxcheck' from input
    if ($input['data']['args']['mxcheck'] == "auto") {
        // If 'mxcheck' is "auto", need to set the detected value from another data point, should be 'remote' or 'local'
        $checkmx = $input['data']['output'][0]['detected'];
    } elseif ($input['data']['args']['mxcheck'] == "secondary") {
        // If 'mxcheck' is "secondary", set $checkmx to "local"
        $checkmx = "local";
    } else {
        // If 'mxcheck' has a custom value (should be 'remote' or 'local'), use that value for $checkmx
        $checkmx = $input['data']['args']['mxcheck'];
    }

    // Output a message indicating the setting change
    echo "CheckMX: Setting " . $input['data']['args']['domain'] . " to $checkmx\r\n";

    // Check the value of $checkmx and perform corresponding actions
    if ($checkmx == "local") {
        // If $checkmx is "local", create the domain
        create_domain($input['data']['args']['domain']);
    } else {
        // If $checkmx is not "local", delete the domain
        delete_domain($input['data']['args']['domain']);
    }

    // Return a status array
    return array(0, "OK");
}
?>
