package Dolomon::Controller::Admin;
use Mojo::Base 'Mojolicious::Controller';
use Dolomon::Admin;
use POSIX;

sub index {
    my $c = shift;

    return $c->render(
        template => 'misc/admin',
        page     => $c->param('page')    || 1,
        nb       => $c->param('nb')      || 10,
        sort_by  => $c->param('sort_by') || 'dolos_nb',
        dir      => $c->param('dir')     || 'DESC'
    );
}

sub get_users {
    my $c      = shift;
    my $page   = $c->param('page')    || 1;
    my $nb     = $c->param('nb')      || 10;
    my $sort   = $c->param('sort_by') || 'dolos_nb';
    my $dir    = $c->param('dir')     || 'DESC';
    my $search = $c->param('search');

    my $da       = Dolomon::Admin->new(app => $c->app);
    my $nb_pages = 1;
    my $users;

    if (defined($search)) {
        $users    = $da->search_user($search, $sort, $dir);
    } else {
        $users    = $da->get_users($page, $nb, $sort, $dir);
        $nb_pages = ceil($da->get_nb_users() / $nb);
    }

    return $c->render(
        json => {
            page      => $page,
            sort_by   => $sort,
            nb        => $nb,
            nb_pages  => $nb_pages,
            dir       => $dir,
            timestamp => time,
            users     => $users
        }
    );
}

1;
