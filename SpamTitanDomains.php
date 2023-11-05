#!/usr/local/bin/php -q
<?php

// SpamTitan Rest API Interface - rlohman@digitimber.com - 11/5/23
// /var/cpanel/spamtitan/SpamTitanDomains.php

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

function create_domain($domain){
    //echo "DEBUG: Create Domain \n";
	$token = 'CHANGEME';
	$baseurl = 'https://spamtitan.example.com/restapi/domains';  
	$rest = curl_init();  

	// Create the domain
	$CreateDomain = array(
	        "domain" => "$domain",
        	"destination" => "mail.$domain"
	);
	$CurQuery = json_encode($CreateDomain);
	$headers = array(
	    'Accept: application/json',
	    "Authorization: Bearer $token",
	    "Content-Type: application/json",
	    'Content-Length: ' . strlen($CurQuery)
	);
	 curl_setopt($rest,CURLOPT_HTTPHEADER,$headers);  
	 curl_setopt($rest,CURLOPT_SSL_VERIFYPEER, false);  
	 curl_setopt($rest,CURLOPT_RETURNTRANSFER, true);  
	 curl_setopt($rest,CURLOPT_URL,$baseurl);  
	 curl_setopt($rest,CURLOPT_POST, 1);
	 curl_setopt($rest,CURLOPT_POSTFIELDS,$CurQuery);  
	 $response = curl_exec($rest);  
	 curl_close($rest);

	$rest = curl_init();
	$data = array(
        	"qreport_enabled" => "true",
	        "qreport_frequency" => "D",
	        "qreport_contains" => "N"
	);
	$httpQuery = http_build_query($data);
	$headers = array(
	    'Accept: application/json',
	    "Authorization: Bearer $token",
	    'Content-Length: ' . strlen($httpQuery)
	);
	curl_setopt($rest, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($rest, CURLOPT_URL,$baseurl."/$domain/policy");  
	curl_setopt($rest, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($rest, CURLOPT_HEADER, 0);
	curl_setopt($rest, CURLOPT_SSL_VERIFYPEER, false);
	curl_setopt($rest, CURLOPT_CUSTOMREQUEST, "PUT");
	curl_setopt($rest, CURLOPT_POSTFIELDS,$httpQuery);

	$output = curl_exec($rest);
	curl_close($rest);

	$rest = curl_init();
	$data = array(
	        "auth_type" => "imap",
        	"imap" => array( 
			"server" => "mail.$domain",
			"port" => "993",
			"secure" => "true",
			"address_type" => "user@domain")
	);
	$httpQuery = http_build_query($data);
	$headers = array(
	    'Accept: application/json',
	    "Authorization: Bearer $token",
	    'Content-Length: ' . strlen($httpQuery)
	);
	curl_setopt($rest, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($rest, CURLOPT_URL,$baseurl."/$domain/auth");  
	curl_setopt($rest, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($rest, CURLOPT_HEADER, 0);
	curl_setopt($rest, CURLOPT_SSL_VERIFYPEER, false);
	curl_setopt($rest, CURLOPT_CUSTOMREQUEST, "PUT");
	curl_setopt($rest, CURLOPT_POSTFIELDS,$httpQuery);

	$output = curl_exec($rest);
	curl_close($rest);

}
function delete_domain($domain) {
    //echo "DEBUG: Delete Domain \n";
	$token = 'CHANGEME';
	$baseurl = 'https://spamtitan.example.com/restapi/domains';  

	$rest = curl_init();  

	// Find the domain ID
	$headers = array(
	    'Accept: application/json',
	    "Authorization: Bearer $token",
	    "Content-Type: application/json"
	);
	 curl_setopt($rest,CURLOPT_HTTPHEADER,$headers);  
	 curl_setopt($rest,CURLOPT_SSL_VERIFYPEER, false);  
	 curl_setopt($rest,CURLOPT_RETURNTRANSFER, true);  
	 curl_setopt($rest,CURLOPT_URL,$baseurl."/$domain");  
	 $response = curl_exec($rest);  
	 $data = json_decode($response, true);
	 curl_close($rest);

	$rest = curl_init();
	$headers = array(
	    'Accept: application/json',
	    "Authorization: Bearer $token"
	);
	curl_setopt($rest, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($rest, CURLOPT_URL,$baseurl."/".$data['id']);
	curl_setopt($rest, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($rest, CURLOPT_HEADER, 0);
	curl_setopt($rest, CURLOPT_SSL_VERIFYPEER, false);
	curl_setopt($rest, CURLOPT_CUSTOMREQUEST, "DELETE");

	$output = curl_exec($rest);
	curl_close($rest);
}


function acctadd($input) {
	$curDomain = $input['data']['domain'];		
	echo "Creating domain: $curDomain\r\n";
	create_domain($curDomain);
	return array(0, "OK");
}
function acctremove($input) {
	$curUser = $input['data']['user'];		
	echo "Removing Account: $curUser\r\n";

        exec("uapi --output=jsonpretty --user=$curUser DomainInfo list_domains", $output);
        $output = json_decode(implode("\n", $output));
        $data = $output->result->data;
        echo "Deleting: " . $data->main_domain . "\r\n";
	delete_domain($data->main_domain);
        for ($i=0;$i<sizeof($data->parked_domains);$i++) {
                echo "Deleting: " . $data->parked_domains[$i] . "\r\n";
		delete_domain($data->parked_domains[$i]);
        }
        for ($i=0;$i<sizeof($data->addon_domains);$i++) {
                echo "Deleting: " . $data->addon_domains[$i] . "\r\n";
		delete_domain($data->addon_domains[$i]);
        }

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

function checkmx($input) {
	$checkmx = "local"; // Set the variable to start
	if ($input['data']['args']['mxcheck'] == "auto") {
		$checkmx = $input['data']['output'][0]['detected'];
	} else if ($input['data']['args']['mxcheck'] == "secondary") {
		$checkmx = "local";
	} else {
		$checkmx = $input['data']['args']['mxcheck'];
	}
	echo "CheckMX: Setting ". $input['data']['args']['domain']." to $checkmx\r\n";
	if ($checkmx == "local") {
		create_domain($input['data']['args']['domain']);
	} else {
		delete_domain($input['data']['args']['domain']);
	}
	return array(0, "OK");
}
?>
