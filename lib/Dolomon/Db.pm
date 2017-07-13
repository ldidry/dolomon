package Dolomon::Db;
use Mojo::Base -base;
use Mojo::Collection;
use Data::Structure::Util qw(unbless);

has 'table';
has 'app';
has 'id';

sub new {
    my $c = shift;
    $c = $c->SUPER::new(@_);

    if (defined $c->id) {
        $c = $c->find_by_('id', $c->id);
    }

    return $c;
}

sub create {
    my $c = shift;
    my $h = shift;

    my ($fields, $prepare, $values) = $c->map_fields_for_insert($h);

    my $r = $c->app->pg->db->query('INSERT INTO '.$c->table.' ('.$fields.') VALUES ('.$prepare.') RETURNING *', @{$values});

    if ($r->rows == 1) {
        $c->map_fields_to_attr($r->hash);
    }
    return $c;
}

sub update {
    my $c = shift;
    my $h = shift;

    my ($fields, $params) = $c->map_fields_for_update($h);
    push @{$params}, $c->id;

    my $q = join(', ', @{$fields});

    my $r = $c->app->pg->db->query('UPDATE '.$c->table.' SET '.$q.' WHERE id = ? RETURNING *;', @{$params});

    if ($r->rows == 1) {
        $c->map_fields_to_attr($r->hash);
    }
    return $c;
}

sub rename {
    my $c       = shift;
    my $newname = shift;

    my $r = $c->app->pg->db->query('UPDATE '.$c->table.' SET name = ? WHERE id = ? RETURNING name', ($newname, $c->id));
    $c->name($r->hash->{name});

    return ($c->name eq $newname) ? $c : undef;
}

sub delete {
    my $c = shift;

    # The CASCADE deletion is handled by the db schema where needed
    return $c->app->pg->db->query('DELETE FROM '.$c->table.' WHERE id = ?', $c->id);
}

sub is_name_taken {
    my $c = shift;
    my $n = shift;
    my $i = shift;
    my $f = shift || 'user_id';
    my $s = shift || 'name';

    return $c->app->pg->db->query('SELECT id FROM '.$c->table.' WHERE '.$s.' = ? AND '.$f.' = ?', ($n, $i))->rows;
}

sub as_struct {
    my $c = shift;

    if (defined $c->{short}) {
        my $url = $c->app->url_for('hit', short => $c->short)->to_abs."";
        $c->short($url);
    }
    $c->dolos($c->dolos->map(sub { $_->as_struct })) if defined $c->{dolos};
    $c->children($c->children->map(sub { $_->as_struct })) if defined $c->{children};
    delete $c->{app};
    delete $c->{db};
    delete $c->{table};
    delete $c->{user_id} if defined $c->{user_id};
    my $struct = unbless($c);

    return $struct;
}

# Find a record and map fields as attributes if found
sub find_by_ {
    my $c = shift;
    my $i = shift;
    my $j = shift;

    my $r = $c->app->pg->db->query('SELECT * FROM '.$c->table.' WHERE '.$i.' = ?;', $j);

    $c->map_fields_to_attr($r->hash) if $r->rows == 1;

    return $c;
}

# Find a record by multiple fields and map fields as attributes if found
sub find_by_fields_ {
    my $c = shift;
    my $h = shift;

    my ($fields, $values) = $c->map_attr_for_select($h);
    my $r = $c->app->pg->db->query('SELECT * FROM '.$c->table.' WHERE '.$fields, @{$values});
    $c->map_fields_to_attr($r->hash) if $r->rows == 1;

    return $c;
}

# Map fields as attributes
sub map_fields_to_attr {
    my $c = shift;
    my $h = shift;
    while (my ($k, $v) = each %{$h}) {
        # Add each field as object's attribute
        $c->{$k} = $v;
    }

    return $c;
}

# Transform hash reference as two array refs:
# ['field1 = ?, 'field2' = ?'] and [value1, value2]
sub map_fields_for_update {
    my $c = shift;
    my $f = shift;

    my @fields = ();
    for my $key (keys %{$f}) {
        push @fields, $key.' = ?';
    }
    my @params = values %{$f};

    return (\@fields, \@params);
}

# Transform hash reference as two strings and an array ref:
# 'field1, field2', '?, ?', [value1, value2]
sub map_fields_for_insert {
    my $c = shift;
    my $f = shift;

    my @i = ();
    my @fields = keys %{$f};
    my @params = values %{$f};
    for (1..scalar(@fields)) {
        push @i, '?';
    }

    return(join(', ', @fields), join(', ', @i), \@params);
}

# Transform array reference as a string and an array ref providing 
# corresponding object attribute value;
# 'field1 = ? AND field2 = ?' and [attribute_field1, attribute_field2]
sub map_attr_for_select {
    my $c = shift;
    my $h = shift;

    my @fields = ();
    my @values = ();
    for my $key (@{$h}) {
        push @fields, $key.' = ?';
        push @values, $c->{$key};
    }

    return (join(' AND ', @fields), \@values);
}

1;
