use v6.d;

use ModelDB::Collection;
use ModelDB::Schema;
use ModelDB::Object;

class ModelDB::Collection::Table { ... }

=begin pod

=head1 NAME

ModelDB::Table - load, save, and find model data

=head1 SYNOPSIS

    use ModelDB;

    module Model {
        use ModelDB::ModelBuilder;
        model Animal {
            has Int $.animal-id is column is primary;
            has Str $.name is column is rw;
        }
    }

    my ModelDB::Schema $schema .= new(...);
    my ModelDB::Table[Model::Animal] $animals .= new(
        :$schema, :table<animals>
    );

    my $cow = $animals.create(%(:name<Cow>));
    my $pig = $animals.create(%(:name<Pig>));

    my $sheep = $animals.find(:animal-id(4));

    $pig.name = 'Zombie Pigman';
    $animals.update($pig);

=head1 DESCRIPTION

A table provides the operations necessary for loading, searching, saving, and otherwise working with a model object in a concrete way involving a backing store.

The L<#SYNOPSIS> demonstrates how to create table objects directly. However, you will most likely want to do this indirectly through the L<ModelDB::SchemaBuilder>.

=head1 METHODS

=head2 method schema

    has ModelDB::Schema $.schema is required

This is the schema to use for manipulating data.

=head2 method table

    has Str $.table is required

This is the name of the RDBMS table to use.

=head2 method model

    method model(--> ::Model)

This is the model class.

=head2 method escaped-table

    method escaped-table(--> Str)

TODO This does not belong here.

Provides a SQL escaped name for the table.

=head2 method escaped-columns

    multi method escaped-columns(--> Str)
    multi method escaped-columns(@names --> Str)

TODO This does not belong here.

Provides SQL escaped names for columns.

=head2 method select-columns

    method select-columns(%columns --> Seq)

TODO This does not belong here.

Generates a data structure for selecting columns.

=head2 method process-where

    method process-where(%where --> Str)

TODO This is primitive.

Generates a where clause.

=head2 method find

    multi method find(%keys --> ::Model)

Returns the model object with the given primary key or returns C<Nil>.

=head2 method create

    method create(%values, Str :$onconflict)

Creates a model object and returns it.

=head2 method update

    method update(::Model $row)

Given a model object, updates the database to match.

=head2 method delete

    multi method delete(:%where, :$DELETE-ALL)

Deletes objects matching the given where clause. Either the C<%where> argument
or the C<$DELETE-ALL> argument must be present. When given, the C<%where>
argument must have at least one constraint.

    # Delete all records where name == "Fred"
    $table.delete(where => %( name => 'Fred' ));

If C<$DELETE-ALL> is present, then the argument that is given must be a list
containing the words "I", "AM", and "SURE" in that order or the method will
fail.

    # Delete all records from this table
    $table.delete(:DELETE-ALL<I AM SURE>);

=head2 method search

    method search(*%search --> ModelDB::Collection)

Returns a collection of objects matching the given where clause.

=end pod

