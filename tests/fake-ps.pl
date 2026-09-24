#!/usr/bin/perl
# Stand-in for powershell.exe -EncodedCommand: decodes the script, saves it to $FAKE_PS_LOG, prints $FAKE_PS_JSON.
use strict; use warnings; use MIME::Base64 qw(decode_base64); use Encode qw(decode);
my $script = decode('UTF-16LE', decode_base64($ARGV[-1]));
if ($ENV{FAKE_PS_LOG}) { open my $f, '>>', $ENV{FAKE_PS_LOG} or die; print $f "$script\n----\n"; close $f }
exit($ENV{FAKE_PS_RC} // 0) if $ENV{FAKE_PS_RC};
print "\x{EF}\x{BB}\x{BF}Some chatter first\n", $ENV{FAKE_PS_JSON} // '[]', "\n";
