#!/usr/bin/perl -w
use strict;
use IO::Socket::INET;

my ($hostname, $port) = @ARGV;
exit 2 unless defined($hostname) && defined($port);

my $outdir = $ENV{OPEN_CURTAINS_OUTDIR} || ".";
my $vncsnap = $ENV{VNCSNAPSHOT_BIN}    || "vncsnapshot";

# Nome: ip_porta.jpg  (ex.: 1.2.3.4_5900.jpg)
my $jpg = "$outdir/${hostname}_$port.jpg";

$SIG{ALRM} = sub { print "ERR:$hostname:$port:timeout\n"; exit 1; };

my $client = new IO::Socket::INET(
    PeerHost => $hostname, PeerPort => $port,
    Proto => "tcp", Timeout => 15
) or do { print "ERR:$hostname:$port:connect\n"; exit 1; };

my $data = "";

alarm(15);
$client->recv($data, 512);
if (!defined($data) || $data !~ /^RFB /) {
    print "ERR:$hostname:$port:banner\n"; exit 1;
}
$client->send("RFB 003.003\n");

alarm(15);
$client->recv($data, 512);
my $noauth = (defined($data) && unpack("H*", $data) =~ /00000001/);
$client->close();
alarm(0);

if (!$noauth) {
    print "PASS:$hostname:$port\n";
    exit 0;
}

# Snapshot direto, nome = ip_porta.jpg
my $display = $port - 5900;
system("$vncsnap -vncQuality 7 -quality 70 $hostname:$display '$jpg' >/dev/null 2>&1");

if (-s $jpg) {
    print "OK:$hostname:$port:$jpg\n";
    exit 0;
} else {
    print "ERR:$hostname:$port:snapshot\n";
    exit 1;
}
