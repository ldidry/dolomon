package Dolomon::Dolo;
use Mojo::Base 'Dolomon::DoloCommon';
use Mojo::Collection;
use DateTime;
use DateTime::Format::Pg;

has 'table' => 'dolos';
has 'url';
has 'short';
has 'name';
has 'extra';
has 'count';
has 'initial_count';
has 'category_id';
has 'category_name';
has 'user_id',
has 'parent_id';
has 'created_at';
has 'expired';
has 'expires_at';
has 'expires_after';
has 'children' => sub {
    return Mojo::Collection->new();
};
has 'tags' => sub {
    return [];
};

# Find a record and map fields as attributes if found
sub find_by_ {
    my $c = shift;
    my $i = shift;
    my $j = shift;

    my $r = $c->app->pg->db->query('SELECT d.id, d.url, d.short, d.name, d.extra, d.count, d.initial_count, d.category_id, d.parent_id, d.created_at, d.expired, d.expires_at, d.expires_after, c.name AS category_name, c.user_id FROM '.$c->table.' d JOIN categories c ON d.category_id = c.id WHERE d.'.$i.' = ?', $j);
    my $h = $r->hash;

    $c->map_fields_to_attr($h) if $r->rows == 1;

    my @achild = ();
    my $children = $c->app->pg->db->query('SELECT d.id, d.url, d.short, d.name, d.extra, d.count, d.initial_count, d.category_id, d.parent_id, d.created_at, d.expired, d.expires_at, d.expires_after, c.name AS category_name, c.user_id FROM '.$c->table.' d JOIN categories c ON d.category_id = c.id WHERE d.parent_id = ?', $h->{id})->hashes;
    $children->each(sub {
        my ($e, $num) = @_;
        my $child = Dolomon::Dolo->new(app => $c->app)
            ->category_id($e->{category_id})
            ->category_name($h->{category_name})
            ->id($e->{id})
            ->url($e->{url})
            ->short($e->{short})
            ->name($e->{name})
            ->extra($e->{extra})
            ->parent_id($e->{parent_id})
            ->count($e->{count})
            ->created_at($e->{created_at})
            ->expired($e->{expired})
            ->expires_at($e->{expires_at})
            ->expires_after($e->{expires_after});

        my $tags = $c->app->pg->db->query('SELECT t.id, t.name FROM dolo_has_tags d JOIN tags t ON t.id = d.tag_id WHERE d.dolo_id = ? ORDER BY t.name', $e->{id})->hashes;
        my @atags;
        $tags->each(sub {
            my ($t, $num) = @_;
            push @atags, $t;
        });
        $child->tags(\@atags);
        push @achild, $child;
    });
    $c->children(Mojo::Collection->new(@achild));

    my @atags;
    my $tags = $c->app->pg->db->query('SELECT t.id, t.name FROM dolo_has_tags d JOIN tags t ON t.id = d.tag_id WHERE d.dolo_id = ? ORDER BY t.name', $h->{id})->hashes;
    $tags->each(sub {
        my ($e, $num) = @_;
        push @atags, $e;
    });
    $c->tags(\@atags);

    return $c;
}

sub has_expired {
    my $c = shift;

    return 1 if $c->expired;

    if (defined($c->expires_at)) {
        my $now        = DateTime->now();
        my $expires_at = DateTime::Format::Pg->parse_timestamp_with_time_zone($c->created_at)->add(days => $c->expires_at);
        if (DateTime->compare($now, $expires_at) > 0) {
            $c->update({ expired => 1 });
            return 1;
        }
    }

    return 0;
}

sub delete {
    my $c = shift;

    $c->app->pg->db->query('UPDATE users SET count = count - '.$c->count.' WHERE id = ?', $c->user_id);

    # The CASCADE deletion is handled by the db schema where needed
    return $c->app->pg->db->query('DELETE FROM '.$c->table.' WHERE id = ?', $c->id);
}

sub unbind_tags {
    my $c = shift;

    $c->app->pg->db->query('DELETE FROM dolo_has_tags WHERE dolo_id = ?', $c->id);
    $c->tags([]);

    return $c;
}

sub get_raw_dys {
    my $c = shift;

    return $c->app->pg->db->query('SELECT * from dolos_year WHERE dolo_id = ? ORDER BY year ASC', $c->id)->hashes;
}

sub get_raw_dms {
    my $c = shift;

    return $c->app->pg->db->query('SELECT * from dolos_month WHERE dolo_id = ? ORDER BY year, month ASC', $c->id)->hashes;
}

sub get_raw_dws {
    my $c = shift;

    return $c->app->pg->db->query('SELECT * from dolos_week WHERE dolo_id = ? ORDER BY year, week ASC', $c->id)->hashes;
}

sub get_raw_dds {
    my $c = shift;

    return $c->app->pg->db->query('SELECT * from dolos_day WHERE dolo_id = ? ORDER BY year, month, day ASC', $c->id)->hashes;
}

sub get_raw_dhs {
    my $c = shift;

    return $c->app->pg->db->query('SELECT * from dolos_hits WHERE dolo_id = ? ORDER BY ts ASC', $c->id)->hashes;
}

1;
