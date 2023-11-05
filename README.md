# New Update 11/5/23
<hr>

With SpamTitan Updating their own code to support a RESTAPI (v3 as of this writing) we have attempted to update our script with the times. We've moved off of Perl and attempted a PHP script this time. 
There were some shortcomings with the old script that this should resolve and just generally be more robust than previous.

Be gentle, we're still new at this and if you would like to make our code better, please do!
  
We updated this repo to house our SpamTitan v8 RESTAPI v3 module script(s) to integrate with cPanel v110

After we found SpamTitan, not being heavy coders, we struggled to create proper integration when new customers were signing up, changing MX records, or cleaning up after termination of accounts.

We eventually created something that worked rather well, and we wanted to share it with the world in case there were others in the same boat. 
<hr>

### A few disclaimers -
<ul><li>we are not coders</li>
<li>we did not follow proper coding procedures or documentation (commenting and such)</li>
<li>this script is available as-is, and we take no responsibility for it being compatible or even working with your installations</li></ul>

We welcome anyone who wants to help us maintain it or improve it. 

Thank you to everyone who contributes to the world wide knowledge base, without you, a lot of us would be lost!
<HR>
  

### Currently tested versions:
SpamTitan v8.00.46 and cPanel v110.0.14

<HR>
  
### How to Install

Create a directory /var/cpanel/spamtitan and copy the SpamTitanDomains.php to /var/cpanel/spamtitan on your cPanel server using the root user. Edit the file to update the $baseurl and $token information using your SpamTitan information. 

To integrate it into the system, run:

>/usr/local/cpanel/bin/manage_hooks add script /var/cpanel/spamtitan/SpamTitanDomains.php

Output should be something like:
<pre>
# /usr/local/cpanel/bin/manage_hooks add script /var/cpanel/spamtitan/SpamTitanDomains.php
Added hook for Whostmgr::Accounts::Create to hooks registry
Added hook for Whostmgr::Domain::park to hooks registry
Added hook for Whostmgr::Accounts::Remove to hooks registry
Added hook for Whostmgr::Domain::unpark to hooks registry
Added hook for Cpanel::Api2::Email::setmxcheck to hooks registry
</pre>
To remove it from your installation:

> /usr/local/cpanel/bin/manage_hooks del script /var/cpanel/spamtitan/SpamTitanDomains.php

Output should be something like:
<pre>
# /usr/local/cpanel/bin/manage_hooks del script /var/cpanel/spamtitan/SpamTitanDomains.php
Deleted hook /var/cpanel/spamtitan/SpamTitanDomains.php --createaccount for Whostmgr::Accounts::Create in hooks registry
Deleted hook /var/cpanel/spamtitan/SpamTitanDomains.php --domainpark for Whostmgr::Domain::park in hooks registry
Deleted hook /var/cpanel/spamtitan/SpamTitanDomains.php --removeaccount for Whostmgr::Accounts::Remove in hooks registry
Deleted hook /var/cpanel/spamtitan/SpamTitanDomains.php --domainunpark for Whostmgr::Domain::unpark in hooks registry
Deleted hook /var/cpanel/spamtitan/SpamTitanDomains.php --checkmx for Cpanel::Api2::Email::setmxcheck in hooks registry
</pre>

To verify if it's working -

> tail -f /usr/local/cpanel/logs/error_log

Create a new account, add an alias domain / addon domain, or change MX routing from local to remote or vise versa and you should see log output resembling that 
of the code.

