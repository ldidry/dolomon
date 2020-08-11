package Dolomon::Controller::Admin;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(true false encode_json decode_json);
use Mojo::Collection 'c';
use Mojo::Cookie;
use Dolomon::Admin;
use Dolomon::User;
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

sub impersonate {
    my $c  = shift;
    my $id = $c->param('id');

    my $msg;
    my $real_user = {
        id        => $c->current_user->id,
    };
    $real_user->{real_user} = decode_json($c->cookie('real_user'))->{real_user} if defined $c->cookie('real_user');
    my $user      = $c->authenticate($id, '', { auto_validate => $id });
    my $success   = false;
    if ($user) {
        $c->cookie(real_user => encode_json($real_user), { path => $c->config('prefix') });
        $success = true;
    } else {
        $msg = {
            class => 'alert-danger',
            msg   => c->l('Sorry, unable to impersonate this user. Contact the administrator.')
        };
    }

    $c->render(
        json => {
            success => $success,
            msg     => $msg
        }
    );
}

sub stop_impersonate {
    my $c = shift;

    my $msg;
    if (defined($c->cookie('real_user'))) {
        my $cookie = decode_json($c->cookie('real_user'));
        my $old_real_user = $cookie->{real_user};

        my $user = $c->authenticate($cookie->{id}, '', { auto_validate => $cookie->{id} });
        if ($user) {
            if (defined($old_real_user)) {
                $c->cookie(real_user => $old_real_user, { path => $c->config('prefix') });
            } else {
                $c->cookie(real_user => '', { expires => -1, path => $c->config('prefix') });
            }
            $msg = {
                title => $c->l('Impersonating has been stopped'),
                class => 'alert-info',
                text  => $c->l('You have returned to your previous session.')
            };
        } else {
            $msg = {
                title => $c->l('Can\'t stop impersonating'),
                class => 'alert-danger',
                text  => $c->l('Please contact the administrator.')
            };
        }
    } else {
        $msg = {
            title => $c->l('Can\'t stop impersonating'),
            class => 'alert-danger',
            text  => $c->l('You weren\'t impersonating anyone.')
        };
    }

    $c->flash(msg => $msg);
    return $c->redirect_to('admin');
}

sub remove_user {
    my $c = shift;
    my $id = $c->param('id');

    my $user    = Dolomon::User->new(app => $c->app, id => $id);
    my $success = false;
    my $msg;
    if ($user->login) {
        $c->app->minion->enqueue(delete_user => [$user->id]);
        $success = true;
        $msg     = {
            title => $c->l('Success'),
            class => 'alert-info',
            text  => $c->l('The account %1 will be deleted in a short time.', $user->login)
        };
    } else {
        $msg = {
            title => $c->l('Error'),
            class => 'alert-danger',
            text  => $c->l('Unable to find an account with this id.')
        };
    }
    return $c->render(
        json => {
            success => $success,
            msg     => $msg
        }
    );
}

1;
