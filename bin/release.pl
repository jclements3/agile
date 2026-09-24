#!/usr/bin/perl
# release.pl -- package the kit for the target laptop: a zip of the committed tree (no data/, no reports),
# named by version tag or commit, with a SHA-256 beside it. Core Perl + git only.
#
#   perl bin/release.pl              -> release/agile-<tag-or-sha>.zip + .sha256
#   perl bin/release.pl --tag v1.0   -> git tag v1.0 first, then package it
#
# On the target: unzip, then `perl bin/daily.pl init` in a project directory. Verify with
#   sha256sum -c agile-<x>.zip.sha256     (Git Bash has sha256sum)
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use Getopt::Long;
use Digest::SHA qw(sha256_hex);

my %o; GetOptions(\%o, 'tag=s') or exit 2;
my $ROOT = abs_path("$FindBin::Bin/.."); chdir $ROOT or die $!;
if (qx(git status --porcelain) =~ /\S/) { print STDERR "working tree not clean: commit first (a release must be reproducible from a commit)\n"; exit 1 }
if ($o{tag}) { system('git', 'tag', '-a', $o{tag}, '-m', "release $o{tag}") == 0 or die "git tag failed\n" }
my $name = $o{tag} // do { chomp(my $t = qx(git describe --tags --always 2>/dev/null)); $t };
$name =~ s/[^\w.-]/-/g;
mkdir 'release' unless -d 'release';
my $zip = "release/agile-$name.zip";
system('git', 'archive', '--format=zip', '--prefix=agile/', '-o', $zip, 'HEAD') == 0 or die "git archive failed\n";
open my $fh, '<:raw', $zip or die $!; local $/; my $bytes = <$fh>; close $fh;
my $sum = sha256_hex($bytes);
open my $s, '>', "$zip.sha256" or die $!; print $s "$sum  agile-$name.zip\n"; close $s;
printf "wrote %s (%.1f KB)\n%s\n", $zip, length($bytes) / 1024, "$zip.sha256: $sum";
print "contains no data/ (git-ignored) and no reports/. On the target: unzip, sha256sum -c, then perl agile/bin/daily.pl init in a project dir.\n";
