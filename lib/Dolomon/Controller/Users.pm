package Dolomon::Controller::Users;
use Mojo::Base 'Mojolicious::Controller';
use Dolomon::User;
use Crypt::PBKDF2;
use Email::Valid;

sub index {
    my $c = shift;

    if ($c->current_user->password) {
        return $c->render(
            template => 'users/index'
        );
    } else {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('This is a LDAP account, you can’t change account details nor password here.')
            }
        );
        return $c->render(
            template => 'misc/dashboard'
        );
    }
}

sub confirm_delete {
    my $c     = shift;
    my $token = $c->param('token');

    my $msg = {
        title => $c->l('Error'),
        class => 'alert-danger',
        text  => $c->l('Unable to find an account with this token.')
    };

    if ($token =~ m#[0-9a-z]{8}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{12}#) {
        my $user = Dolomon::User->new(app => $c->app)->find_by_('token', $token);
        if ($user->id) {
            if (!defined($c->current_user) || $user->id == $c->current_user->id) {
                $c->logout() if defined $c->current_user;

                $c->app->minion->enqueue(delete_user => [$user->id]);

                $msg = {
                    class => 'alert-info',
                    text  => $c->l('Your account will be deleted in a short time.')
                }
            } else {
                $msg = {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    text  => $c->l('You are not logged in with the same account that you are trying to delete. Please, log out first.')
                };
            }
        }
    }

    if ($c->is_user_authenticated) {
        $c->flash(msg => $msg);
        return $c->redirect_to('dashboard');
    }

    $c->stash(msg => $msg);
    return $c->render(
        template => 'misc/index',
        goto     => 'dashboard',
        method   => 'register',
    );
}

sub modify {
    my $c      = shift;
    my $action = $c->param('action');

    # LDAP user
    unless ($c->current_user->password) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('This is a LDAP account, you can\'t change account details nor password here.')
            }
        );
        return $c->render(
            template => 'misc/dashboard'
        );
    }

    my $v = $c->validation;

    if ($v->csrf_protect->has_error('csrf_token')) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Bad CSRF token!')
            }
        );
        return $c->render(
            template => 'users/index',
        );
    }

    unless ($c->current_user->password || $action eq 'delete_account') {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('This is a LDAP account, you can\'t change account details nor password here.')
            }
        );
        return $c->render(
            template => 'misc/dashboard'
        );
    }

    my @texts = ();

    if ($action eq 'account_details') {
        $v->optional('first_name', 'trim');
        $v->optional('last_name',  'trim');
        $v->required('mail', 'trim', 'not_empty')->valid_email;

        push @texts, $c->l('This email address is not valid.') if $v->has_error('mail');

        $v->required('mail')->available_email;
        push @texts, $c->l('Email address already used. Choose another one.') if $v->has_error('mail');

        if (scalar @texts) {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    texts => \@texts
                }
            );
        } else {
            $c->current_user->update(
                {
                    first_name => $v->param('first_name'),
                    last_name  => $v->param('last_name'),
                    mail       => $v->param('mail'),
                }
            );
            $c->stash(
                msg => {
                    class => 'alert-info',
                    text  => $c->l('Your account details have been updated.')
                }
            );
        }
    } elsif ($action eq 'change_password') {
        my $pwd  = $c->param('password');
        my $pwd2 = $c->param('password2');
        my $pwd3 = $c->param('password3');

        my $pbkdf2 = Crypt::PBKDF2->new(
            hash_class => 'HMACSHA2',
            hash_args => {
                sha_size => 512,
            },
            iterations => 10000,
            salt_len => 10
        );

        unless ($pbkdf2->validate($c->current_user->password, $pwd)) {
            push @texts, $c->l('Your current password is incorrect.');
        }

        if ($pwd2 ne $pwd3) {
            push @texts, $c->l('The passwords does not match.');
        }

        if (length $pwd2 < 8) {
            push @texts, $c->l('Please, choose a password with at least 8 characters.');
        }

        if (scalar @texts) {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    texts => \@texts
                }
            );
        } else {
            my $npwd = $pbkdf2->generate($pwd2);
            $c->current_user->update({password => $npwd});
            $c->current_user->password($npwd);

            $c->stash(
                msg => {
                    class => 'alert-info',
                    text  => $c->l('Your password has been successfully changed.')
                }
            );
        }
    } elsif ($action eq 'delete_account') {
        my $pwd  = $c->param('password');
        my $pbkdf2 = Crypt::PBKDF2->new();

        unless ($pbkdf2->validate($c->current_user->password, $pwd)) {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    text  => $c->l('Your current password is incorrect.')
                }
            );
        } else {
            my $user = $c->current_user->renew_token();
            $c->current_user->token($user->token);

            my $subject = $c->l('Account deletion');
            my $data    = $c->l("Someone asked to delete your account on %1.\n", $c->url_for('/')->to_abs->to_string); 
               $data   .= $c->l('If want to delete your account, please click on this link: %1', $c->url_for('confirm_delete', {token => $user->token})->to_abs->to_string);
               $data   .= "\n-- \n";
               $data   .= $c->l("Kind regards\n");
               $data   .= $c->config('signature');
            $c->mail(
                to      => $c->current_user->mail,
                subject => $subject,
                data    => $data,
            ) unless $ENV{CI};
            $c->stash(
                msg => {
                    class => 'alert-info',
                    text  => $c->l('An email has been sent to %1 for your account deletion.', $user->mail)
                }
            );
        }
    }

    return $c->render(
        template => 'users/index',
    );
}

