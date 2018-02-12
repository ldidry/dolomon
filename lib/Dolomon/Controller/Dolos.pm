package Dolomon::Controller::Dolos;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Collection;
use Mojo::JSON qw(true false);
use Mojo::Util qw(xml_escape);
use Dolomon::Dolo;
use Dolomon::Category;
use Dolomon::Tag;
use HTTP::BrowserDetect;
use Text::Slugify 'slugify';
use Data::Validate::URI qw(is_web_uri);
use DateTime::Format::Pg;
use DateTime::Duration;
use Math::Round 'nlowmult';
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

sub index {
    my $c = shift;

    $c->respond_to(
        json => {
            json => $c->current_user->get_dolos()->map(sub { $_->as_struct })->to_array
        },
        any => {
            template   => 'dolos/index',
            dolos => $c->current_user->get_dolos()
        }
    );
}

sub show {
    my $c      = shift;
    my $id     = $c->param('id');

    my ($msg, %agg_referrers);
    my $dolo = Dolomon::Dolo->new(app => $c->app, id => $id);
    unless (defined $dolo->user_id && $dolo->user_id == $c->current_user->id) {
        $msg = {
            class => 'alert-warning',
            title => $c->l('Error'),
            text  => $c->l('The dolo you\'re trying to show does not belong to you.')
        };
    } else {
        my $dhs = $dolo->get_raw_dhs;
        $dhs->each(sub {
            my ($e, $num) = @_;

            if ($e->{referrer}) {
                $agg_referrers{$e->{referrer}}  = 0 unless defined $agg_referrers{$e->{referrer}};
                $agg_referrers{$e->{referrer}} += 1;
            }
        });
    }

    return $c->render(
        template  => 'dolos/show',
        msg       => $msg,
        dolo      => (defined $msg) ? undef : $dolo,
        referrers => \%agg_referrers
    );
}

sub get_data {
    my $c      = shift;
    my $id     = $c->param('id');
    my $period = $c->param('period');
    my $agg    = $c->param('aggregate_by');
    # $agg must be at least one minute and at most one day
       $agg    = 60 unless (defined $agg && 0 < $agg && $agg < 60*24);

    my $dolo = Dolomon::Dolo->new(app => $c->app, id => $id);
    unless (defined $dolo->user_id && $dolo->user_id == $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The dolo you\'re trying to get does not belong to you.')
            }
        );
    }

    my (@data, $min, $max);
    if ($period eq 'years') {
        my $dys = $dolo->get_raw_dys;
        $dys->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year})->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dys->size;
        });
    } elsif ($period eq 'months') {
        my $dms = $dolo->get_raw_dms;
        $dms->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year}, month => $e->{month})->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dms->size;
        });
    } elsif ($period eq 'weeks') {
        my $dws = $dolo->get_raw_dws;
        $dws->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year}, month => 1, day => 4 )->add(weeks => $e->{week} - 1)->truncate( to => 'week' )->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dws->size;
        });
    } elsif ($period eq 'days') {
        my $dds = $dolo->get_raw_dds;
        $dds->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year}, month => $e->{month}, day => $e->{day})->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dds->size;
        });
    } elsif ($period eq 'hits') {
        my $dhs = $dolo->get_raw_dhs;
        my %agg_hits;
        $dhs->each(sub {
            my ($e, $num) = @_;

            my $dt = DateTime::Format::Pg->parse_timestamp_with_time_zone($e->{ts})->set_time_zone('UTC');

            my $duration = DateTime::Duration->new(minutes => nlowmult($agg, ($dt->hour * 60 + $dt->minute)));
            $dt->truncate(to => 'day');
            $dt += $duration;

            my $time = $dt->epoch();

            $agg_hits{$time}  = 0 unless defined $agg_hits{$time};
            $agg_hits{$time} += 1;
            $min = $time unless defined ($min);
            $max = $time if $num == $dhs->size;
        });
        for my $time (keys %agg_hits) {
            push @data, { x => $time, value => $agg_hits{$time} };
        }
    }

    return $c->render(
        json => {
            success => true,
            data    => \@data,
            min     => $min,
            max     => $max,
            object  => $dolo->as_struct
        }
    );
}

