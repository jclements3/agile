package Ai;
# Hand the day's structured stand-up data to your AI service and get back a short,
# fixed-format assessment.  Three backends: 'paste' (write the prompt to a file, you paste it into
# its chat UI and paste the reply back — works everywhere), 'curl' (an OpenAI-compatible
# chat endpoint the service exposes; uses the curl bundled with Git for Windows), and
# 'mock' (canned reply for tests).  The prompt carries the banner; only use a service your
# organisation allows for the data's marking.
use strict;
use warnings;
use JSON::PP ();
use Prelude qw(sorted);
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Ai: unknown function '$n'\n" unless defined &{"Ai::$n"};
        *{"${caller}::$n"} = \&{"Ai::$n"};
    }
}

my @SECTIONS = ('HIGHLIGHTS', 'RISKS', 'STUCK', 'QUESTIONS FOR LEADS', 'PROGRESS');

# ---------------------------------------------------------------- prompt
# prompt_pack(date => , sprint_text => , answers => { Team => $answers_report }, flags => { Team => [..] }, history => { Team => $text }, marking => $conf)
sub prompt_pack {
    my %o = @_;
    my $banner = $o{marking} && $o{marking}{banner} ? "$o{marking}{banner}\n\n" : '';
    my $p = $banner . <<"HEAD";
You are assisting a solutions architect who runs daily stand-ups for several scrum teams.
Below are today's ($o{date}) stand-up answers from each team (Y = yesterday, T = today, B = blockers),
the sprint metrics, deterministic flags already computed, and the previous days' answers for context.

Write a concise assessment for the architect. Use EXACTLY these section headings, in this order,
each followed by short bullet lines starting with "- ". Name people and task ids. If a section
has nothing, write "- none". Do not restate the metrics table. No preamble, no closing remarks.

HIGHLIGHTS
RISKS
STUCK
QUESTIONS FOR LEADS
PROGRESS

HIGHLIGHTS: what moved, finished, or was unblocked. RISKS: anything that threatens the sprint
commitment, cross-team dependencies, and blockers, with who owns the next action. STUCK: people
or tasks that show no movement across days or contradict earlier answers. QUESTIONS FOR LEADS:
up to five specific questions the architect should ask today. PROGRESS: one or two sentences per
team on whether the sprint is on track, with a number.

HEAD
    $p .= "=== SPRINT METRICS ===\n$o{sprint_text}\n" if $o{sprint_text};
    for my $team (sorted(keys %{ $o{answers} // {} })) {
        $p .= "=== $team TODAY ===\n$o{answers}{$team}\n";
        my @f = @{ $o{flags}{$team} // [] };
        $p .= "flags (computed):\n" . join('', map { "  $_->{level}: $_->{who}: $_->{text}\n" } @f) . "\n" if @f;
        $p .= "=== $team PREVIOUS DAYS ===\n$o{history}{$team}\n" if $o{history} && $o{history}{$team};
    }
    $p .= "=== NOTES ===\n$o{notes}\n" if $o{notes};
    $p . $banner;
}

# ---------------------------------------------------------------- response
sub parse_response {                          # -> { HIGHLIGHTS => [..], ... } ; tolerant of markdown headings and bullets
    my $text = shift // '';
    $text =~ s/\r//g;
    my (%r, $cur);
    for my $l (split /\n/, $text) {
        (my $h = $l) =~ s/^[\s#*_]+|[\s#*_:]+$//g;
        if (grep { uc($h) eq $_ } @SECTIONS) { $cur = uc $h; $r{$cur} //= []; next }
        next unless $cur;
        (my $b = $l) =~ s/^\s*(?:[-*•]|\d+[.)])\s*//;
        $b =~ s/\s+$//;
        push @{ $r{$cur} }, $b if $b =~ /\S/ && lc($b) ne 'none';
    }
    \%r;
}
sub response_text {                           # normalised block for the status mail
    my $r = shift;
    return '' unless $r && %$r;
    my $out = "AI assessment:\n";
    for my $s (@SECTIONS) {
        next unless $r->{$s} && @{ $r->{$s} };
        $out .= "  $s\n" . join('', map { "    - $_\n" } @{ $r->{$s} });
    }
    $out;
}
sub response_ok { my $r = shift; ($r && scalar(grep { $r->{$_} } @SECTIONS)) ? 1 : 0 }

# ---------------------------------------------------------------- backends
# ask(conf => \%conf, prompt => $text, out_dir => 'reports', date => ...) -> { status => 'pending'|'ok'|'error', text, prompt_file, response_file }
sub ask {
    my %o = @_;
    my $c = $o{conf} // {};
    my $b = $c->{ai_backend} // 'paste';
    my $pf = "$o{out_dir}/$o{date}-ai-prompt.txt";
    my $rf = "$o{out_dir}/$o{date}-ai-response.txt";
    _write($pf, $o{prompt});
    if ($b eq 'paste') {
        return { status => 'ok', text => _read($rf), prompt_file => $pf, response_file => $rf } if -s $rf;
        return { status => 'pending', prompt_file => $pf, response_file => $rf, text => '' };
    }
    if ($b eq 'mock') {
        my $t = $c->{ai_mock_response} // "HIGHLIGHTS\n- mock highlight\nRISKS\n- none\nSTUCK\n- none\nQUESTIONS FOR LEADS\n- mock question?\nPROGRESS\n- mock progress\n";
        _write($rf, $t);
        return { status => 'ok', text => $t, prompt_file => $pf, response_file => $rf };
    }
    if ($b eq 'curl') {
        my $r = eval { curl_chat($c, $o{prompt}) };
        return { status => 'error', text => '', error => $@, prompt_file => $pf, response_file => $rf } unless defined $r;
        _write($rf, $r);
        return { status => 'ok', text => $r, prompt_file => $pf, response_file => $rf };
    }
    die "unknown ai_backend '$b' (paste|curl|mock)\n";
}

# OpenAI-style chat completions:  ai_url, ai_model, ai_key_env (name of the env var holding the key), ai_curl (default 'curl')
sub curl_chat {
    my ($c, $prompt) = @_;
    die "ai_url not set in scrum.conf\n" unless $c->{ai_url};
    my $key = $c->{ai_key_env} ? $ENV{ $c->{ai_key_env} } : undef;
    my $body = JSON::PP->new->utf8->encode({ model => $c->{ai_model} // 'default', temperature => 0.2,
        messages => [ { role => 'system', content => 'You are a precise engineering-program assistant.' }, { role => 'user', content => $prompt } ] });
    require File::Temp;                       # a portable temp file: $TEMP on a Windows runner is a backslash path that cygwin Perl and curl read differently
    my ($tfh, $bf) = File::Temp::tempfile('ai-req-XXXXXX', SUFFIX => '.json', TMPDIR => 1, UNLINK => 0);
    close $tfh;
    _write($bf, $body);
    my @curl = ref $c->{ai_curl} eq 'ARRAY' ? @{ $c->{ai_curl} } : split(' ', $c->{ai_curl} // 'curl');   # arrayref when set programmatically (paths with spaces); a string from scrum.conf is split on whitespace
    my @cmd = (@curl, '-sS', '-X', 'POST', $c->{ai_url}, '-H', 'Content-Type: application/json', ($key ? ('-H', "Authorization: Bearer $key") : ()), '--data-binary', "\@$bf");
    push @cmd, split(' ', $c->{ai_curl_args}) if $c->{ai_curl_args};
    open my $ph, '-|', @cmd or die "cannot run curl: $!\n";
    my $out = do { local $/; <$ph> };
    close $ph;
    my $rc = $? >> 8;
    unlink $bf;
    die "curl failed (rc=$rc): " . substr($out // '', 0, 300) . "\n" if $rc;
    my $j = eval { JSON::PP->new->utf8->decode($out) } or die "bad JSON from AI endpoint: " . substr($out, 0, 300) . "\n";
    my $text = $j->{choices}[0]{message}{content} // $j->{content}[0]{text} // $j->{response} // $j->{output};
    die "no text in AI response: " . substr($out, 0, 300) . "\n" unless defined $text;
    $text;
}
sub _write { my ($f, $t) = @_; open my $fh, '>:encoding(UTF-8)', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh }
sub _read  { my $f = shift; open my $fh, '<:encoding(UTF-8)', $f or return ''; local $/; my $t = <$fh>; close $fh; $t }

{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|DESTROY|AUTOLOAD)$/ && defined &{"Ai::$_"}
          && !(defined &{"Prelude::$_"} && \&{"Ai::$_"} == \&{"Prelude::$_"})
    } keys %Ai::;
}

1;

__END__

=head1 NAME

Ai - hand the day's stand-up data to your AI service and bring its assessment back into the report

=head1 SYNOPSIS

    daily.pl answers            # parse today's chats -> answers files, flags, suggested lines
    daily.pl ai                 # build prompt from answers+metrics+history; ask, or leave it for pasting
    daily.pl report             # includes the AI assessment when reports/<date>-ai-response.txt exists

scrum.conf:

    ai_backend = paste          # paste (default) | curl | mock
    # curl backend: any OpenAI-style chat-completions endpoint the service exposes
    ai_url     = https://ai.example.com/v1/chat/completions
    ai_model   = gpt-4o
    ai_key_env = AI_API_KEY     # name of the environment variable holding the key; never the key itself
    ai_curl_args = --cacert /path/to/roots.pem   # optional extra curl flags

=head1 PASTE WORKFLOW

C<daily.pl ai> writes C<reports/E<lt>dateE<gt>-ai-prompt.txt>. Open it, select all, paste
into the AI service's chat, copy the reply, save it as C<reports/E<lt>dateE<gt>-ai-response.txt>
(Vim: C<:SAiPrompt> opens the prompt, C<:SAiResponse> opens the response file to paste into).
C<daily.pl report> and C<draft> then include it. The prompt demands five fixed headings so
the reply parses regardless of the model's style; C<parse_response> tolerates markdown.

=head1 WHAT THE AI ADDS, AND WHAT IT DOESN'T

The deterministic flags (L<Answers>) already catch silence, blockers, repeated plans, and
id mismatches, and they never hallucinate. The AI reads the free text: it can notice that
"waiting on Bob" in Bravo's chat is the same thing as Bob's "cert still pending" in Alpha's,
draft the questions to ask, and phrase the progress line. Treat its output as a draft to read
in thirty seconds, not as a metric. Metrics stay derived from the journal.

=head1 SEE ALSO

L<Answers>, L<Scrum>, C<bin/daily.pl>.

=cut
