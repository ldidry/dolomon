package Dolomon::Application;
use Mojo::Base 'Dolomon::Db';
use Mojo::Collection;

has 'table' => 'applications';
has 'name';
has 'user_id';
has 'app_id';
has 'app_secret';

sub get_all {
    my $c = shift;
    my $r = $c->app->pg->db->query('SELECT * FROM '.$c->table)->hashes;

    my $results = Mojo::Collection->new();
    $r->each(sub {
        my ($e, $num) = @_;
        my $app = Dolomon::Application->new(app => $c->app)
                                      ->id($e->{id})
                                      ->name($e->{name})
                                      ->user_id($e->{user_id})
                                      ->app_id($e->{app_id})
                                      ->app_secret($e->{app_secret});
        push @{$results}, $app;
    });

    return $results
}

1;
