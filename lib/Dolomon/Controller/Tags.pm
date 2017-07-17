package Dolomon::Controller::Tags;
use Mojo::Base 'Mojolicious::Controller';
use Dolomon::Tag;
use Mojo::JSON qw(true false);
use DateTime::Format::Pg;
use DateTime::Duration;
use Math::Round 'nlowmult';
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

sub index {
    my $c = shift;

    $c->respond_to(
        json => {
            json => $c->current_user->get_tags()->map(sub { $_->as_struct })->to_array
        },
        any => {
            template   => 'tags/index',
            tags => $c->current_user->get_tags()
        }
    );
}

sub get {
    my $c  = shift;
    my $id = $c->param('id');

    if (defined $id) {
        my $tag = Dolomon::Tag->new(app => $c->app, id => $id);
        unless ($tag->user_id == $c->current_user->id) {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('The tag you\'re trying to get does not belong to you.')
                }
            );
        }
        return $c->render(
            json => {
                success => true,
                object  => $tag->as_struct
            }
        );
    } else {
        return $c->render(
            json => {
                success => true,
                object  => $c->current_user->get_tags()->map(sub { $_->as_struct })->to_array
            }
        );
    }
}

sub show {
    my $c      = shift;
    my $id     = $c->param('id');

    my ($msg, %agg_referrers);
    my $tag = Dolomon::Tag->new(app => $c->app, id => $id);
    unless (defined $tag->user_id && $tag->user_id == $c->current_user->id) {
        $msg = {
            class => 'alert-warning',
            title => $c->l('Error'),
            text  => $c->l('The tag you\'re trying to show does not belong to you or does not exist.')
        };
    } else {
        my $dhs = $tag->get_raw_dhs;
        $dhs->each(sub {
            my ($e, $num) = @_;

            if ($e->{referrer}) {
                $agg_referrers{$e->{referrer}}  = 0 unless defined $agg_referrers{$e->{referrer}};
                $agg_referrers{$e->{referrer}} += 1;
            }
        });
    }

    return $c->render(
        template  => 'tags/show',
        msg       => $msg,
        tag       => (defined $msg) ? undef : $tag,
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

    my $tag = Dolomon::Tag->new(app => $c->app, id => $id);
    unless (defined $tag->user_id && $tag->user_id == $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The tag you\'re trying to get does not belong to you.')
            }
        );
    }

    my (@data, $min, $max);
    if ($period eq 'years') {
        my $dys = $tag->get_raw_dys;
        $dys->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year})->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dys->size;
        });
    } elsif ($period eq 'months') {
        my $dms = $tag->get_raw_dms;
        $dms->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year}, month => $e->{month})->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dms->size;
        });
    } elsif ($period eq 'weeks') {
        my $dws = $tag->get_raw_dws;
        $dws->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year}, month => 1, day => 4 )->add(weeks => $e->{week} - 1)->truntage( to => 'week' )->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dws->size;
        });
    } elsif ($period eq 'days') {
        my $dds = $tag->get_raw_dds;
        $dds->each(sub {
            my ($e, $num) = @_;
            my $time = DateTime->new(year => $e->{year}, month => $e->{month}, day => $e->{day})->set_time_zone('UTC')->epoch();
            push @data, { x => $time, value => $e->{count} };
            $min = $time unless defined ($min);
            $max = $time if $num == $dds->size;
        });
    } elsif ($period eq 'hits') {
        my $dhs = $tag->get_raw_dhs;
        my %agg_hits;
        $dhs->each(sub {
            my ($e, $num) = @_;

            my $dt = DateTime::Format::Pg->parse_timestamp_with_time_zone($e->{ts})->set_time_zone('UTC');

            my $duration = DateTime::Duration->new(minutes => nlowmult($agg, ($dt->hour * 60 + $dt->minute)));
            $dt->truntage(to => 'day');
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
            object  => $tag->as_struct
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

    my $tag = Dolomon::Tag->new(app => $c->app, id => $id);
    unless (defined $tag->user_id && $tag->user_id == $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The tag you\'re trying to get does not belong to you.')
            }
        );
    }

    my $zip = Archive::Zip->new();

    # Years
    my $csv = '"Year","Count"'."\n";
    my $dys = $tag->get_raw_dys;
    $dys->each(sub {
        my ($e, $num) = @_;
        $csv .= '"'.$e->{year}.'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'years.csv');

    # Months
    $csv = '"Year","Month","Count"'."\n";
    my $dms = $tag->get_raw_dms;
    $dms->each(sub {
        my ($e, $num) = @_;
        $csv .= '"'.$e->{year}.'","'.$e->{month}.'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'months.csv');

    # Weeks
    $csv = '"Year","Week","Count"'."\n";
    my $dws = $tag->get_raw_dws;
    $dws->each(sub {
        my ($e, $num) = @_;
        my $time = DateTime->new(year => $e->{year}, month => 1, day => 4 )->add(weeks => $e->{week} - 1)->truncate( to => 'week' )->set_time_zone('UTC');
        $csv .= '"'.$time->week_year().'","'.$time->week_number().'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'weeks.csv');

    # Days
    $csv = '"Year","Month","Day","Count"'."\n";
    my $dds = $tag->get_raw_dds;
    $dds->each(sub {
        my ($e, $num) = @_;
        $csv .= '"'.$e->{year}.'","'.$e->{month}.'","'.$e->{day}.'","'.$e->{count}.'"'."\n";
    });
    $zip->addString($csv, 'days.csv');

    # Hits
    $csv = '"Timestamp","Count"'."\n";
    my $dhs = $tag->get_raw_dhs;
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
    $headers->add('Content-Type'        => 'application/zip;name=export-tag-'.$id.'.zip');
    $headers->add('Content-Disposition' => 'attachment;filename=export-tag-'.$id.'.zip');
    $c->res->content->headers($headers);

    my $asset = Mojo::Asset::File->new(path => $zipfile);
    $c->res->content->asset($asset);
    $headers->add('Content-Length' => $asset->size);

    unlink $zipfile;

    return $c->rendered(200);
}

sub add {
    my $c    = shift;
    my $name = $c->param('name');

    if (defined $name && $name ne '') {
        my $tag = Dolomon::Tag->new(app => $c->app);
        unless ($tag->is_name_taken($name, $c->current_user->id)) {
            $tag->create({user_id => $c->current_user->id, name => $name});

            if (defined $tag) {
                return $c->render(
                    json => {
                        success    => true,
                        msg        => $c->l('The tag %1 has been successfully created.', $tag->name),
                        object     => $tag->as_struct
                    }
                );
            } else {
                return $c->render(
                    json => {
                        success => false,
                        msg     => $c->l('Unable to create tag %1. Please contact the administrator.', $name)
                    }
                );
            }
        } else {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('Unable to create tag %1, this name is already taken. Choose another one.', $name)
                }
            );
        }
    } else {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('Tag name blank or undefined. I refuse to create an tag without name.')
            }
        );
    }
}

sub rename {
    my $c       = shift;
    my $id      = $c->param('id');
    my $newname = $c->param('name');

    if (defined $newname && $newname ne '') {
        my $tag  = Dolomon::Tag->new(app => $c->app, id => $id);
        my $name = $tag->name;
        unless ($tag->user_id == $c->current_user->id) {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('The tag you\'re trying to rename does not belong to you.')
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
        my $result = $tag->rename($newname);

        if (defined $result) {
            return $c->render(
                json => {
                    success => true,
                    msg     => $c->l('The tag %1 has been successfully renamed to %2', ($name, $newname)),
                    newname => $result->name
                }
            );
        } else {
            return $c->render(
                json => {
                    success => false,
                    msg     => $c->l('Something went wrong while renaming tag %1 to %2', ($name, $newname))
                }
            );
        }
    } else {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('New tag name blank or undefined. I refuse to rename the tag.')
            }
        );
    }
}

sub delete {
    my $c  = shift;
    my $id = $c->param('id');

    my $tag = Dolomon::Tag->new(app => $c->app, id => $id);

    if ($tag->user_id != $c->current_user->id) {
        return $c->render(
            json => {
                success => false,
                msg     => $c->l('The tag you\'re trying to delete does not belong to you.')
            }
        );
    }

    $tag->delete();

    return $c->render(
        json => {
            success => true,
            msg     => $c->l('The tag %1 has been successfully deleted.', $tag->name)
        }
    );
}

1;
