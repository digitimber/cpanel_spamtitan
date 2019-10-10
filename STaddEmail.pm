# Created 8/14/2019 to add and remove listed valid emails to SpamTitan when the customers add and remove email boxes and forwarders.
# Updated 10/10/19 to add/remove domain based on local/remote mail exchanger, add/remove of alias/addon domain, and creation/termination of account

package STaddEmail;

# Return errors if Perl experiences problems.
use strict;
use warnings;

# Properly decode JSON.
use JSON;
use Cpanel::Logger;
use LWP::Simple;
use Cpanel::AcctUtils::Domain ();


# Instantiate the cPanel logging object.
my $logger = Cpanel::Logger->new();
my $base_uri = 'https://<your_spamtitan_domain/api/domain.php';

# Embed hook attributes alongside the action code.
sub describe {
    my $my_add = [
    {
        'category' => 'Cpanel',
        'event'    => 'UAPI::Email::add_pop',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::addemail',
    },{
        'category' => 'Cpanel',
        'event'    => 'UAPI::Email::delete_pop',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::deleteemail',
    },{
        'category' => 'Cpanel',
        'event'    => 'UAPI::Email::add_forwarder',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::addforwarder',
    },{
        'category' => 'Cpanel',
        'event'    => 'UAPI::Email::delete_forwarder',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::deleteforwarder',
    },{
        'category' => 'Cpanel',
        'event'    => 'Api2::Email::setmxcheck',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::checkmx',
    },{
        'category' => 'Whostmgr',
        'event'    => 'Accounts::Create',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::createdomain',
    },{
        'category' => 'Whostmgr',
        'event'    => 'Accounts::Remove',
        'stage'    => 'pre',
        'hook'     => 'STaddEmail::deletedomain',
    },{
        'category' => 'Whostmgr',
        'event'    => 'Domain::park',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::parkdomain',
    },{
        'category' => 'Whostmgr',
        'event'    => 'Domain::unpark',
        'stage'    => 'post',
        'hook'     => 'STaddEmail::unparkdomain',
    }];
    return $my_add ;
};

sub createdomain {
    my ( $context, $data ) = @_;
    my $curdomain = $data->{domain};
    $logger->info("SpamTitan: Adding domain $curdomain to relay (new account)");
    my $contents = get("$base_uri?name=$curdomain&server=mail.$curdomain&method=add");
};
sub unparkdomain {
    my ( $context, $data ) = @_;
    my $curdomain = $data->{domain};
    $logger->info("SpamTitan: Removing domain $curdomain from relay (domain was unparked)");
    my $contents = get("$base_uri?name=$curdomain&method=delete");
};
sub parkdomain {
    my ( $context, $data ) = @_;
    my $curdomain = $data->{new_domain};
    $logger->info("SpamTitan: Adding domain $curdomain to relay (domain was parked)");
    my $contents = get("$base_uri?name=$curdomain&server=mail.$curdomain&method=add");
};
sub deletedomain {
    my ( $context, $data ) = @_;
    my $user = $data->{user};
    my $curdomain = Cpanel::AcctUtils::Domain::getdomain( $user );
    $logger->info("SpamTitan: Removing domain $curdomain from relay (deleted account)");
    my $contents = get("$base_uri?name=$curdomain&method=delete");
};
sub checkmx {
    my ( $context, $data ) = @_;
    my $mxremote = $data->{output}->[0]->{remote};
    my $mxdomain = $data->{args}->{domain};
    if ($mxremote == 1) {
        $logger->info("SpamTitan: Removing domain $mxdomain from relay (mx changed to remote)");
        my $contents = get("$base_uri?name=$mxdomain&method=delete");
    } else {
        $logger->info("SpamTitan: Adding domain $mxdomain to relay (mx changed to local)");
        my $contents = get("$base_uri?name=$mxdomain&server=mail.$mxdomain&method=add");
    }
};
sub addforwarder {
    my ( $context, $data ) = @_;
    my $emailaddress = $data->{result}->[0]->{email};
    my ($before_at, $after_at) = split('@',$emailaddress);
    $logger->info("SpamTitan: Created forwarder for $emailaddress at $after_at");
    my $contents = get("$base_uri?name=$after_at&email=$emailaddress&method=edit");
};
sub addemail {
    my ( $context, $data ) = @_;
    my $emailaddress = $data->{result};
    $emailaddress =~ s/\+/\@/g;
    my ($before_at, $after_at) = split('@',$emailaddress);
    $logger->info("SpamTitan: Created email for $emailaddress at $after_at");
    my $contents = get("$base_uri?name=$after_at&email=$emailaddress&method=edit");
};

sub deleteemail {
    my ( $context, $data ) = @_;
    my $emailaddress = $data->{args}->{email};
    my ($before_at, $after_at) = split('@',$emailaddress);
    $logger->info("SpamTitan: Deleted email for $emailaddress at $after_at");
    my $contents = get("$base_uri?name=$after_at&delemail=$emailaddress&method=edit");
};
sub deleteforwarder {
    my ( $context, $data ) = @_;
    my $emailaddress = $data->{args}->{address};
    my ($before_at, $after_at) = split('@',$emailaddress);
    $logger->info("SpamTitan: Deleted forwarder for $emailaddress at $after_at");
    my $contents = get("$base_uri?name=$after_at&delemail=$emailaddress&method=edit");
};

1;
