# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
package Dolomon::Command::breakingchanges::app_secret_migration;
use Mojo::Base 'Mojolicious::Command';
use FindBin qw($Bin);
use Dolomon::Application;
use Dolomon::BreakingChange;
use Dolomon::DefaultConfig qw($default_config);
use Term::ProgressBar;
use Crypt::PBKDF2;

has description => 'Update "applications" DB table to increase security.';
has usage       => sub { shift->extract_usage };

sub run {
    my $c = shift;

    my $bc = Dolomon::BreakingChange->new(app => $c->app, change => 'app_secret_migration');
    if ($bc->ack) {
        say 'Change "app_secret_migration" already applied. Exiting.';
        exit;
    }

    say 'Getting number of database records to update, it can take some time.';
    my $apps = Dolomon::Application->new(app => $c->app)->get_all();
    if ($apps->size) {
        say sprintf('There is %d database records to update, please be patient.', $apps->size);
        print 'Do you want to continue? [Y/n] ';
        my $confirm = <STDIN>;

        if ($confirm =~ m/yes|y/i) {
            my $progress = Term::ProgressBar->new({ count => $apps->size, ETA => 'linear', name => 'Migrating app_secret' });
            my $pbkdf2 = Crypt::PBKDF2->new(
                hash_class => 'HMACSHA2',
                hash_args => {
                    sha_size => 512,
                },
                iterations => 10000,
                salt_len => 10
            );
            $apps->each(sub {
                my ($e, $num) = @_;
                $e->update({ app_secret => $pbkdf2->generate($e->{app_secret}) });
                $progress->update();
            });
            $bc->acknowledge;
            say 'Change "app_secret_migration" successfully applied. You can now start Dolomon.';
        } else {
            say 'Change "app_secret_migration" not applied. You won\'t be able to start Dolomon';
        }
    } else {
        say 'No records in database. Setting "app_secret_migration" change as applied.';
        $bc->acknowledge;
        say 'Change "app_secret_migration" successfully applied. You can now start Dolomon.';
    }
}

=encoding utf8

=head1 NAME

Dolomon::Command::breakingchanges::app_secret_migration - Update "applications" DB table to increase security.

=head1 SYNOPSIS

  Usage: script/dolomon breakingchanges app_secret_migration

=cut

1;
