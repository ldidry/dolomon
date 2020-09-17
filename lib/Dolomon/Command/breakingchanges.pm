# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
package Dolomon::Command::breakingchanges;
use Mojo::Base 'Mojolicious::Commands';

has description => 'Execute breaking changes tasks.';
has hint        => <<EOF;

See 'script/dolomon breakingchanges help TASK' for more information on a specific task.
EOF
has message    => sub { shift->extract_usage . "\nBreaking changes tasks:\n    app_secret_migration" };
has namespaces => sub { ['Dolomon::Command::breakingchanges'] };

sub help { shift->run(@_) }

1;

=encoding utf8

=head1 NAME

Dolomon::Command::breakingchanges - Cron commands

=head1 SYNOPSIS

  Usage: script/dolomon breakingchanges TASK [OPTIONS]

=cut

