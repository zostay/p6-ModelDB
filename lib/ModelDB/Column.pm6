use v6;

unit package ModelDB;

=begin pod

=head1 DESCRIPTION

A column describes how to load and save data to and from a particular table column.

=head1 METHODS

=head2 method when-loading

    has &.when-loading

=head2 method when-saving

    has &.when-saving

=head2 method column-name

    method column-name(--> Str)

=head2 method load-filter

    method load-filter($v --> Any)

=head2 method default-load-vilter

    method default-load-filter($v --> Any)

=head2 method save-filter

    method save-filter($v --> Any)

=head2 method default-save-filter

    method default-save-filter($v --> Any)

=end pod

role Column[$column-name] {
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

