use v6;

unit package ModelDB;

class Schema {
    has $.dbh is required;

    method last-insert-rowid() {
        my $sth = $.dbh.prepare('SELECT last_insert_rowid()');
        $sth.execute;
        $sth.fetchrow[0];
    }
}

