package Dolomon::Dolo;
use Mojo::Base 'Dolomon::DoloCommon';
use Mojo::Collection;

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

    my $r = $c->app->pg->db->query('SELECT d.id, d.url, d.short, d.name, d.extra, d.count, d.initial_count, d.category_id, d.parent_id, d.created_at, c.name AS category_name, c.user_id FROM '.$c->table.' d JOIN categories c ON d.category_id = c.id WHERE d.'.$i.' = ?', $j);
    my $h = $r->hash;

    $c->map_fields_to_attr($h) if $r->rows == 1;

    my @achild = ();
    my $children = $c->app->pg->db->query('SELECT id, url, short, name, extra, count, initial_count, category_id, parent_id, created_at FROM dolos WHERE parent_id = ? ORDER BY id', $h->{id})->hashes;
    $children->each(sub {
        my ($e, $num) = @_;
        my $child = Dolomon::Dolo->new(app => $c->app)
            ->category_id($e->id)
            ->category_name($h->{category_name})
            ->id($e->{id})
            ->url($e->{url})
            ->short($e->{short})
            ->name($e->{name})
            ->extra($e->{extra})
            ->parent_id($e->{parent_id})
            ->count($e->{count})
            ->created_at($e->{created_at});

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
