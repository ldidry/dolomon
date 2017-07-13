package Dolomon::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin';
use Data::Entropy qw(entropy_source);

sub register {
    my ($self, $app) = @_;

    $app->plugin('PgURLHelper');

    $app->helper(pg        => \&_pg);
    $app->helper(active    => \&_active);
    $app->helper(shortener => \&_shortener);
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

sub _shortener {
    my $c      = shift;
    my $length = shift;

    my @chars  = ('a'..'z','A'..'Z','0'..'9', '-', '_');
    my $result = '';
    foreach (1..$length) {
        $result .= $chars[entropy_source->get_int(scalar(@chars))];
    }
    return $result;
}

1;