role ModelDB::Table[::Model] {
    has ModelDB::Schema $.schema is required;
    has Str $.table is required;

    method model() { Model }

    my sub sql-escape(Str:D $name) returns Str:D {
        $name.trans(['`'] => ['``']);
    }

    my sub sql-quote(Str:D $name) returns Str:D {
        '`' ~ $name ~ '`'
    }

    my &sql-quote-escape = &sql-quote o &sql-escape;

    has $!escaped-table;
    method escaped-table() returns Str {
        $!escaped-table //= sql-escape($!table);
        $!escaped-table
    }

    has @!escaped-columns;
    method !init-escaped-columns() {
        @!escaped-columns = $.model.^column-names.map({ $_ => sql-escape($_) })
            if @!escaped-columns.elems != $.model.^columns.elems;
    }
    multi method escaped-columns() {
        self!init-escaped-columns();
        @!escaped-columns.map({ .value });
    }

    multi method escaped-columns(@names) {
        my $name-matcher = any(|@names);
        self!init-escaped-columns();
        @!escaped-columns.grep({ .key ~~ $name-matcher }).map({ .value });
    }

    multi method escaped-columns(@names, Str :$join!) {
        self.escaped-columns(@names).map(&sql-quote).join($join);
    }

    multi method escaped-columns(Str :$join!) returns Str {
        $.escaped-columns.map(&sql-quote).join($join);
    }

    method select-columns($selector) {
        gather for $.model.^column-names.kv -> $i, $c {
            take self.escaped-columns[$i] if $c ~~ $selector;
        }
    }

    method process-where(%where) {
        return ('',) unless %where;

        my @and-clauses;
        my @bindings;
        for %where.kv -> $column, $value {
            my $escaped = sql-quote-escape($column);
            push @and-clauses, "$escaped = ?";
            push @bindings, $value;
        }

        "WHERE " ~ @and-clauses.join(' AND '), |@bindings
    }

    method construct(%values) {
        for $.model.^attributes -> $attr {
            ...
            # HERE we need something to auto-coerce from SQL
        }
    }

    multi method find(%keys) {
        my ($where, @bindings) = self.process-where(%keys);

        my (%first, %second);
        my $columns = self.escaped-columns(:join<,>);
        $.schema.connector.run: -> $dbh {
            my $sth = $dbh.prepare(qq:to/END_STATEMENT/);
                SELECT $columns
                FROM `$.escaped-table`
                $where
                END_STATEMENT

            $sth.execute(|@bindings);

            %first  = $sth.fetchrow-hash;
            %second = $sth.fetchrow-hash;
        }

        return Nil unless %first;
        die "more than a single row found by .find()" if %second;

        $.model.new(|%first, :sql-load);
    }

    multi method find(*%keys) { self.find(%keys) }

    multi method create(%values, Str :$onconflict) {
        my $row = $.model.new(|%values);

        # FIXME Something is not right here. The escape-columns() stuff
        # builds a map of sql-column-name => escaped-sql-column-name. However,
        # the values the Perl developer is expected to use are the
        # $.attribute-name without "$." on the front. A remedy for this will
        # be needed at some point when sql-column-name ne attribute-name.
        # For the moment, unfortunately, it is a necessary expedient for me to
        # move onto different problems and live with this discrepency.
        my $column-names = self.escaped-columns(%values.keys, :join<,>);

        my $conflict = '';
        if defined $onconflict && $onconflict ~~ any(<ignore>) {
            $conflict = " OR " ~ uc $onconflict;
        }

        my @binds = $.model.^columns
            .grep({ %values{ .name.substr(2) }:exists })
            .map(-> $col {
                my $getter = $col.getter-name;
                $col.save-filter(%values{$col.getter-name});
            });

        $.schema.connector.run: -> $dbh {
            my $sth = $dbh.prepare(qq:to/END_STATEMENT/);
                INSERT$conflict INTO `$.escaped-table` ($column-names)
                VALUES ({('?' xx %values).join(',')})
                END_STATEMENT

            $sth.execute(@binds);

            my $id = $.schema.connector.last-insert-rowid($dbh);
            if $id == 0 && defined $onconflict {
                return self.find(%values);
            }

            $row.save-id($id);
        }

        $row;
    }

    multi method create(ModelDB::Object:D $row, Str :$onconflict) {
        my %values = $row.create-values;
        self.create(%values, :$onconflict);
    }

    method update($row) {
        die "Wrong model; expected $.model but got $row.WHAT()"
            unless $row ~~ $.model;

        my $id-column-attr-name = $.model.HOW.id-column;
        my $id-column = $id-column-attr-name.substr(2);
        my $id-value  = $row."$id-column"();

        my ($where, @where-bindings) = self.process-where({
            $id-column => $id-value,
        });

        my @settings = $.model.^columns
            .grep({ .name ne $id-column-attr-name && .rw })
            .map(-> $col {
                my $getter = $col.name.substr(2);
                my $value  = $col.save-filter($row."$getter"());
                $col.column-name => $value;
            });

        my @set-names    = self.escaped-columns(@settings».key);
        my @set-bindings = @settings».value;

        $.schema.connector.run: -> $dbh {
            my $sth = $dbh.prepare(qq:to/END_STATEMENT/);
                UPDATE `$.escaped-table`
                SET @set-names.map({ "{sql-quote($_)} = ?" }).join(',')
                $where
                END_STATEMENT

            $sth.execute(|@set-bindings, |@where-bindings);
        }
    }

    multi method delete(:%where!) {
        die "To use empty WHERE clause during delete, use the :DELETE-ALL<I AM SURE>, option."
            unless %where;

        my ($where, @bindings) = self.process-where(%where);

        my $sql = qq:to/END_STATEMENT/;
            DELETE FROM `$.escaped-table`
            $where
            END_STATEMENT

        $.schema.connector.run: -> $dbh {
            my $sth = $dbh.prepare($sql);

            $sth.execute(|@bindings);
        }
    }

    multi method delete(:$DELETE-ALL!) {
        die "To use empty WHERE clause during delete, use the :DELETE-ALL<I AM SURE>, option."
            unless $DELETE-ALL eqv <I AM SURE>;

        my $sql = qq:to/END_STATEMENT/;
            DELETE FROM `$.escaped-table`
            END_STATEMENT

        $.schema.connector.run: -> $dbh {
            my $sth = $dbh.prepare($sql);

            $sth.execute;
        }
    }

    multi method search(%search) returns ModelDB::Collection {
        ModelDB::Collection::Table.new(:table(self), :%search);
    }

    multi method search(*%search) { self.search(%search) }
}

class ModelDB::Collection::Table does ModelDB::Collection {
    has ModelDB::Table $.table;

    method all() {
        my ($where, @bindings) = $.table.process-where(%.search);

        my $columns = $.table.escaped-columns(:join<,>);
        $.table.schema.connector.run: -> $dbh {
            my $sth = $dbh.prepare(qq:to/END_STATEMENT/);
                SELECT $columns
                FROM `$.table.escaped-table()`
                $where
                END_STATEMENT

            $sth.execute(|@bindings);

            eager $sth.allrows(:array-of-hash).map({ $.table.model.new(|$_, :sql-load) })
        }
    }
}

