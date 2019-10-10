# cpanel_spamtitan
a SpamTitan Module written to work with cPanel hooks to add domains to the relay list and update validation lists if enabled

be gentle, we're new at this -
  
We created this repo to house our SpamTitan v7 module script(s) to integrate with cPanel v82

After we found SpamTitan, not being heavy coders, we struggled to create proper integration when new customers were signing up, changing MX records, or adding email addresses and/or forwarders

We eventually created something that worked rather well, and we wanted to share it with the world in case there were others in the same boat. 
<hr>
a few disclaimers -
<ul><li>we are not coders</li>
<li>we did not follow proper coding proceedures or documentation (commenting and such)</li>
<li>this script is available as-is, and we take no responsibility for it being compatible or even working with your installations</li></ul>

that being said, we welcome anyone who wants to help us maintain it, or improve it. If you have feature requests, please let us know and we will attempt to add them.

questions, comments, and concerns can be directed to github(@)digitimber.com

Thank you to everyone who contributes to the world wide knowledge base, without you, a lot of us would be lost!
<HR>
  <b>ToDo:</b>
  Create something that resembles debuging option for the log file to show the returned content of the request



Currently tested versions:

SpamTitan v7.05 and cPanel v82.0.16
<HR>
  
<b>How to Install</b>

Copy the STaddEmail.pm to /usr/local/cpanel on your cPanel server using the root user. Edit the file to update the $base_uri on line 19 to include your own spamtitan domain name or ip. Usually something like spamtitan.mycompany.com is what they suggest you create after signup.

To integrate it into the system, run:

/usr/local/cpanel/bin/manage_hooks add module STaddEmail

Output should be something like:

Added hook for Cpanel::UAPI::Email::add_pop to hooks registry

Added hook for Cpanel::UAPI::Email::delete_pop to hooks registry

Added hook for Cpanel::UAPI::Email::add_forwarder to hooks registry

etc



To remove it from your installation:

/usr/local/cpanel/bin/manage_hooks del module STaddEmail

Output should be something like:

Deleted hook STaddEmail::addemail for Cpanel::UAPI::Email::add_pop in hooks registry

Deleted hook STaddEmail::deleteemail for Cpanel::UAPI::Email::delete_pop in hooks registry

Deleted hook STaddEmail::addforwarder for Cpanel::UAPI::Email::add_forwarder in hooks registry

etc



To verify if it's working - while running:

tail -f /usr/local/cpanel/logs/error_log

Create a new account, add an alias domain / addon domain, or create an email or forwarder and you should see log output resembling that 
of the code.




