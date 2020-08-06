package Dolomon::Plugin::MinionTasks;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Collection 'c';
use Dolomon::User;
use Dolomon::Category;
use Dolomon::Tag;
use Dolomon::Application;
use Dolomon::Dolo;
use Dolomon::DoloDay;
use Dolomon::DoloWeek;
use Dolomon::DoloMonth;
use Dolomon::DoloYear;
use Dolomon::DoloHit;
use Dolomon::Export;
use DateTime;
use DateTime::Format::Pg;
use Mojo::JSON qw(encode_json decode_json);
use Mojo::File;

sub register {
    my ($self, $app) = @_;

    $app->minion->add_task(
        clean_stats => sub {
            my $job   = shift;
            my $c     = $job->app;
            my $time  = time;

            # Expire dolos that need it
            $c->pg->db->query('SELECT expire_dolos();');

            # Months stats
            my $dt = DateTime->from_epoch(epoch => $time);
            $dt->subtract_duration(DateTime::Duration->new(months => $job->app->config('keep_hits')->{month_precision}));
            $c->pg->db->query('SELECT clean_month_stats(?, ?)', ($dt->year(), $dt->month()));

            # Weeks stats
            $dt = DateTime->from_epoch(epoch => $time);
            $dt->subtract_duration(DateTime::Duration->new(weeks => $job->app->config('keep_hits')->{week_precision}));
            $c->pg->db->query('SELECT clean_week_stats(?, ?)', ($dt->year(), $dt->week_number()));

            # Days stats
            $dt = DateTime->from_epoch(epoch => $time);
            $dt->subtract_duration(DateTime::Duration->new(days => $job->app->config('keep_hits')->{day_precision}));
            $c->pg->db->query('SELECT clean_day_stats(?, ?, ?)', ($dt->year(), $dt->month(), $dt->day_of_month()));

            # Uber precision stats
            $c->pg->db->query("DELETE FROM dolos_hits WHERE ts < (CURRENT_TIMESTAMP - INTERVAL '".$job->app->config('keep_hits')->{uber_precision}." days')");

            # Data exports
            Dolomon::Export->new(app => $c)->clean_exports();
        }
    );
    $app->minion->add_task(
        hit => sub {
            my $job   = shift;
            my $short = shift;
            my $date  = shift || time;
            my $ref   = shift;

            my $d  = Dolomon::Dolo->new(app => $job->app)->find_by_('short', $short);
            my $dt = DateTime->from_epoch(epoch => $date);

            $job->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', ($d->id, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), $ref));

            if (defined $d->parent_id) {
                $job->app->log->debug("INCREMENT PARENT ".$d->parent_id);
                my $p = Dolomon::Dolo->new(app => $job->app, id => $d->parent_id);

                $job->app->pg->db->query('SELECT increment_dolo_cascade(?, ?, ?, ?, ?, ?, ?)', ($p->id, $dt->year(), $dt->month(), $dt->week_number(), $dt->day(), DateTime::Format::Pg->format_timestamp_with_time_zone($dt), $ref));
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
    $app->minion->add_task(
        delete_user => sub {
            my $job     = shift;
            my $user_id = shift;

            my $c = Dolomon::User->new(app => $job->app, id => $user_id)->delete_cascade();
        }
    );
    $app->minion->add_task(
        export_data => sub {
            my $job     = shift;
            my $user_id = shift;
            my $token   = shift;
            my $subject = shift;
            my $body    = shift;
            my $c       = $job->app;

            my $user = Dolomon::User->new(app => $c, id => $user_id);
            my $data = encode_json($user->export_data());

            my $export = Dolomon::Export->new(app => $c)->find_by_(token => $token);
            Mojo::File->new('exports', $token.'.json')->spurt($data);

            $c->mail(
                to      => $user->mail,
                subject => $subject,
                data    => $body
            );

            my $dt = DateTime->from_epoch(epoch => time);
            $export->update({ finished_at => DateTime::Format::Pg->format_timestamp($dt) });
        }
    );
    $app->minion->add_task(
        import_data => sub {
            my $job     = shift;
            my $user_id = shift;
            my $file    = Mojo::File->new(shift);
            my $time    = shift;
            my $subject = shift;
            my $body    = shift;
            my $rename  = shift;
            my $r_cats  = shift;
            my $r_tags  = shift;
            my $r_apps  = shift;
            my $r_dolos = shift;
            my $tail    = shift;
            my $c       = $job->app;

            my $data = decode_json($file->slurp);
            my $data2 = {
                cats  => {},
                tags  => {},
                dolos => {},
                changed_names => {
                    cats         => {},
                    tags         => {},
                    dolos        => {},
                    applications => {},
                }
            };
            my $renamed = 0;
            c(@{$data->{categories}})->each(sub {
                my ($e, $num) = @_;
                my $category  = Dolomon::Category->new(app => $c);
                my $name      = $e->{name};
                while ($category->is_name_taken($name, $user_id)) {
                    $name .= '-import-'.$time;
                    $data2->{changed_names}->{cats}->{$e->{id}} = 1;
                }
                $category = $category->create({ name => $name, user_id => $user_id });

                $data2->{cats}->{$e->{id}} = $category->id;

                if (defined($data2->{changed_names}->{cats}->{$e->{id}})) {
                    $data2->{changed_names}->{cats}->{$e->{id}} = {
                        old_name => $e->{name},
                        new_name => $name,
                        new_id   => $category->id
                    };
                    $renamed++;
                }
            });
            c(@{$data->{tags}})->each(sub {
                my ($e, $num) = @_;
                my $tag       = Dolomon::Tag->new(app => $c);
                my $name      = $e->{name};
                while ($tag->is_name_taken($name, $user_id)) {
                    $name .= '-import-'.$time;
                    $data2->{changed_names}->{tags}->{$e->{id}} = 1;
                }
                $tag = $tag->create({ name => $name, user_id => $user_id });

                $data2->{tags}->{$e->{id}} = $tag->id;

                if (defined($data2->{changed_names}->{tags}->{$e->{id}})) {
                    $data2->{changed_names}->{tags}->{$e->{id}} = {
                        old_name => $e->{name},
                        new_name => $name,
                        new_id   => $tag->id
                    };
                    $renamed++;
                }
            });
            c(@{$data->{applications}})->each(sub {
                my ($e, $num)   = @_;
                my $application = Dolomon::Application->new(app => $c);
                my $name        = $e->{name};
                while ($application->is_name_taken($name, $user_id)) {
                    $name .= '-import-'.$time;
                    $data2->{changed_names}->{applications}->{$e->{id}} = 1;
                }
                $application = $application->create({ name => $name, user_id => $user_id });

                if (defined($data2->{changed_names}->{applications}->{$e->{id}})) {
                    $data2->{changed_names}->{applications}->{$e->{id}} = {
                        old_name => $e->{name},
                        new_name => $name,
                        new_id   => $application->id
                    };
                    $renamed++;
                }
            });
            c(@{$data->{dolos}})->each(sub {
                my ($e, $num) = @_;
                my $dolo      = Dolomon::Dolo->new(app => $c);
                my $short     = $e->{short};
                while ($dolo->is_name_taken($short, 1, 1, 'short')) {
                    $short .= '-import-'.$time;
                    $data2->{changed_names}->{dolos}->{$e->{id}} = 1;
                }
                my $parent_id = $data2->{dolos}->{$e->{parent_id}} if defined $e->{parent_id};
                $dolo = $dolo->create({
                    short         => $short,
                    url           => $e->{url},
                    name          => $e->{name},
                    extra         => $e->{extra},
                    count         => $e->{count},
                    initial_count => $e->{initial_count},
                    category_id   => $data2->{cats}->{$e->{category_id}},
                    parent_id     => $parent_id,
                    created_at    => $e->{created_at},
                    expired       => $e->{expired},
                    expires_at    => $e->{expires_at},
                    expires_after => $e->{expires_after}
                });

                $data2->{dolos}->{$e->{id}} = $dolo->id;

                if (defined($data2->{changed_names}->{dolos}->{$e->{id}})) {
                    $data2->{changed_names}->{dolos}->{$e->{id}} = {
                        old_name => $e->{short},
                        new_name => $short,
                        new_id   => $dolo->id
                    };
                    $renamed++;
                }
            });
            c(@{$data->{dolos_year}})->each(sub {
                my ($e, $num) = @_;
                Dolomon::DoloYear->new(app => $c)->create({
                    dolo_id => $data2->{dolos}->{$e->{dolo_id}},
                    year    => $e->{year},
                    count   => $e->{count},
                });
            });
            c(@{$data->{dolos_month}})->each(sub {
                my ($e, $num) = @_;
                Dolomon::DoloMonth->new(app => $c)->create({
                    dolo_id => $data2->{dolos}->{$e->{dolo_id}},
                    year    => $e->{year},
                    month   => $e->{month},
                    count   => $e->{count},
                });
            });
            c(@{$data->{dolos_week}})->each(sub {
                my ($e, $num) = @_;
                Dolomon::DoloWeek->new(app => $c)->create({
                    dolo_id => $data2->{dolos}->{$e->{dolo_id}},
                    year    => $e->{year},
                    week    => $e->{week},
                    count   => $e->{count},
                });
            });
            c(@{$data->{dolos_day}})->each(sub {
                my ($e, $num) = @_;
                Dolomon::DoloDay->new(app => $c)->create({
                    dolo_id => $data2->{dolos}->{$e->{dolo_id}},
                    year    => $e->{year},
                    month   => $e->{month},
                    week    => $e->{week},
                    day     => $e->{day},
                    count   => $e->{count},
                });
            });
            c(@{$data->{dolos_hits}})->each(sub {
                my ($e, $num) = @_;
                Dolomon::DoloHit->new(app => $c)->create({
                    dolo_id  => $data2->{dolos}->{$e->{dolo_id}},
                    ts       => $e->{ts},
                    referrer => $e->{referrer},
                });
            });
            my $tag = Dolomon::Tag->new(app => $c);
            c(@{$data->{dolo_has_tags}})->each(sub {
                my ($e, $num) = @_;
                my $tag_id    = $data2->{tags}->{$e->{tag_id}};
                my $dolo_id   = $data2->{dolos}->{$e->{dolo_id}};
                $tag->bind_tag_to($tag_id, $dolo_id);
            });

            if ($renamed) {
                $body .= $rename;
                if (keys(%{$data2->{changed_names}->{cats}})) {
                    $body .= "\n - $r_cats";
                    while (my ($key, $value) = each %{$data2->{changed_names}->{cats}}) {
                        $body .= sprintf("\n  - %s => %s", $value->{old_name}, $value->{new_name});
                    }
                }
                if (keys(%{$data2->{changed_names}->{tags}})) {
                    $body .= "\n- $r_tags";
                    while (my ($key, $value) = each %{$data2->{changed_names}->{tags}}) {
                        $body .= sprintf("\n  - %s => %s", $value->{old_name}, $value->{new_name});
                    }
                }
                if (keys(%{$data2->{changed_names}->{dolos}})) {
                    $body .= "\n- $r_dolos";
                    while (my ($key, $value) = each %{$data2->{changed_names}->{dolos}}) {
                        $body .= sprintf("\n  - %s => %s", $value->{old_name}, $value->{new_name});
                    }
                }
                if (keys(%{$data2->{changed_names}->{applications}})) {
                    $body .= "\n- $r_apps";
                    while (my ($key, $value) = each %{$data2->{changed_names}->{applications}}) {
                        $body .= sprintf("\n  - %s => %s", $value->{old_name}, $value->{new_name});
                    }
                }
            }

            my $user = Dolomon::User->new(app => $c, id => $user_id);
            $c->mail(
                to      => $user->mail,
                subject => $subject,
                data    => $body.$tail
            );

            $file->remove;
        }
    );

}

1;
