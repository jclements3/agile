#!/usr/bin/perl
# release.pl -- package the kit for the target laptop: a zip of the committed tree (no data/, no reports),
# named by version tag or commit, with a SHA-256 beside it. Core Perl + git only.
#
#   perl bin/release.pl                      -> release/agile-<tag-or-sha>.zip + .sha256
#   perl bin/release.pl --tag v1.0           -> git tag v1.0 first, then package it
#   perl bin/release.pl --profile mbse       -> release/agile-mbse-<tag-or-sha>.zip: only the files that
#                                               tools/gitlab/mbse-release.txt lists (an MBSE DevSecOps team's kit)
#   perl bin/release.pl --profile mbse --list [--worktree]
#                                            -> print the profile's files, one per line, and make nothing
#                                               (--worktree: from the working tree, committed or not)
#
# On the target: unzip, then `perl bin/daily.pl init` in a project directory (the mbse profile: perl
# agile/tools/gitlab/kickoff.pl doctor). Verify with
#   sha256sum -c agile-<x>.zip.sha256     (Git Bash has sha256sum)
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use Getopt::Long;
use Digest::SHA qw(sha256_hex);

my %o; GetOptions(\%o, 'tag=s', 'profile=s', 'list', 'worktree') or exit 2;
my $ROOT = abs_path("$FindBin::Bin/.."); chdir $ROOT or die $!;
if ($o{list} && !$o{profile}) { print STDERR "release: --list needs --profile NAME\n"; exit 2 }
my ($manifest, @spec);
if ($o{profile}) {
    $o{profile} =~ /^[\w-]+$/ or do { print STDERR "release: a profile name is letters, digits, _ and - ('$o{profile}')\n"; exit 2 };
    $manifest = "tools/gitlab/$o{profile}-release.txt";
    open my $mf, '<', $manifest or do { print STDERR "release: no profile '$o{profile}' ($manifest: $!)\n"; exit 2 };
    while (my $l = <$mf>) { $l =~ s/#.*//; $l =~ s/^\s+|\s+$//g; next if $l eq ''; my $opt = $l =~ s/^\?\s*//; push @spec, [$l, $opt] }
    close $mf;
}
sub glob_re { my $g = shift; my $r = join '', map { $_ eq '**' ? '.*' : $_ eq '*' ? '[^/]*' : quotemeta } split /(\*\*|\*)/, $g; qr/^$r$/ }
sub profile_files {                              # (files in the tree) -> the profile's files, sorted; dies on a required line that matches nothing
    my @all = @_;
    my (%keep, @missing);
    for my $s (@spec) {
        my ($pat, $opt) = @$s;
        my $re = glob_re($pat);
        my @m = grep { $_ =~ $re } @all;
        push @missing, $pat if !@m && !$opt;
        $keep{$_} = 1 for @m;
    }
    if (@missing) { print STDERR "release: $manifest names files that are not in the tree: @missing\n"; exit 1 }
    sort keys %keep;
}
if ($o{list}) {
    my @all = split /\n/, $o{worktree} ? qx(git ls-files -c -o --exclude-standard) : qx(git ls-tree -r --name-only HEAD);
    print "$_\n" for profile_files(grep { -f } @all);
    exit 0;
}
if (qx(git status --porcelain) =~ /\S/) { print STDERR "working tree not clean: commit first (a release must be reproducible from a commit)\n"; exit 1 }
if ($o{tag}) { system('git', 'tag', '-a', $o{tag}, '-m', "release $o{tag}") == 0 or die "git tag failed\n" }
my $name = $o{tag} // do { chomp(my $t = qx(git describe --tags --always 2>/dev/null)); $t };
$name =~ s/[^\w.-]/-/g;
mkdir 'release' unless -d 'release';
my $base = $o{profile} ? "agile-$o{profile}-$name" : "agile-$name";
my $zip = "release/$base.zip";
my @paths;
if ($o{profile}) {                               # the manifest's lines as git pathspecs (only those that match: optional ones may not)
    my @all = split /\n/, qx(git ls-tree -r --name-only HEAD);
    my %in = map { $_ => 1 } profile_files(@all);
    @paths = map { ":(glob)$_->[0]" } grep { my $re = glob_re($_->[0]); grep { $_ =~ $re } keys %in } @spec;
}
system('git', 'archive', '--format=zip', '--prefix=agile/', '-o', $zip, 'HEAD', (@paths ? ('--', @paths) : ())) == 0 or die "git archive failed\n";
open my $fh, '<:raw', $zip or die $!; local $/; my $bytes = <$fh>; close $fh;
my $sum = sha256_hex($bytes);
open my $s, '>', "$zip.sha256" or die $!; print $s "$sum  $base.zip\n"; close $s;
printf "wrote %s (%.1f KB)\n%s\n", $zip, length($bytes) / 1024, "$zip.sha256: $sum";
if ($o{profile}) { print "the $o{profile} profile ($manifest). On the target: unzip, sha256sum -c, then perl agile/tools/gitlab/kickoff.pl doctor.\n" }
else { print "contains no data/ (git-ignored) and no reports/. On the target: unzip, sha256sum -c, then perl agile/bin/daily.pl init in a project dir.\n" }
