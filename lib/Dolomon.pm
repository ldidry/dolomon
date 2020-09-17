package Dolomon;
use Mojo::Base 'Mojolicious';
use Mojo::Collection 'c';
use Dolomon::User;
use Dolomon::Category;
use Dolomon::BreakingChange;
use Dolomon::DefaultConfig qw($default_config);
use Net::LDAP;
use Mojo::JSON qw(true false);
use Mojo::File;
use Mojo::Util qw(decode);
use Mojolicious::Sessions;
use Crypt::PBKDF2;

# This method will run once at server start
sub startup {
    my $self = shift;

    push @{$self->commands->namespaces}, 'Dolomon::Command';

    mkdir 'exports' unless -e 'exports';
    mkdir 'imports' unless -e 'imports';

    my $config = $self->plugin('Config' => {
        default => $default_config
    });

    die "You need to provide a contact information in dolomon.conf !" unless (defined($config->{contact}));

    ## Themes handling
    shift @{$self->renderer->paths};
    shift @{$self->static->paths};
    if ($config->{theme} ne 'default') {
        my $theme = $self->home->rel_file('themes/'.$config->{theme});
        push @{$self->renderer->paths}, $theme.'/templates' if -d $theme.'/templates';
        push @{$self->static->paths}, $theme.'/public' if -d $theme.'/public';
    }
    push @{$self->renderer->paths}, $self->home->rel_file('themes/default/templates');
    push @{$self->static->paths}, $self->home->rel_file('themes/default/public');

    ## Plugins
    # Internationalization
    my $lib = $self->home->rel_file('themes/'.$config->{theme}.'/lib');
    eval qq(use lib "$lib");
    $self->plugin('I18N');

    # Mail config
    my $mail_config = {
        type     => 'text/plain',
        encoding => 'base64',
        how      => $self->config('mail')->{'how'},
        from     => $self->config('mail')->{'from'}
    };
    $mail_config->{howargs} = $self->config('mail')->{'howargs'} if (defined $self->config('mail')->{'howargs'});
    $self->plugin('Mail' => $mail_config);

    $self->plugin('StaticCache');

    $self->plugin('PgURLHelper');

    $self->plugin('DebugDumperHelper');

    $self->plugin('Dolomon::Plugin::Helpers');

    $self->plugin('FiatTux::Helpers');

    $self->plugin('Minion' => { Pg => $self->pg_url($self->config->{minion_db}) });

    $self->plugin('Minion::Admin' => { return_to => '/admin', route => $self->routes->any('/admin/minion')->over(is_admin => 1) });

    $self->plugin('CoverDb' => { route => 'c' });

    $self->plugin('authentication' =>
        {
            autoload_user => 1,
            session_key   => 'Dolomon',
            stash_key     => '__authentication__',
            load_user     => sub {
                my ($c, $uid) = @_;

                return undef unless defined $uid;

                my $user = Dolomon::User->new(app => $c->app, 'id', $uid);
                my $admins = c(@{$c->app->config('admins')});
                if ($admins->size) {
                    my $is_admin = $admins->grep(sub {$_ eq $user->login});
                    $user->{is_admin} = $is_admin->size;
                } else {
                    $user->{is_admin} = 0;
                }

                return $user;
            },
            validate_user => sub {
                my ($c, $username, $password, $extradata) = @_;

                my $method = $extradata->{method} || 'standard';

                if ($method eq 'ldap') {
                    my $ldap = Net::LDAP->new($c->config->{ldap}->{uri});
                    my $mesg;
                    if (defined($c->config->{ldap}->{bind_user}) && defined($c->config->{ldap}->{bind_dn}) && defined($c->config->{ldap}->{bind_pwd})) {
                        $mesg = $ldap->bind($c->config->{ldap}->{bind_user}.$c->config->{ldap}->{bind_dn},
                            password => $c->config->{ldap}->{bind_pwd}
                        );
                    } else {
                        $mesg = $ldap->bind;
                    }

                    if ($mesg->code) {
                        $c->app->log->error('[LDAP ERROR] '.$mesg->error);
                        return undef;
                    }

                    my $uid = $c->config->{ldap}->{user_key} || 'uid';
                    $mesg = $ldap->search(
                        base => $c->config->{ldap}->{user_tree},
                        filter => "(&($uid=$username)".$c->config->{ldap}->{user_filter}.")"
                    );

                    if ($mesg->code) {
                        $c->app->log->error('[LDAP ERROR] '.$mesg->error);
                        return undef;
                    }

                    my @entries = $mesg->entries;
                    my $entry   = $entries[0];

                    if (!defined $entry) {
                        $c->app->log->info("[LDAP authentication failed] - User $username filtered out, IP: ".$extradata->{ip});
                        return undef;
                    }
                    my $res = $mesg->as_struct->{$entry->dn};

                    # Now we know that the user exists
                    $mesg = $ldap->bind($entry->dn,
                        password => $password
                    );

                    if ($mesg->code) {
                        $c->app->log->error('[LDAP ERROR] '.$mesg->error);
                        return undef;
                    }

                    my $givenname = $c->config->{ldap}->{first_name} || 'givenname';
                    my $sn        = $c->config->{ldap}->{last_name} || 'sn';
                    my $mail      = $c->config->{ldap}->{mail} || 'mail';
                    my $infos    = {
                        first_name => decode('UTF-8', $res->{$givenname}->[0]),
                        last_name  => decode('UTF-8', $res->{$sn}->[0]),
                        mail       => decode('UTF-8', $res->{$mail}->[0])
                    };

                    my $user = Dolomon::User->new(app => $c->app)->find_by_('login', $username);

                    if (defined($user->id)) {
                        $user = $user->update($infos, 'login');
                    } else {
                        $user = $user->create(
                            {
                                login      => $username,
                                first_name => decode('UTF-8', $res->{$givenname}->[0]),
                                last_name  => decode('UTF-8', $res->{$sn}->[0]),
                                mail       => decode('UTF-8', $res->{$mail}->[0]),
                                confirmed  => 'true'
                            }
                        );
                        my $cat = Dolomon::Category->new(app => $c->app)->create(
                            {
                                name    => $c->l('Default'),
                                user_id => $user->id
                            }
                        );
                    }

                    return $user->id;
                } elsif ($method eq 'standard') {
                    my $user = Dolomon::User->new(app => $c->app)->find_by_('login', $username);

                    if (defined($user->id)) {
                        return undef unless $user->confirmed;

                        my $hash = $user->password; # means that this is a LDAP user
                        return undef unless $hash;

                        my $pbkdf2 = Crypt::PBKDF2->new;

                        if ($pbkdf2->validate($hash, $password)) {
                            $user = $user->update({}, 'login');
                            return $user->id;
                        } else {
                            return undef;
                        }
                    } else {
                        return undef;
                    }
                }
            }
        }
    );

    ## Configure sessions
    my $sessions = Mojolicious::Sessions->new;
    $sessions->cookie_name('dolomon');
    $sessions->cookie_path($self->config('prefix'));
    $sessions->default_expiration(86400*31); # set expiry to 31 days
    $self->sessions($sessions);

    ## Hooks
    $self->app->hook(
        before_dispatch => sub {
            my $c = shift;
            $c->res->headers->header('Access-Control-Allow-Origin' => '*');
            if ($c->app->time_to_clean) {
                $c->minion->enqueue('clean_stats');
            }
        }
    );

    ## Minion tasks
    $self->plugin('Dolomon::Plugin::MinionTasks');

    ## Database migration
    my $migrations = Mojo::Pg::Migrations->new(pg => $self->pg);
    if ($ENV{DOLOMON_DEV}) {
        $migrations->from_file('utilities/migrations.sql')->migrate(0)->migrate($migrations->latest);
        $self->app->minion->reset;
    } else {
        $migrations->from_file('utilities/migrations.sql')->migrate($migrations->latest);
    }

    ## Handle breaking changes… but not when using the breakingchanges command line 😉
    if ((scalar(@ARGV) == 0 || $ARGV[0] ne 'breakingchanges') && !$ENV{DOLOMON_TEST}) {
        my $bc = Dolomon::BreakingChange->new(app => $self, change => 'app_secret_migration');
        if (!$bc->ack) {
            print <<EOF;
==========================================================================
==                       WARNING! BREAKING CHANGE                       ==
==========================================================================
==                                                                      ==
== You need to execute this command before being able to start Dolomon: ==
==                                                                      ==
== carton exec ./script/dolomon breakingchanges app_secret_migration    ==
==                                                                      ==
== Please note that you won't be able to revert the changes!            ==
==                                                                      ==
==========================================================================
EOF
            exit 1;
        }
    }

    ## Router
    my $r = $self->routes;

    $r->add_condition(authenticated_or_application => sub {
        my ($r, $c, $captures, $required) = @_;
        my $res = (!$required || $c->is_user_authenticated) ? 1 : 0;

        if (!$res && defined $c->req->headers->header('XDolomon-App-Id') && defined $c->req->headers->header('XDolomon-App-Secret')) {
            my $rows = $c->pg->db->query(
                'SELECT user_id, app_secret FROM applications WHERE app_id::text = ?',
                $c->req->headers->header('XDolomon-App-Id')
            );
            if ($rows->rows == 1) {
                my $pbkdf2 = Crypt::PBKDF2->new;

                my $app = $rows->hash;
                if ($pbkdf2->validate($app->{app_secret}, $c->req->headers->header('XDolomon-App-Secret'))) {
                    $c->stash('__authentication__' => {
                        user => Dolomon::User->new(app => $c->app, 'id', $app->{user_id})
                    });
                    $res = 1;
                }
            }
            if (!$res) {
                $c->stash('format' => 'json') unless scalar @{$c->accepts};
                $c->respond_to(
                    html => {
                        template => 'misc/index',
                        goto     => $r->name
                    },
                    any => {
                        json => {
                            success => false,
                            msg     => $c->l('You are not authenticated or have not valid application credentials')
                        }
                    }
                );
            }
        }
        return $res;
    });

    $r->add_condition(is_admin => sub {
        my ($r, $c, $captures, $required) = @_;
        return 0 unless $c->is_user_authenticated;
        return $c->current_user->{is_admin};
    });

    # CORS headers for API
    $r->options('/api/*')->
        to('Misc#cors');

    # Normal route to controller
    $r->get('/')->
        name('index')->
        to('Misc#authent');

    $r->post('/')->
        to('Misc#login');

    $r->get('/lang/:l')->
        name('lang')->
        to('Misc#change_lang');

    $r->get('/about')->
        name('about')->
        to('Misc#about');

    $r->get('/admin')->
        over('is_admin')->
        name('admin')->
        to('Admin#index');

    unless ($self->config('no_register') || $self->config('no_internal_accounts')) {
        $r->post('/register')->
            to('Users#register');

        $r->get('/confirm/:token')->
            name('confirm')->
            to('Users#confirm');
    }

    unless ($self->config('no_internal_accounts')) {
        $r->get('/forgot_password' => sub {
            return shift->render(
                template => 'users/send_mail',
                action   => 'password',
            );
        })->name('forgot_password');

        $r->post('/forgot_password')->
            to('Users#forgot_password');

        $r->get('/renew_password/:token' => sub {
            my $c = shift;
            return $c->render(
                template => 'users/send_mail',
                action   => 'renew',
                token    => $c->param('token')
            );
        })->name('renew_password');

        $r->post('/renew_password')->
            to('Users#renew_password');

        $r->get('/send_again' => sub {
            return shift->render(
                template => 'users/send_mail',
                action   => 'token'
            );
        })->name('send_again');

        $r->post('/send_again')->
            to('Users#send_again');
    }

    $r->get('/partial/js/:file' => sub {
        my $c = shift;
        $c->render(
            template => 'js/'.$c->param('file'),
            format   => 'js',
            layout   => undef,
        );
    })->name('partial');

    $r->get('/dashboard')->
        over(authenticated_or_application => 1)->
        name('dashboard')->
        to('Misc#dashboard');

    $r->get('/logout')->
        over(authenticated_or_application => 1)->
        name('logout')->
        to('Misc#get_out');

    $r->get('/export-import')->
        over(authenticated_or_application => 1)->
        name('export-import')->
        to('Data#index');

    $r->get('/export')->
        over(authenticated_or_application => 1)->
        name('export')->
        to('Data#export');

    $r->get('/data/:token')->
        name('download_data')->
        to('Data#download');

    $r->post('/import')->
        over(authenticated_or_application => 1)->
        name('import')->
        to('Data#import');

    $r->any('/api/ping')->
        over(authenticated_or_application => 1)->
        name('ping')->
        to('Misc#ping');

    $r->get('/dolo')->
        over(authenticated_or_application => 1)->
        name('dolo')->
        to('Dolos#index');

    $r->get('/dolo/:id')->
        over(authenticated_or_application => 1)->
        name('show_dolo')->
        to('Dolos#show');

    $r->get('/api/dolo/data/:id')->
        over(authenticated_or_application => 1)->
        name('get_dolo_data')->
        to('Dolos#get_data');

    $r->get('/api/dolo/zip/:id')->
        over(authenticated_or_application => 1)->
        name('get_dolo_zip')->
        to('Dolos#get_zip');

    $r->get('/api/dolo')->
        over(authenticated_or_application => 1)->
        name('get_dolo')->
        to('Dolos#get');

    $r->post('/api/dolo')->
        over(authenticated_or_application => 1)->
        name('add_dolo')->
        to('Dolos#add');

    $r->put('/api/dolo')->
        over(authenticated_or_application => 1)->
        name('mod_dolo')->
        to('Dolos#modify');

    $r->delete('/api/dolo')->
        over(authenticated_or_application => 1)->
        name('del_dolo')->
        to('Dolos#delete');

    $r->get('/cat')->
        over(authenticated_or_application => 1)->
        name('categories')->
        to('Categories#index');

    $r->get('/cat/:id')->
        over(authenticated_or_application => 1)->
        name('show_cat')->
        to('Categories#show');

    $r->get('/api/cat/data/:id')->
        over(authenticated_or_application => 1)->
        name('get_cat_data')->
        to('Categories#get_data');

    $r->get('/api/cat/zip/:id')->
        over(authenticated_or_application => 1)->
        name('get_cat_zip')->
        to('Categories#get_zip');

    $r->get('/api/cat')->
        over(authenticated_or_application => 1)->
        name('get_cat')->
        to('Categories#get');

    $r->post('/api/cat')->
        over(authenticated_or_application => 1)->
        name('add_cat')->
        to('Categories#add');

    $r->put('/api/cat')->
        over(authenticated_or_application => 1)->
        name('mod_cat')->
        to('Categories#rename');

    $r->delete('/api/cat')->
        over(authenticated_or_application => 1)->
        name('del_cat')->
        to('Categories#delete');

    $r->get('/tags')->
        over(authenticated_or_application => 1)->
        name('tags')->
        to('Tags#index');

    $r->get('/tag/:id')->
        over(authenticated_or_application => 1)->
        name('show_tag')->
        to('Tags#show');

    $r->get('/api/tag/data/:id')->
        over(authenticated_or_application => 1)->
        name('get_tag_data')->
        to('Tags#get_data');

    $r->get('/api/tag/zip/:id')->
        over(authenticated_or_application => 1)->
        name('get_tag_zip')->
        to('Tags#get_zip');

    $r->get('/api/tag')->
        over(authenticated_or_application => 1)->
        name('get_tag')->
        to('Tags#get');

    $r->post('/api/tag')->
        over(authenticated_or_application => 1)->
        name('add_tag')->
        to('Tags#add');

    $r->put('/api/tag')->
        over(authenticated_or_application => 1)->
        name('mod_tag')->
        to('Tags#rename');

    $r->delete('/api/tag')->
        over(authenticated_or_application => 1)->
        name('del_tag')->
        to('Tags#delete');

    $r->get('/apps')->
        over(authenticated_or_application => 1)->
        name('apps')->
        to('Applications#index');

    $r->get('/api/app')->
        over(authenticated_or_application => 1)->
        name('get_app')->
        to('Applications#get');

    $r->post('/api/app')->
        over(authenticated_or_application => 1)->
        name('add_app')->
        to('Applications#add');

    $r->put('/api/app')->
        over(authenticated_or_application => 1)->
        name('mod_app')->
        to('Applications#rename');

    $r->delete('/api/app')->
        over(authenticated_or_application => 1)->
        name('del_app')->
        to('Applications#delete');

    $r->get('/api/admin/users')->
        over(is_admin => 1)->
        name('admin_get_users')->
        to('Admin#get_users');

    $r->delete('/api/admin/users')->
        over(is_admin => 1)->
        name('admin_remove_user')->
        to('Admin#remove_user');

    $r->post('/api/admin/impersonate')->
        over(is_admin => 1)->
        name('admin_impersonate')->
        to('Admin#impersonate');

    $r->get('/api/admin/stop_impersonate')->
        over(authenticated_or_application => 1)->
        name('admin_stop_impersonate')->
        to('Admin#stop_impersonate');

    $r->get('/user')->
        over(authenticated_or_application => 1)->
        name('user')->
        to('Users#index');

    unless ($self->config('no_internal_accounts')) {
        $r->post('/user')->
            over(authenticated_or_application => 1)->
            to('Users#modify');

        $r->get('/delete/:token')->
            over(authenticated_or_application => 1)->
            name('confirm_delete')->
            to('Users#confirm_delete');
    }

    $r->get('/h/:short')->
        name('hit')->
        to('Dolos#hit');
}

1;
