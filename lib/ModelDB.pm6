use v6;

class ModelDB::Schema {
    has $.dbh is required;

    method last-insert-rowid() {
        my $sth = $.dbh.prepare('SELECT last_insert_rowid()');
        $sth.execute;
        $sth.fetchrow[0];
    }

    method changes() {
        my $sth = $.dbh.prepare('SELECT changes()');
        $sth.execute;
        $sth.fetchrow[0].Int;
    }
}

role ModelDB::Column[$column-name] {
    has &.when-loading;
    has &.when-saving;

    method column-name() { $column-name }

    method load-filter(Mu $v) {
        with &.when-loading {
            &.when-loading.($.name, $v);
        }
        else {
            self.default-load-filter($v);
        }
    }

    method default-load-filter($v) {
        with $v {
            my $x = do given self.type {
                when Bool { ?+$v }
                when Int { $v.Int }
                default { $v }
            }
            #dd self.type;
            #note "Int?  {self.type ~~ Int}";
            #note "Bool? {self.type ~~ Bool}";
            #dd $v;
            #dd ?$v;
            #dd +$v;
            #dd ?+$v;
            #dd $x;
            $x;
        }
        else {
            self.type
        }
    }

    method save-filter(Mu $v) {
        with &.when-saving {
            &.when-saving.($.name, $v);
        }
        else {
            self.default-load-filter($v);
        }
    }

    method default-save-filter($v) {
        with $v {
            given self.type {
                when Bool { $v ?? 1 !! 0 }
                default { ~$v }
            }
        }
        else {
            Str
        }
    }
}

class ModelDB::Model {
    method new(|c) {
        my $c = c;
        if c.hash<sql-load> {
            my %hash;
            for c.hash.kv -> $c, $v {
                if (my $attr = self.^attributes.first({ .name eq '$!' ~ $c })) ~~ ModelDB::Column {
                    #note "HERE $attr.name() <- $attr.load-filter($v)";
                    %hash{ $c } = $attr.load-filter($v);
                }
                else {
                    %hash{ $c } = $v;
                }
            }

            $c = Capture.new(:%hash, :list(c.list));
            #dd $c;
        }

        nextwith(|$c);
    }

    method save-id($id) {
        my $attr = self.^attributes.first({ .name eq self.HOW.id-column });
        return unless $attr;
        my $filter-id = $attr.load-filter($id);
        $attr.set_value(self, $filter-id);
    }
}

class MetamodelX::DBModelHOW is Metamodel::ClassHOW {
    has Str $.id-column is rw;
    has %.index;

    # method add_attribute(Mu $obj, Mu $meta_attr) {
    #     nextwith($obj, $meta_attr but ModelDB::Column);
    # }
    method columns($model) {
        $model.^attributes.grep(ModelDB::Column)
    }

    method column-names($model) {
        $model.^attributes.grep(ModelDB::Column)».column-name;
    }

    method compose(Mu \type) {
        self.add_parent(type, ModelDB::Model);
        self.Metamodel::ClassHOW::compose(type);
    }
}

class ModelDB::Collection { ... }

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

        my $columns = self.escaped-columns(:join<,>);
        my $sth = self.schema.dbh.prepare(qq:to/END_STATEMENT/);
            SELECT $columns
            FROM `$.escaped-table`
            $where
            END_STATEMENT

        $sth.execute(|@bindings);

        $.model.new(|$sth.fetchrow-hash, :sql-load);
    }

    multi method find(*%keys) { self.find(%keys) }

    method create(%values, Str :$onconflict) {
        my $row = $.model.new(|%values);

        my @columns = self.select-columns(%values);

        my $conflict = '';
        if defined $onconflict && $onconflict ~~ any(<ignore>) {
            $conflict = " OR " ~ uc $onconflict;
        }

        my $sth = $.schema.dbh.prepare(qq:to/END_STATEMENT/);
            INSERT$conflict INTO `$.escaped-table` (@columns.map(&sql-quote).join(','))
            VALUES (@columns.map({ '?' }).join(','))
            END_STATEMENT

        $sth.execute(|%values{ @columns });

        my $id = $.schema.last-insert-rowid;
        if $id == 0 && defined $onconflict {
            return self.find(%values);
        }

        $row.save-id($id);

        $row;
    }

    method update($row) {
        die "Wrong model; expected $.model but got $row.WHAT()"
            unless $row ~~ $.model;

        my $id-column = $.model.HOW.id-column.substr(2);
        my $id-value  = $row."$id-column"();

        my ($where, @where-bindings) = self.process-where({
            $id-column => $id-value,
        });

        my @settings = $.model.^columns.map(-> $col {
            my $getter = $col.name.substr(2);
            my $value  = $col.save-filter($row."$getter"());
            $col.column-name => $value;
        });

        my @set-names    = self.escaped-columns(@settings».key);
        my @set-bindings = @settings».value;

        my $sth = $.schema.dbh.prepare(dd qq:to/END_STATEMENT/);
            UPDATE `$.escaped-table`
               SET @set-names.map({ "{sql-quote($_)} = ?" }).join(',')
             $where
            END_STATEMENT

        dd @set-bindings;
        dd @where-bindings;
        $sth.execute(|@set-bindings, |@where-bindings);
    }

    method delete(:%where) {
        my ($where, @bindings) = self.process-where(%where);

        my $sql = qq:to/END_STATEMENT/;
            DELETE FROM `$.escaped-table`
            $where
            END_STATEMENT

        my $sth = $.schema.dbh.prepare($sql);

        $sth.execute(|@bindings);
    }

    multi method search(%search) returns ModelDB::Collection {
        ModelDB::Collection.new(:table(self), :%search);
    }

    multi method search(*%search) { self.search(%search) }
}

