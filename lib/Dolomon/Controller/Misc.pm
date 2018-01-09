package Dolomon::Controller::Misc;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(true false);

sub cors {
    my $c = shift;
    $c->res->headers->header('Access-Control-Allow-Origin'  => '*');
    $c->res->headers->header('Access-Control-Allow-Headers' => 'xdolomon-app-id,xdolomon-app-secret');
    $c->res->headers->header('Access-Control-Allow-Method'  => 'GET, POST, PUT, DELETE');
    $c->rendered(200);
}

sub dashboard {
    return shift->render(
        template => 'misc/dashboard'
    );
}

sub authent {
    my $c      = shift;
    my $goto   = $c->param('goto') || 'dashboard';
    my $method = $c->cookie('auth_method') || 'standard';

    return $c->redirect_to('dashboard') if $c->is_user_authenticated;

    return $c->render(
        template => 'misc/index',
        goto     => $goto,
        method   => $method
    );
}

sub login {
    my $c      = shift;
    my $login  = $c->param('login');
    my $pwd    = $c->param('password');
    my $goto   = $c->param('goto');
    my $method = $c->param('method');

    my $validation = $c->validation;

    if ($validation->csrf_protect->has_error('csrf_token')) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Bad CSRF token!')
            }
        );
        return $c->render(
            template => 'misc/index',
            goto     => $goto,
            method   => $method
        );
    } elsif ($c->authenticate($login, $pwd, { method => $method })) {
        $c->cookie(auth_method => $method);
        $c->stash(
            msg => {
                class => 'alert-info',
                text  => $c->l('You have been successfully authenticated.')
            }
        );
        if (defined $goto) {
            return $c->redirect_to($c->url_for($goto));
        } else {
            return $c->render(
                template => 'misc/dashboard'
            );
        }
    } else {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Unable to authenticate. Please check your credentials.')
            }
        );
        return $c->render(
            template => 'misc/index',
            goto     => $goto,
            method   => $method
        );
    }
}

sub get_out {
    my $c = shift;

    $c->logout();

    $c->flash(
        msg => {
            title => $c->l('Logout'),
            class => 'alert-info',
            text  => $c->l('You have been successfully disconnected.')
        }
    );
    return $c->redirect_to('/');
}

sub ping {
    my $c = shift;

    my $pong = false;
    if ($c->is_user_authenticated) {
        $pong = true
    }
    return $c->render(
        json => {
            success => $pong
        }
    );
}

sub change_lang {
    my $c = shift;
    my $l = $c->param('l');

    $c->cookie(dolomon_lang => $l, { path => $c->config('prefix') });

    if ($c->req->headers->referrer) {
        return $c->redirect_to($c->req->headers->referrer);
    } else {
        return $c->redirect_to('/');
    }
}

1;
