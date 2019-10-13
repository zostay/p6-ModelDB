use v6.d;

unit package ModelDB;

=begin pod

=head1 NAME

ModelDB::Column - information about a table column in a model

=head1 DESCRIPTION

A column describes how to load and save data to and from a particular table column.

=head1 METHODS

=head2 method when-loading

    has &.when-loading

This is a reference to a callback that will be called when loading the calling to transform the serialized data into a Perl data structure.

=head2 method when-saving

    has &.when-saving

This is a reference to a callback that will be called when saving the model to transform teh Perl data structure back into a serialized form.

=head2 method column-name

    method column-name(--> Str)

This returns the name of the column in the RDBMS.

=head2 method load-filter

    method load-filter($v --> Any)

This method applies the L<#method when-loading> filter or falls back to the L<#method default-load-filter>.

=head2 method default-load-filter

    method default-load-filter($v --> Any)

This performs generic transformation of data from a serialized form to a Perl data structure for the common cases.

=head2 method save-filter

    method save-filter($v --> Any)

This method applies the L<#method when-saving> filter or falls back to the L<#method default-save-filter>.

=head2 method default-save-filter

    method default-save-filter($v --> Any)

This performs generic transform of data from a Perl data structure to a serialized form for the common cases.

=end pod

role Column[$column-name] {
    has &.when-loading;
    has &.when-saving;

    method column-name() { $column-name }

    method getter-name() { self.name.substr(2) }

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

                # AUCHTUNG! This is technically DB dependent, but it will work
                # for any database I personally am likely to use. Oracle can be
                # sewed close with yarn and burned for all I care.
                when DateTime {
                    my $iso = $v.Str.trans(' ' => 'T').substr(0,19) ~ 'Z';
                    DateTime.new($iso)
                }
                when Date { Date.new(~$v) }

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

                # AUCHTUNG! This is technically DB dependent, but it will work
                # for any database I personally am likely to use. Oracle can be
                # covered in yarn for all I care.
                #
                # Also, this loses TZ and nanos, if you care
                when DateTime { $v.utc.Str.trans('T' => ' ').subst(/'.' \d+ Z$/, '') }
                when Date { ~$v }

                default { ~$v }
            }
        }
        else {
            Str
        }
    }
}