class ModelDB::Collection {
    has ModelDB::Table $.table;
    has %.search;

    method all() {
        my ($where, @bindings) = $.table.process-where(%.search);

        my $columns = $.table.escaped-columns(:join<,>);
        my $sth = $.table.schema.dbh.prepare(qq:to/END_STATEMENT/);
            SELECT $columns
            FROM `$.table.escaped-table()`
            $where
            END_STATEMENT

        $sth.execute(|@bindings);

        $sth.allrows(:array-of-hash).map({ $.table.model.new(|$_, :sql-load) })
    }
}

role ModelDB::TableBuilder[Str $table] {
    method compose(Mu $package) {
        callsame;
        my $attr = self;
        if $attr.has_accessor {
            my $name = self.name.substr(2);
            $package.^method_table{$name}.wrap(
                method (|) {
                    without $attr.get_value(self) {
                        $attr.set_value(self,
                            $attr.type.new(
                                table  => $table,
                                schema => self,
                            )
                        );
                    }
                    callsame;
                }
            );
        }
    }
}

role ModelDB::RelationshipSetup[Str $relationship-name, Str $schema-ref] {
    #     method compose(Mu $package) {
    #         callsame;
    #         if self.has_accessor {
    #             my $name = self.name.substr(2);
    #             $package.^method_table{$name}.wrap(
    #                 method (|) {
    #                     (my $value = callsame)
    #                         andthen $value."_set-key-for-$relationship-name"($schema-ref);
    #                     $value;
    #                 }
    #             );
    #         }
    #     }
}

sub belongs-to(
    Str :$relationship,
    Str :$local-index,
    Mu :$foreign-class,
    Str :$foreign-index = 'PRIMARY',
) is export {
    my \type = callframe(1).my<?::PACKAGE>;

    my $relationship-key;
    type.^add_method("_set-key-for-$relationship", method ($key) {
        $relationship-key = $key;
    });

    type.^add_method($relationship, method (ModelDB::Schema $schema = $*DB-SCHEMA) {
        my @theirs = $foreign-class.^index{ $foreign-index };
        my @ours   = self.^index{ $local-index };

        my %key = zip(@theirs, @ours).map: -> ($their-attr, $our-attr) {
            my $their-key = $their-attr.name.substr(2);
            my $our-key   = $our-attr.name.substr(2);
            my $value     = self."$our-key"();

            $their-key => $value;
        };

        $schema."$relationship-key"().find(|%key);
    });
}

multi trait_mod:<is> (Attribute $attr, Str:D :$table!) is export {
    $attr does ModelDB::TableBuilder[$table]
}

multi trait_mod:<is> (Attribute $attr, :$table!) is export {
    $attr does ModelDB::TableBuilder[$attr.name.substr(2)]
}

multi trait_mod:<is> (Attribute $attr, Str:D :$column!) is export {
    die "columns must be added to models" unless $attr.package.HOW ~~ MetamodelX::DBModelHOW;
    $attr does ModelDB::Column[$column];
}

multi trait_mod:<is> (Attribute $attr, :$column!) is export {
    die "columns must be added to models" unless $attr.package.HOW ~~ MetamodelX::DBModelHOW;
    $attr does ModelDB::Column[$attr.name.substr(2)];
}

multi trait_mod:<is> (Attribute $attr, :$primary!) is export {
    $attr.package.HOW.id-column = $attr.name;
    $attr.package.HOW.index<PRIMARY> = [ $attr ];
}

multi trait_mod:<is> (Attribute $attr, :@indexed!) is export {
    my ($index-name, $pos) = |@indexed;
    die "index name is required" without $index-name;
    $attr.package.HOW.index{ $index-name } //= [];
    $pos //= $attr.package.HOW.index{ $index-name }.elems;
    $attr.package.HOW.index{ $index-name }[ $pos ] = $attr;
}

multi trait_mod:<is> (Attribute $attr, :$indexed!) is export {
    my $index-name = $attr.name.substr(2);
    $attr.package.HOW.index{ $index-name } = [ $attr ];
}

multi trait_mod:<is> (Attribute $attr, :@related!) is export {
    my ($relationship-name, $schema-ref) = |@related;
    $attr does ModelDB::RelationshipSetup[$relationship-name, $schema-ref];
}

package EXPORTHOW {
    package DECLARE {
        constant model = MetamodelX::DBModelHOW;
    }
}