sub renew_password {
    my $c     = shift;
    my $token = $c->param('token');
    my $pwd   = $c->param('password');
    my $pwd2  = $c->param('password2');

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
            template => 'users/send_mail',
            action   => 'renew',
            token    => $token
        );
    }

    my @texts = ();

    if ($pwd ne $pwd2) {
        push @texts, $c->l('The passwords does not match.');
    }

    if (length $pwd < 8) {
        push @texts, $c->l('Please, choose a password with at least 8 characters.');
    }

    my $user = Dolomon::User->new(app => $c->app)->find_by_('token', $token);
    if ($user->id) {
        if (!$user->password) {
            push @texts, $c->l('This is a LDAP account, you can\'t change your password here.');
        } elsif ($user->confirmed) {
            $c->stash(
                msg => {
                    class => 'alert-info',
                    text  => $c->l('Your password has been updated. You can now login with your new password.')
                }
            );
            my $pbkdf2 = Crypt::PBKDF2->new(
                hash_class => 'HMACSHA2',
                hash_args => {
                    sha_size => 512,
                },
                iterations => 10000,
                salt_len => 10
            );
            $user = $user->update({password => $pbkdf2->generate($pwd)});

            return $c->render(
                template => 'misc/index',
                goto     => 'dashboard',
                method   => 'standard',
            );
        } else {
             push @texts, $c->l('The account linked to this token is not confirmed. Please confirm the account first.');
        }
    } else {
        push @texts, $c->l('Unable to find an account with this token.');
    }

    $c->stash(
        msg => {
            title => $c->l('Error'),
            class => 'alert-danger',
            texts => \@texts
        }
    );
    return $c->render(
        template => 'users/send_mail',
        action   => 'renew',
        token    => $token
    );
}

sub forgot_password {
    my $c    = shift;
    my $mail = $c->param('mail');

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
            template => 'users/send_mail',
            action   => 'password'
        );
    }
    if (!Email::Valid->address($mail)) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('This email address is not valid.')
            }
        );

        return $c->render(
            template => 'users/send_mail',
            action   => 'password'
        );
    }

    my $user = Dolomon::User->new(app => $c->app)->find_by_('mail', $mail);
    if ($user->id) {
        if (!$user->password) {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    text  => $c->l('This is a LDAP account, you can\'t change your password here.')
                }
            );
        } elsif ($user->confirmed) {
            $user = $user->renew_token();
            my $subject = $c->l('Password renewal');
            my $data    = $c->l('Hello %1,', $user->login)."\n\n";
               $data   .= $c->l("Someone asked to renew your password on %1.\n", $c->url_for('/')->to_abs->to_string);
               $data   .= $c->l('If it\'s you, please click on this link: %1', $c->url_for('renew_password', {token => $user->token})->to_abs->to_string);
               $data   .= "\n-- \n";
               $data   .= $c->l("Kind regards\n");
               $data   .= $c->config('signature');
            $c->mail(
                to      => $mail,
                subject => $subject,
                data    => $data,
            ) unless $ENV{CI};
            $c->stash(
                msg => {
                    class => 'alert-info',
                    text  => $c->l('An email has been sent to %1 for your password renewal.', $mail)
                }
            );
        } else {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    text  => $c->l('The account linked to this email address is not confirmed. Please confirm the account.')
                }
            );
        }
    } else {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Unable to retrieve an account linked to that email address.')
            }
        );
    }

    return $c->render(
        template => 'users/send_mail',
        action   => 'password'
    );
}

sub send_again {
    my $c    = shift;
    my $mail = $c->param('mail');

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
            template => 'users/send_mail',
            action   => 'token'
        );
    }
    if (!Email::Valid->address($mail)) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('This email address is not valid.')
            }
        );

        return $c->render(
            template => 'users/send_mail',
            action   => 'token'
        );
    }

    my $user = Dolomon::User->new(app => $c->app)->find_by_('mail', $mail);
    if ($user->id) {
        if ($user->confirmed) {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    text  => $c->l('This account has already been confirmed.')
                }
            );
        } else {
            $user = $user->renew_token();
            my $subject = $c->l('Please confirm your email address');
            my $data    = $c->l("This is the final step for your registration on %1.\n", $c->url_for('/')->to_abs->to_string); 
               $data   .= $c->l('Please click on this link: %1', $c->url_for('confirm', {token => $user->token})->to_abs->to_string);
               $data   .= "\n-- \n";
               $data   .= $c->l("Kind regards\n");
               $data   .= $c->config('signature');
            $c->mail(
                to      => $mail,
                subject => $subject,
                data    => $data,
            ) unless $ENV{CI};
            $c->stash(
                msg => {
                    class => 'alert-info',
                    text  => $c->l('An email has been sent to %1 for your password renewal.', $mail)
                }
            );
        }
    } else {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Unable to retrieve an account linked to that email address.')
            }
        );
    }

    return $c->render(
        template => 'users/send_mail',
        action   => 'token'
    );
}