sub get_zip {
    my $c      = shift;
    my $id     = $c->param('id');
    my $period = $c->param('period');
    my $agg    = $c->param('aggregate_by');
    # $agg must be at least one minute and at most one day
       $agg    = 60 unless (defined $agg && 0 < $agg && $agg < 60*24);

    my $dolo = Dolomon::Dolo->new(app => $c->app, id => $id);
    unless (defined $dolo->user_id && $dolo->user_id == $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The dolo you\'re trying to get does not belong to you.')
            }
        );
    }

    my $zip = Archive::Zip->new();

    # Years
    my $csv = '"Year","Count"'."\n";
    my $dys = $dolo->get_raw_dys;
    $dys->each(sub {
        my ($e, $num) = @_;
        $csv .= '"'.$e->{year}.'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'years.csv');

    # Months
    $csv = '"Year","Month","Count"'."\n";
    my $dms = $dolo->get_raw_dms;
    $dms->each(sub {
        my ($e, $num) = @_;
        $csv .= '"'.$e->{year}.'","'.$e->{month}.'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'months.csv');

    # Weeks
    $csv = '"Year","Week","Count"'."\n";
    my $dws = $dolo->get_raw_dws;
    $dws->each(sub {
        my ($e, $num) = @_;
        my $time = DateTime->new(year => $e->{year}, month => 1, day => 4 )->add(weeks => $e->{week} - 1)->truncate( to => 'week' )->set_time_zone('UTC');
        $csv .= '"'.$time->week_year().'","'.$time->week_number().'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'weeks.csv');

    # Days
    $csv = '"Year","Month","Day","Count"'."\n";
    my $dds = $dolo->get_raw_dds;
    $dds->each(sub {
        my ($e, $num) = @_;
        $csv .= '"'.$e->{year}.'","'.$e->{month}.'","'.$e->{day}.'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'days.csv');

    # Hits
    $csv = '"Timestamp","Count"'."\n";
    my $dhs = $dolo->get_raw_dhs;
    my (%agg_hits, %agg_referrers);
    $dhs->each(sub {
        my ($e, $num) = @_;

        my $time = DateTime::Format::Pg->parse_timestamp_with_time_zone($e->{ts})->set_time_zone('UTC')->epoch();

        $agg_hits{$time}  = 0 unless defined $agg_hits{$time};
        $agg_hits{$time} += 1;

        if ($e->{referrer}) {
            $e->{referrer} = "'".$e->{referrer} if $e->{referrer} =~ /^(?:=|\+|-|@)/;
            $agg_referrers{$e->{referrer}}  = 0 unless defined $agg_referrers{$e->{referrer}};
            $agg_referrers{$e->{referrer}} += 1;
        }
    });
    for my $time (keys %agg_hits) {
        $csv .= '"'.$time.'","'.$agg_hits{$time}.'"'."\n";
    }
    $zip->addString($csv, 'hits.csv');

    $csv = '"Referrer","Count"'."\n";
    for my $referrer (sort keys %agg_referrers) {
        $csv .= '"'.$referrer.'","'.$agg_referrers{$referrer}.'"'."\n";
    }
    $zip->addString($csv, 'referrers.csv');

    my ($fh, $zipfile) = Archive::Zip::tempFile();
    unless ($zip->writeToFileNamed($zipfile) == AZ_OK) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('Unable to generate the zip file. Please contact the administrator')
            }
        );
    }

    my $headers = Mojo::Headers->new();
    $headers->add('Content-Type'        => 'application/zip;name=export-dolo-'.$id.'.zip');
    $headers->add('Content-Disposition' => 'attachment;filename=export-dolo-'.$id.'.zip');
    $c->res->content->headers($headers);

    my $asset = Mojo::Asset::File->new(path => $zipfile);
    $c->res->content->asset($asset);
    $headers->add('Content-Length' => $asset->size);

    unlink $zipfile;

    return $c->rendered(200);
}

sub get {
    my $c      = shift;
    my $id     = $c->param('id');

    if (defined $id) {
        my $dolo = Dolomon::Dolo->new(app => $c->app, id => $id);
        unless (defined $dolo->user_id && $dolo->user_id == $c->current_user->id) {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('The dolo you\'re trying to get does not belong to you.')
                }
            );
        }
        return $c->render(
            json => {
                success => true,
                object  => $dolo->as_struct
            }
        );
    } else {
        return $c->render(
            json => {
                success => true,
                object  => $c->current_user->get_dolos()->map(sub { $_->as_struct })->to_array
            }
        );
    }
}

sub add {
    my $c    = shift;
    my $dolo = Dolomon::Dolo->new(app => $c->app);
    my %errors;

    my $url  = $c->param('url');
    my $furl = $url;
       $furl =~ s/ftp/http/;
    $errors{doloUrl} = [$c->l('The url is not a valid http, https, ftp or ftps URL.')] unless (is_web_uri($url) || is_web_uri($furl));

    my $name = xml_escape($c->param('name'));
    $errors{doloName} = [$c->l('The name %1 is already taken for the category you choose.')] if ($name && $dolo->is_name_taken($name, $c->param('cat_id'), 'category_id'));

    my $short = slugify($c->param('short'));
    if ($short ne '') {
        if ($dolo->is_name_taken($short, 1, 1, 'short')) {
            $short = $c->current_user->id.$short;
        }
        $errors{doloShort} = [$c->l('You already have a dolo which dolomon URL is %1.')] if ($dolo->is_name_taken($short, 1, 1, 'short'));
    } else {
        do {
            $short = $c->current_user->id.$c->shortener(10);
        } while ($dolo->is_name_taken($short, 1, 1, 'short'));
    }

    my $initial_count = $c->param('initial_count') || 0;
    $errors{initialCount} = [$c->l('The initial counter must be an integer, superior or equal to 0.')] unless ($initial_count =~ m/^\d+$/);

    my $cat = Dolomon::Category->new(app => $c->app, id => $c->param('cat_id'));
    $errors{catList} = [$c->l('I can\'t find the given category.')] unless (defined $cat->user_id);
    if (defined $cat->user_id && $cat->user_id != $c->current_user->id) {
        $errors{catList} = [] unless defined $errors{catList};
        push @{$errors{catList}}, $c->l('The category you want to use for your dolo does not belong to you.');
    }
    if ($url ne $c->url_for('/1px.gif')->to_abs && $cat->dolos->grep(sub { $_->url eq $url })->size) {
        $errors{doloUrl} = [] unless defined $errors{doloUrl};
        push @{$errors{doloUrl}}, $c->l('You already have that URL in the dolos of this category.');
    }

    my $tags_id = $c->every_param('tags[]');
    my @tags;
    for my $tag_id (@{$tags_id}) {
        my $tag = Dolomon::Tag->new(app => $c->app, id => $tag_id);
        unless (defined $tag->user_id && $tag->user_id == $c->current_user->id) {
            $errors{tagList} = [] unless defined $errors{tagList};
            if (!defined $tag->user_id) {
                push @{$errors{tagList}}, $c->l('I can\'t find at least one of the given tag.');
            } else {
                push @{$errors{tagList}}, $c->l('At least one of the tag you want to use for your dolo does not belong to you.') unless (defined $tag->user_id && $tag->user_id == $c->current_user->id);
            }
        }
        push @tags, $tag;
    }

    return $c->render(
        json => {
            success => false,
            errors  => \%errors
        }
    ) if (scalar keys %errors);

    $c->app->log->warn('short: '.$short);
    $dolo = $dolo->create({
        url           => $url,
        name          => $name,
        extra         => xml_escape($c->param('extra')),
        short         => $short,
        count         => $initial_count,
        initial_count => $initial_count,
        expires_at    => (defined $c->param('expires_at')    && $c->param('expires_at') ne '')    ? $c->param('expires_at')    : undef,
        expires_after => (defined $c->param('expires_after') && $c->param('expires_after') ne '') ? $c->param('expires_after') : undef,
        category_id   => $cat->id,
    });

    my @tmp;
    for my $tag (@tags) {
        $tag->bind_to($dolo->id);
        push @tmp, { id => $tag->id, name => $tag->name };
    }
    $dolo = $dolo->tags(\@tmp);

    $c->current_user->increment($initial_count);

    return $c->render(
        json => {
            success => true,
            msg     => $c->l("The dolo %1 has been successfully created.<br>Its dolomon URL is %2.", ($dolo->name || $dolo->url, $c->url_for('hit', short => $dolo->short)->to_abs)),
            object  => $dolo->as_struct
        }
    );
}

sub modify {
    my $c    = shift;
    my $id   = $c->param('id');

    return $c->render(
        json => {
            success => false,
            errors  => {
                id => [
                    $c->l('You need to provide a dolo id!')
                ]
            }
        }
    ) unless defined $id;

    my $dolo = Dolomon::Dolo->new(app => $c->app, id => $id);

    return $c->render(
        json => {
            success => false,
            errors  => {
                id => [
                    $c->l('The dolo you\'re trying to delete does not belong to you.')
                ]
            }
        }
    ) if ($dolo->user_id != $c->current_user->id);

    my %errors;

    my $url  = $c->param('url');
    my $furl = $url;
       $furl =~ s/ftp/http/;
    $errors{doloUrl} = [$c->l('The url is not a valid http, https, ftp or ftps URL.')] unless (is_web_uri($url) || is_web_uri($furl));

    my $name = xml_escape($c->param('name'));
    $errors{doloName} = [$c->l('The name %1 is already taken for the category you choose.')] if ($dolo->is_name_taken($name, $c->param('cat_id'), 'category_id') && $name ne $dolo->name);

    my $cat = Dolomon::Category->new(app => $c->app, id => $c->param('cat_id'));
    $errors{catList} = [$c->l('I can\'t find the given category.')] unless (defined $cat->user_id);
    if (defined $cat->user_id && $cat->user_id != $c->current_user->id) {
        $errors{catList} = [] unless defined $errors{catList};
        push @{$errors{catList}}, $c->l('The category you want to use for your dolo does not belong to you.');
    }
    if ($c->param('cat_id') != $dolo->category_id && $cat->dolos->grep(sub { $_->url eq $url })->size) {
        $errors{doloUrl} = [] unless defined $errors{doloUrl};
        push @{$errors{doloUrl}}, $c->l('You already have that URL in the dolos of this category.');
    }

    my $tags_id = $c->every_param('tags[]');
    my @tags;
    for my $tag_id (@{$tags_id}) {
        my $tag = Dolomon::Tag->new(app => $c->app, id => $tag_id);
        unless (defined $tag->user_id && $tag->user_id == $c->current_user->id) {
            $errors{tagList} = [] unless defined $errors{tagList};
            if (!defined $tag->user_id) {
                push @{$errors{tagList}}, $c->l('I can\'t find at least one of the given tag.');
            } else {
                push @{$errors{tagList}}, $c->l('At least one of the tag you want to use for your dolo does not belong to you.') unless (defined $tag->user_id && $tag->user_id == $c->current_user->id);
            }
        }
        push @tags, $tag;
    }

    return $c->render(
        json => {
            success => false,
            errors  => \%errors
        }
    ) if (scalar keys %errors);

    $dolo = $dolo->update({
        url           => $url,
        name          => $name,
        extra         => xml_escape($c->param('extra')),
        expires_at    => (defined $c->param('expires_at')    && $c->param('expires_at') ne '')    ? $c->param('expires_at')    : undef,
        expires_after => (defined $c->param('expires_after') && $c->param('expires_after') ne '') ? $c->param('expires_after') : undef,
        category_id   => $cat->id,
    });

    $dolo = $dolo->unbind_tags();
    for my $tag (@tags) {
        $tag->bind_to($dolo->id);
        push @{$dolo->tags}, $tag->id;
    }

    return $c->render(
        json => {
            success => true,
            msg     => $c->l("The dolo %1 has been successfully modified.", ($dolo->name || $dolo->url)),
            object  => $dolo->as_struct
        }
    );
}

sub delete {
    my $c  = shift;
    my $id = $c->param('id');

    my $dolo = Dolomon::Dolo->new(app => $c->app, id => $id);

    if (!defined($dolo->user_id) || $dolo->user_id != $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The dolo you\'re trying to delete does not belong to you.')
            }
        );
    }

    $dolo->delete();

    return $c->render(
        json => {
            success => true,
            msg     => $c->l('The dolo %1 has been successfully deleted.', $dolo->name)
        }
    );
}

