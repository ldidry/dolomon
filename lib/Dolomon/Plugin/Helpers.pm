package Dolomon::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ($self, $app) = @_;

    $app->helper(pg     => \&_pg);
    $app->helper(active => \&_active);
}

sub _pg {
    my $c     = shift;

    my $addr  = 'postgresql://';
    $addr    .= $c->config->{db}->{user};
    $addr    .= ':'.$c->config->{db}->{passwd};
    $addr    .= '@'.$c->config->{db}->{host};
    $addr    .= '/'.$c->config->{db}->{database};
    state $pg = Mojo::Pg->new($addr);
}

sub _active {
    my $c = shift;
    my $r = shift;

    return ($c->current_route eq $r) ? ' class="active"' : '';
}

1;