sub confirm {
    my $c     = shift;

    my $v = $c->validation->input({token => $c->param('token')});

    $v->required('token', 'trim', 'not_empty')->uuid_like;
    $c->debug($v->has_error('token'));
    if (!$v->has_error('token')) {
        my $user = Dolomon::User->new(app => $c->app)->find_by_('token', $v->param('token'));
        if ($user->id) {
            if ($user->confirmed) {
                $c->stash(
                    msg => {
                        title => $c->l('Error'),
                        class => 'alert-danger',
                        text  => $c->l('This account has already been confirmed.')
                    }
                );
            } else {
                $user->update({confirmed => 'true'});
                $user->renew_token();
                $c->stash(
                    msg => {
                        class => 'alert-info',
                        text  => $c->l('Your account is now confirmed. You can now login.')
                    }
                );
            }
            return $c->render(
                template => 'misc/index',
                goto     => 'dashboard',
                method   => 'standard',
            );
        }
    }
    $c->stash(
        msg => {
            title => $c->l('Error'),
            class => 'alert-danger',
            text  => $c->l('Unable to find an account with this token: %1', $v->param('token'))
        }
    );
    return $c->render(
        template => 'misc/index',
        goto     => 'dashboard',
        method   => 'register',
    );
}

sub register {
    my $c     = shift;
    my $v = $c->validation;

    if ($v->csrf_protect->has_error('csrf_token')) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Bad CSRF token!')
            }
        );
        return $c->render(
            template   => 'misc/index',
            goto       => 'dashboard',
            method     => 'register',
            login      => $c->param('login'),
            mail       => $c->param('mail'),
            first_name => $c->param('fname'),
            last_name  => $c->param('lname')
        );
    }

    my @texts = ();

    $v->required('login',      'trim', 'not_empty')->available_login;
    push @texts, $c->l('Login already taken. Choose another one.') if $v->has_error('login');

    $v->required('mail',       'trim', 'not_empty')->available_email;
    push @texts, $c->l('Email address already used. Choose another one.') if $v->has_error('mail');

    $v->required('mail')->valid_email;
    push @texts, $c->l('This email address is not valid.') if $v->has_error('mail');

    $v->required('password',   'trim', 'not_empty')->size(8, undef);
    push @texts, $c->l('Please, choose a password with at least 8 characters.') if $v->has_error('password');

    $v->required('password2',  'trim', 'not_empty')->equal_to('password');
    push @texts, $c->l('The passwords does not match.') if $v->has_error('password2');

    $v->optional('first_name', 'trim', 'not_empty');
    $v->optional('last_name',  'trim', 'not_empty');

    if (scalar @texts) {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                texts => \@texts
            }
        );
        return $c->render(
            template   => 'misc/index',
            goto       => 'dashboard',
            method     => 'register',
            login      => $c->param('login'),
            mail       => $c->param('mail'),
            first_name => $c->param('fname'),
            last_name  => $c->param('lname')
        );
    }

    my $login = $v->param('login');
    my $mail  = $v->param('mail');
    my $pwd   = $v->param('password');
    my $fname = $v->param('first_name');
    my $lname = $v->param('last_name');

    my $pbkdf2 = Crypt::PBKDF2->new(
        hash_class => 'HMACSHA2',
        hash_args => {
            sha_size => 512,
        },
        iterations => 10000,
        salt_len => 10
    );
    my $user = Dolomon::User->new(app => $c->app)->create(
        {
            login      => $login,
            first_name => $fname,
            last_name  => $lname,
            mail       => $mail,
            password   => $pbkdf2->generate($pwd)
        }
    );
    my $cat = Dolomon::Category->new(app => $c->app)->create(
        {
            name    => $c->l('Default'),
            user_id => $user->id
        }
    );

    $c->cookie(auth_method => 'standard');

    $c->stash(
        msg => {
            class => 'alert-info',
            text  => $c->l('You have been successfully registered. You will receive a mail containing a link to finish your registration.')
        }
    );

    my $subject = $c->l('Please confirm your email address');
    my $data    = $c->l("This is the final step for your registration on %1.\n", $c->url_for('/')->to_abs->to_string); 
       $data   .= $c->l('Please click on this link: %1', $c->url_for('confirm', {token => $user->token})->to_abs->to_string);
       $data   .= "\n-- \n";
       $data   .= $c->l("Kind regards\n");
       $data   .= $c->config('signature');
    $c->mail(
        to      => $mail,
        subject => $subject,
        data    => $data,
    ) unless $ENV{CI};
    return $c->render(
        template => 'misc/index',
        goto     => 'dashboard',
        method   => 'standard',
    );
}

1;
