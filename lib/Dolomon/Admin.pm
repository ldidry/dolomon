package Dolomon::Admin;
use Mojo::Base 'Dolomon::DoloCommon';
use Mojo::Collection 'c';

sub get_users {
    my $c    = shift;
    my $page = shift;
    my $nb   = shift;
    my $sort = shift;
    my $dir  = shift;

    $page = 0 if --$page < 0;
    $nb   = 1 if $nb < 1;
    $page = $page * $nb;

    $sort = 'login' unless c(qw(id login first_name last_name mail last_login confirmed dolos_nb))->map(sub { $_ eq $sort })->size;
    $sort = 'u.'.$sort unless $sort eq 'dolos_nb';

    $dir  = 'DESC' unless $dir eq 'ASC';

    return $c->app->pg->db->query('SELECT u.id, u.login, u.first_name, u.last_name, u.mail, EXTRACT(\'epoch\' FROM u.last_login) AS last_login, u.confirmed, count(d.id) AS dolos_nb FROM users u JOIN categories c ON c.user_id = u.id JOIN dolos d ON d.category_id = c.id GROUP BY u.id ORDER BY '.$sort.' '.$dir.' LIMIT ? OFFSET ?', $nb, $page)->hashes;
}

sub get_nb_users {
    my $c = shift;

    return $c->app->pg->db->query('SELECT count(id) AS users_nb FROM users')->hashes->first->{users_nb};
}

1;
