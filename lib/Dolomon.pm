package Dolomon;
use Mojo::Base 'Mojolicious';
use Mojo::Collection 'c';
use Dolomon::User;
use Dolomon::Category;
use Dolomon::Dolo;
use Dolomon::DoloDay;
use Dolomon::DoloWeek;
use Dolomon::DoloMonth;
use Dolomon::DoloYear;
use Dolomon::DoloHit;
use Net::LDAP;
use DateTime;
use DateTime::Format::Pg;
use Mojo::JSON qw(true false);
use Mojo::File;
use Mojo::Util qw(decode);
use Mojolicious::Sessions;
use Crypt::PBKDF2;

# This method will run once at server start
sub startup {
    my $self = shift;

    push @{$self->commands->namespaces}, 'Dolomon::Command';

    my $config = $self->plugin('Config' => {
        default => {
            prefix               => '/',
            admins               => [],
            theme                => 'default',
            no_register          => 0,
            counter_delay        => 0,
            do_not_count_spiders => 0,
            mail      => {
                how  => 'sendmail',
                from => 'noreply@dolomon.org'
            },
            signature => 'Dolomon',
            keep_hits => {
                uber_precision  => 3,
                day_precision   => 90,
                week_precision  => 12,
                month_precision => 36,
            }
        }
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

    $self->plugin('Minion' => { Pg => $self->pg_url($self->config->{minion_db}) });

    $self->plugin('Minion::Admin' => { return_to => '/admin', route => $self->routes->any('/admin/minion')->over(is_admin => 1) });

    $self->plugin('authentication' =>
        {
            autoload_user => 1,
            session_key   => 'Dolomon',
            stash_key     => '__authentication__',
            load_user     => sub {
                my ($c, $uid) = @_;

                return undef unless defined $uid;

                my $user = Dolomon::User->new(app => $c->app, 'id', $uid);
                if (defined $c->config('admins')) {
                    my $is_admin = c(@{$c->app->config('admins')})->grep(sub {$_ eq $user->login});
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
                    my $res = $mesg->as_struct->{$entry->dn};

                    if (!defined $entry) {
                        $c->app->log->info("[LDAP authentication failed] - User $username filtered out, IP: ".$c->ip);
                        return undef;
                    }

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
            $c->minion->enqueue('clean_stats');
        }
    );

    ## Minion tasks
    $self->app->minion->add_task(
        clean_stats => sub {
            my $job   = shift;
            my $c     = $job->app;
            my $file  = 'last_cleaning_time.txt';
            my $time  = time;
            my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($file);

            # Clean stats every two hours max
            if (($time - $mtime) > 7200) {
                # Create a job to expire dolos that need it
                $job->app->minion->enqueue('expire_dolos');

                # Months stats
                my $dt = DateTime->from_epoch(epoch => $time);
                $dt->subtract_duration(DateTime::Duration->new(months => $job->app->config('keep_hits')->{month_precision}));
                $c->pg->db->query('DELETE FROM dolos_month WHERE year < ? OR (year = ? AND month < ?)', ($dt->year(), $dt->year(), $dt->month()));

                # Weeks stats
                $dt = DateTime->from_epoch(epoch => $time);
                $dt->subtract_duration(DateTime::Duration->new(weeks => $job->app->config('keep_hits')->{week_precision}));
                $c->pg->db->query('DELETE FROM dolos_week WHERE year < ? OR (year = ? AND week < ?)', ($dt->year(), $dt->year(), $dt->week_number()));

                # Days stats
                $dt = DateTime->from_epoch(epoch => $time);
                $dt->subtract_duration(DateTime::Duration->new(days => $job->app->config('keep_hits')->{day_precision}));
                $c->pg->db->query('DELETE FROM dolos_day WHERE year < ? OR (year = ? AND month < ?) OR (year = ? AND month = ? AND day < ?)', ($dt->year(), $dt->year(), $dt->month(), $dt->year(), $dt->month(), $dt->day_of_month()));

                # Uber precision stats
                $c->pg->db->query("DELETE FROM dolos_hits WHERE ts < (CURRENT_TIMESTAMP - INTERVAL '".$job->app->config('keep_hits')->{uber_precision}." days')");
                Mojo::File->new($file)->spurt($job->app->config('keep_hits')->{uber_precision});
            }
        }
    );
    $self->app->minion->add_task(
        expire_dolos => sub {
            my $job   = shift;
            my $c     = $job->app;

            $c->pg->db->query("UPDATE dolos SET expired = true WHERE expired IS false AND (created_at + (INTERVAL '1 day' * expires_at)) < current_timestamp;");
        }
    );
    $self->app->minion->add_task(
        hit => sub {
            my $job   = shift;
            my $short = shift;
            my $date  = shift || time;
            my $ref   = shift;

            my $d    = Dolomon::Dolo->new(app => $job->app)->find_by_('short', $short);

            $d->increment;
            $job->app->minion->enqueue(add_hit_day   => [$d->id, $date]);
            $job->app->minion->enqueue(add_hit_week  => [$d->id, $date]);
            $job->app->minion->enqueue(add_hit_month => [$d->id, $date]);
            $job->app->minion->enqueue(add_hit_year  => [$d->id, $date]);
            $job->app->minion->enqueue(add_hit       => [$d->id, $date, $ref]);
            $job->app->minion->enqueue(add_hit_user  => [$d->id]);

            if (defined $d->parent_id) {
                $job->app->log->debug("INCREMENT PARENT ".$d->parent_id);
                my $p = Dolomon::Dolo->new(app => $job->app, 'id', $d->parent_id);
                $p->increment;
                $job->app->minion->enqueue(add_hit_day   => [$p->id, $date]);
                $job->app->minion->enqueue(add_hit_week  => [$p->id, $date]);
                $job->app->minion->enqueue(add_hit_month => [$p->id, $date]);
                $job->app->minion->enqueue(add_hit_year  => [$p->id, $date]);
                $job->app->minion->enqueue(add_hit       => [$p->id, $date, $ref]);
            }

            if (defined($d->expires_after) && !defined($d->expires_at)) {
                my $expires_at = DateTime->now()->add(days => $d->expires_after);
                my $duration   = $expires_at->subtract_datetime(DateTime::Format::Pg->parse_timestamp_with_time_zone($d->created_at))->in_units('days');
                $d->update({
                    expires_at => $duration
                });
            }
        }
    );
    $self->app->minion->add_task(
        add_hit_user => sub {
            my $job     = shift;
            my $dolo_id = shift;

            my $cat_id  = Dolomon::Dolo->new(app => $job->app, id => $dolo_id)->category_id;
            my $user_id = Dolomon::Category->new(app => $job->app, id => $cat_id)->user_id;
            Dolomon::User->new(app => $job->app, id => $user_id)->increment;
        }
    );
    $self->app->minion->add_task(
        add_hit_day => sub {
            my $job     = shift;
            my $dolo_id = shift;
            my $date    = DateTime->from_epoch(epoch => shift);

            Dolomon::DoloDay->new(
                app     => $job->app,
                dolo_id => $dolo_id,
                year    => $date->year(),
                month   => $date->month(),
                week    => $date->week_number(),
                day     => $date->day()
            )->find_by_fields_(
                [qw(dolo_id year month week day)]
            )->increment_or_create;
        }
    );
    $self->app->minion->add_task(
        add_hit_week => sub {
            my $job     = shift;
            my $dolo_id = shift;
            my $date    = DateTime->from_epoch(epoch => shift);

            Dolomon::DoloWeek->new(
                app     => $job->app,
                dolo_id => $dolo_id,
                year    => $date->year(),
                week    => $date->week_number()
            )->find_by_fields_(
                [qw(dolo_id year week)]
            )->increment_or_create;
        }
    );
    $self->app->minion->add_task(
        add_hit_month => sub {
            my $job     = shift;
            my $dolo_id = shift;
            my $date    = DateTime->from_epoch(epoch => shift);

            Dolomon::DoloMonth->new(
                app     => $job->app,
                dolo_id => $dolo_id,
                year    => $date->year(),
                month   => $date->month()
            )->find_by_fields_(
                [qw(dolo_id year month)]
            )->increment_or_create;
        }
    );
    $self->app->minion->add_task(
        add_hit_year => sub {
            my $job     = shift;
            my $dolo_id = shift;
            my $date    = DateTime->from_epoch(epoch => shift);

            Dolomon::DoloYear->new(
                app     => $job->app,
                dolo_id => $dolo_id,
                year    => $date->year()
            )->find_by_fields_(
                [qw(dolo_id year)]
            )->increment_or_create;
        }
    );
    $self->app->minion->add_task(
        add_hit => sub {
            my $job     = shift;
            my $dolo_id = shift;
            my $date    = DateTime->from_epoch(epoch => shift);
            my $ref     = shift;

            my $c = Dolomon::DoloHit->new(app => $job->app)->create({
                dolo_id  => $dolo_id,
                ts       => DateTime::Format::Pg->format_timestamp_with_time_zone($date),
                referrer => $ref
            });
        }
    );
    $self->app->minion->add_task(
        delete_user => sub {
            my $job     = shift;
            my $user_id = shift;

            my $c = Dolomon::User->new(app => $job->app, id => $user_id)->delete_cascade();
        }
    );

    ## Database migration
    my $migrations = Mojo::Pg::Migrations->new(pg => $self->pg);
    if ($ENV{DOLOMON_DEV} && 0) {
        $migrations->from_file('utilities/migrations.sql')->migrate(0)->migrate(1);
        $self->app->minion->reset;
    } else {
        $migrations->from_file('utilities/migrations.sql')->migrate(1);
    }

    ## Be sure last_cleaning_time.txt file exists
    Mojo::File->new('last_cleaning_time.txt')->spurt(time) unless -e 'last_cleaning_time.txt';

    ## Router
    my $r = $self->routes;

    $r->add_condition(authenticated_or_application => sub {
        my ($r, $c, $captures, $required) = @_;
        my $res = (!$required || $c->is_user_authenticated) ? 1 : 0;

        if (!$res && defined $c->req->headers->header('XDolomon-App-Id') && defined $c->req->headers->header('XDolomon-App-Secret')) {
            my $rows = $c->pg->db->query('SELECT user_id FROM applications WHERE app_id::text = ? AND app_secret::text = ?',
                ($c->req->headers->header('XDolomon-App-Id'), $c->req->headers->header('XDolomon-App-Secret'))
            );
            if ($rows->rows == 1) {
                $c->stash('__authentication__' => {
                    user => Dolomon::User->new(app => $c->app, 'id', $rows->hash->{user_id})
                });
                $res = 1;
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

    unless ($self->config('no_register')) {
        $r->post('/register')->
            to('Users#register');

        $r->get('/confirm/:token')->
            name('confirm')->
            to('Users#confirm');

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

    unless ($self->config('no_register')) {
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
