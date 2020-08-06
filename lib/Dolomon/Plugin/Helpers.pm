package Dolomon::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin';
use Data::Entropy qw(entropy_source);
use Mojo::Collection;
use Mojo::File;
use Mojo::Util qw(decode);
use ISO::639_1;

sub register {
    my ($self, $app) = @_;

    $app->plugin('PgURLHelper');

    $app->helper(pg                 => \&_pg);
    $app->helper(active             => \&_active);
    $app->helper(time_to_clean      => \&_time_to_clean);

    $app->hook(
        before_dispatch => sub {
            my $c = shift;
            $c->languages($c->cookie('dolomon_lang')) if $c->cookie('dolomon_lang');
        }
    );
}

sub _pg {
    my $c     = shift;

    state $pg = Mojo::Pg->new($c->app->pg_url($c->app->config('db')));
}

sub _active {
    my $c = shift;
    my $r = shift;

    return ($c->current_route eq $r) ? ' class="active"' : '';
}

sub _time_to_clean {
    my $c    = shift;
    my $time = time;

    state $last_cleaning;

    # If the last cleaning was less than 2 hours ago
    if (defined $last_cleaning && ($last_cleaning + 7200 > $time)) {
        return 0
    }

    $last_cleaning = $time;
    return 1;
}

1;