sub hit {
    my $c     = shift;
    my $short = $c->param('short');

    my $dolo = Dolomon::Dolo->new(app => $c->app)->find_by_('short', $short);

    if ($dolo->id) {
        unless ($dolo->has_expired) {
            my $ref   = $c->req->headers->referrer;
            my $robot = HTTP::BrowserDetect->new($c->req->headers->user_agent)->robot();
            unless ($c->config('do_not_count_spiders') && defined $robot && $robot ne 'curl' && $robot ne 'wget') {
                if ($c->config('counter_delay') > 0) {
                    unless (defined $c->cookie($short)) {
                        # Set cookie that expires in $c->config('counter_delay') seconds
                        $c->cookie($short => 1, {expires => time + $c->config('counter_delay')}) unless $c->req->headers->dnt;

                        # Update counters
                        $c->app->minion->enqueue(hit => [$short, time, $ref]);
                    }
                } else {
                    $c->app->minion->enqueue(hit => [$short, time, $ref]);
                }
            }

            $c->res->code(302);
            return $c->redirect_to($dolo->url);
        } else {
            $c->stash(
                msg => {
                    title => $c->l('Error'),
                    class => 'alert-danger',
                    text  => $c->l('Sorry, this URL has expired')
                }
            );
        }
    } else {
        $c->stash(
            msg => {
                title => $c->l('Error'),
                class => 'alert-danger',
                text  => $c->l('Sorry, this URL does not exist.')
            }
        );
    }
    return $c->render(
        template => 'error'
    );
}

1;
