# vim:set sw=4 ts=4 sts=4 ft=perl expandtab:
package Dolomon::BreakingChange;
use Mojo::Base 'Dolomon::Db';
use Mojo::File;
use Mojo::Collection 'c';

has 'table' => 'breakingchanges';
has 'change';
has 'ack' => 0;
has 'app';

=head1 NAME

Dolomon::BreakingChange - DB abstraction layer for Dolomon breaking changes

=head1 Attributes

=over 1

=item B<change> : string, name of the change

=item B<ack>    : boolean, if the admin has acknowledged the change

=item B<app>    : a Mojolicious object

=back

=head1 Sub routines

=head2 new

=over 1

=item B<Usage>     : C<$c = Dolomon::BreakingChange-E<gt>new(app =E<gt> $self);>

=item B<Arguments> : any of the attribute above

=item B<Purpose>   : construct a new db accessor object. If the C<change> attribute is provided, it have to load the informations from the database.

=item B<Returns>   : the db accessor object

=back

=cut

sub new {
    my $c = shift;

    $c = $c->SUPER::new(@_);

    if (defined $c->change) {
        $c = $c->find_by_('change', $c->change);
    }

    return $c;
}

=head2 ack

=over 1

=item B<Usage>     : C<$c-E<gt>acknowledge>

=item B<Arguments> : none

=item B<Purpose>   : update the database with the C<ack> flag set to true and update the db accessor object accordingly

=item B<Returns>   : the db accessor object

=back

=cut

sub acknowledge {
    my $c = shift;

    my $r = $c->app->pg->db->query('UPDATE '.$c->table.' SET ack = true WHERE change = ? RETURNING *;', $c->change);

    $c->ack(1) if ($r->rows == 1);

    return $c;
}

1;
