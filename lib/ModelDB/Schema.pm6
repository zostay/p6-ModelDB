use v6;

unit package ModelDB;

=begin pod

=head1 DESCRIPTION

A schema is a collection of models.

=head1 METHODS

=head2 method dbh

    has $.dbh is required

=head2 method last-insert-rowid

    method last-insert-rowid(--> Any)

=end pod

class Schema {
    has $.dbh is required;

    method last-insert-rowid() {
        my $sth = $.dbh.prepare('SELECT last_insert_rowid()');
        $sth.execute;
        $sth.fetchrow[0];
    }
}

