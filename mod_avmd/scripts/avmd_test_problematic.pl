#!/usr/bin/perl -w


#brief      Test module avmd by calling all voicemails available
#           in avmd test suite and print detection results to the console.
#author     Piotr Gregor <piotrgregor@rsyncme.org>
#details    If you are testing serving voicemails from dialplan then avmd
#           must be set to inbound mode, either globally (by avmd set inbound
#           in fs_cli) or in dialplan settings (<action application="avmd_start"
#           data="inbound_channel=1,outbound_channel=0").
#date       15 Sept 2016 03:00 PM


$|++;   # turn on autoflush
use strict;
use warnings;
require ESL;
use POSIX;
use Time::HiRes;


# Hashtable of <destination number : test result expectation> pairs
my %numbers = (
    840531400 => "DETECTED",    # obscure voicemails, mode AVMD_DETECT_BOTH
    840531401 => "DETECTED",
    840531402 => "DETECTED",
    840531403 => "DETECTED",
    840531404 => "DETECTED",
    840531405 => "DETECTED",
    840531000 => "DETECTED",    # obscure voicemails, mode AVMD_DETECT_BOTH
    840531001 => "DETECTED",
    840531002 => "DETECTED",
    840531003 => "DETECTED",
    840531004 => "DETECTED",
    840531005 => "DETECTED",
    840531006 => "DETECTED",
    840531007 => "DETECTED",
    840531008 => "DETECTED",
    840531009 => "DETECTED",
    840531010 => "DETECTED",
    840531011 => "DETECTED",
    840531012 => "DETECTED",
    840531013 => "DETECTED",
    840531014 => "DETECTED",
    840531200 => "DETECTED",    # obscure voicemails, mode AVMD_DETECT_FREQ
    840531201 => "DETECTED",
    840531202 => "DETECTED",
    840531203 => "DETECTED",
    840531204 => "DETECTED",
    840531205 => "DETECTED",
    840531206 => "DETECTED",
    840531207 => "DETECTED",
    840531208 => "DETECTED",
    840531209 => "DETECTED",
    840531210 => "DETECTED",
    840531211 => "DETECTED",
    840531212 => "DETECTED",
    840531213 => "DETECTED",
    840531214 => "DETECTED",
);

my $host = "127.0.0.1";
my $port = "8021";
my $pass = "ClueCon";
my $extension_base = "sofia/internal/1000\@192.168.1.60";

my $playback = 'local_stream://moh';
my $context = 'default'; 
my $endpoint;
my $dest;
my $expectation;
my $callerid;
my $passed = 0;
my $failed = 0;
my $hanguped = 0;


if ($#ARGV + 1 eq 1) {
    $callerid = $ARGV[0];
    print "\nDialing as [" .$callerid ."]\n";
} elsif ($#ARGV + 1 > 1) {
    die "Please specify single caller id.\n";
} else {
    die "Please specify caller id.\n";
}


print "Connecting...\t";
my $con  = new ESL::ESLconnection($host, $port, $pass);
if (!$con) {
    die "Unable to establish connection to $host:$port\n";
}
if ($con->connected()) {
    print "OK.\n";
} else {
    die "Connection failure.\n";
}

print "Subscribing to avmd events...\t";
$con->events("plain", "CUSTOM avmd::start");
$con->events("plain", "CUSTOM avmd::stop");
$con->events("plain", "CUSTOM avmd::beep");
$con->events("plain", "CHANNEL_CALLSTATE");
$con->events("plain", "CHANNEL_HANGUP");
print "OK.\n\n";
printf("\nRunning [" .keys(%numbers) ."] tests.\n\n");

printf("outbound uuid | destination number | timestamp | expectation | test result | freq | variance\n\n");
foreach $dest (sort keys %numbers) {
    if (!$con->connected()) {
        last;
    }
    $expectation = $numbers{$dest};
    test_once($dest, $callerid, $expectation);
}
print "Disconnected.\n\n";
if (($failed == 0) && ($hanguped == 0)) {
    printf("\n\nOK. All PASS [%s]\n\n", $passed);
} else {
    printf("PASS [%s], FAIL [%s], HANGUP [%s]\n\n", $passed, $failed, $hanguped);
}

sub test_once {
    my ($dest, $callerid, $expectation) = @_;
    my $originate_string =
    'originate ' .
    '{ignore_early_media=true,' .
    'origination_uuid=%s,' . 
    'originate_timeout=60,' .
    'origination_caller_id_number=' . $callerid . ',' .
    'origination_caller_id_name=' . $callerid . '}';
    my $outcome = "";
    my $result = "";
    my $event_uuid = "N/A";
    my $uuid_in = "";
    my $freq = "N/A";
    my $freq_var = "N/A";

    if(defined($endpoint)) {
        $originate_string .= $endpoint;
    } else {
        $originate_string .= 'loopback/' . $dest . '/' . $context;
    }
    $originate_string .=  ' ' . '&playback(' . $playback . ')';

    my $uuid_out = $con->api('create_uuid')->getBody();
    my ($time_epoch, $time_hires) = Time::HiRes::gettimeofday();

    printf("[%s] [%s]", $uuid_out, $dest);
    $con->bgapi(sprintf($originate_string, $uuid_out));

    while($con->connected()) {
        my $e = $con->recvEvent();
        if ($e) {
            my $event_name = $e->getHeader("Event-Name");
            if ($event_name eq 'CUSTOM') {
                my $avmd_event_type = $e->getHeader("Event-Subclass");
                if ($avmd_event_type eq 'avmd::start') {
                    $uuid_in = $e->getHeader("Unique-ID");
                } elsif (!($uuid_in eq "") && (($avmd_event_type eq 'avmd::beep') || ($avmd_event_type eq 'avmd::stop'))) {
                    $event_uuid = $e->getHeader("Unique-ID");
                    if ($event_uuid eq $uuid_in) {
                        if ($avmd_event_type eq 'avmd::beep') {
                            $freq = $e->getHeader("Frequency");
                            $freq_var = $e->getHeader("Frequency-variance");
                        }
                        $outcome = $e->getHeader("Beep-Status");
                        if ($outcome eq $expectation) {
                            $result = "PASS";
                            $passed++;
                        } else {
                            $result = "FAIL";
                            $failed++;
                        }
                        last;
                    }
                }
            } elsif ($event_name eq 'CHANNEL_HANGUP') {
                $event_uuid = $e->getHeader("variable_origination_uuid");
                if ((defined $event_uuid) && ($event_uuid eq $uuid_out)) {
                    $outcome = "HANGUP";
                    $result = "HANGUP";
                    $hanguped++;
                    last;
                }
            }
        }
    }
    printf("\t[%s]\t[%s]\t\t[%s]\t[%s]HZ\t[%s]\n", POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime($time_epoch)), $expectation, $result, $freq, $freq_var);
    Time::HiRes::sleep(0.5);    # avoid switch_core_session.c:2265 Throttle Error! 33, switch_time.c:1227 Over Session Rate of 30!
}
