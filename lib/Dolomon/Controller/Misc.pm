package Dolomon::Controller::Misc;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(true false);

sub cors {
    my $c = shift;
    $c->res->headers->header('Access-Control-Allow-Origin' => '*');
    $c->res->headers->header('Access-Control-Allow-Headers' => 'xdolomon-app-id,xdolomon-app-secret');
    $c->res->headers->header('Access-Control-Allow-Method' => 'GET, POST, PUT, DELETE');
    $c->rendered(200);
}

sub dashboard {
    my $c = shift;

    return $c->render(
        template => 'misc/dashboard'
    )
}

sub authent {
    my $c = shift;
    my $goto = $c->param('goto') || 'dashboard';

    return $c->render(
        template => 'misc/index',
        goto     => $goto
    );
}

sub login {
    my $c     = shift;
    my $login = $c->param('login');
    my $pwd   = $c->param('password');
    my $goto  = $c->param('goto');

    if($c->authenticate($login, $pwd)) {
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
            goto     => $goto
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
    return $c->redirect_to('index');
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
1;
