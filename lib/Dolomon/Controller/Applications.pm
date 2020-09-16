package Dolomon::Controller::Applications;
use Mojo::Base 'Mojolicious::Controller';
use Crypt::PBKDF2;
use Dolomon::Application;
use Mojo::JSON qw(true false);
use Mojo::Util qw(xml_escape);

sub index {
    my $c = shift;

    $c->respond_to(
        json => {
            json => $c->current_user->get_applications()->map(sub { $_->as_struct })->to_array
        },
        any => {
            template => 'applications/index',
            apps     => $c->current_user->get_applications()
        }
    );
}

sub get {
    my $c  = shift;
    my $id = $c->param('id');

    if (defined $id) {
        my $app = Dolomon::Application->new(app => $c->app, id => $id);
        unless (defined($app->user_id) && $app->user_id == $c->current_user->id) {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('The application you\'re trying to get does not belong to you.')
                }
            );
        }
        return $c->render(
            json => {
                success => true,
                object  => $app->as_struct
            }
        );
    } else {
        return $c->render(
            json => {
                success => true,
                object  => $c->current_user->get_applications()->map(sub { $_->as_struct })->to_array
            }
        );
    }
}

sub add {
    my $c    = shift;
    my $name = xml_escape($c->param('name'));

    if (defined $name && $name ne '') {
        my $app = Dolomon::Application->new(app => $c->app);
        unless ($app->is_name_taken($name, $c->current_user->id)) {
            my $pbkdf2 = Crypt::PBKDF2->new(
                hash_class => 'HMACSHA2',
                hash_args => {
                    sha_size => 512,
                },
                iterations => 10000,
                salt_len => 10
            );
            my $uuid = $app->generate_uuid_v4();
            $app->create({user_id => $c->current_user->id, name => $name, app_secret => $pbkdf2->generate($uuid)});

            if (defined $app) {
                return $c->render(
                    json => {
                        success    => true,
                        msg        => $c->l('The application %1 has been successfully created. Please note the credentials below: you won\'t be able to recover them.<br><ul><li>app_id: %2</li><li>app_secret: %3</li><ul>', ($app->name, $app->app_id, $uuid)),
                        app_id     => $app->app_id,
                        app_secret => $uuid,
                        object     => $app->as_struct
                    }
                );
            } else {
                return $c->render(
                    json => {
                        success => false,
                        msg     => $c->l('Unable to create application %1. Please contact the administrator.', $name)
                    }
                );
            }
        } else {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('Unable to create application %1, this name is already taken. Choose another one.', $name)
                }
            );
        }
    } else {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('Application name blank or undefined. I refuse to create an application without name.')
            }
        );
    }
}

sub rename {
    my $c       = shift;
    my $id      = $c->param('id');
    my $newname = xml_escape($c->param('name'));

    if (defined $newname && $newname ne '') {
        my $app  = Dolomon::Application->new(app => $c->app, id => $id);
        my $name = $app->name;
        unless (defined($app->user_id) && $app->user_id == $c->current_user->id) {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('The application you\'re trying to rename does not belong to you.')
                }
            );
        }
        if ($newname eq $name) {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('The new name is the same as the previous: %1.', $name)
                }
            );
        }
        my $result = $app->rename($newname);

        if (defined $result) {
            return $c->render(
                json => {
                    success => true,
                    msg     => $c->l('The application %1 has been successfully renamed to %2', ($name, $newname)),
                    newname => $result->name
                }
            );
        } else {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('Something went wrong while renaming application %1 to %2', ($name, $newname))
                }
            );
        }
    } else {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('New application name blank or undefined. I refuse to rename the application.')
            }
        );
    }
}

sub delete {
    my $c  = shift;
    my $id = $c->param('id');

    my $app = Dolomon::Application->new(app => $c->app, id => $id);

    if (!defined($app->user_id) || $app->user_id != $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The application you\'re trying to delete does not belong to you.')
            }
        );
    }

    $app->delete();

    return $c->render(
        json => {
            success => true,
            msg     => $c->l('The application %1 has been successfully deleted.', $app->name)
        }
    );
}

1;
