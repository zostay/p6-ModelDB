use v6.d;

unit package ModelDB;

use ModelDB::Column;
use ModelDB::Object;

=begin pod

=head1 NAME

ModelDB::Model - This is the base class for all models

=head1 DESCRIPTION

This class is inherited by every object declared with the C<model> keyword. It provides some common features to all model classes.

=head1 METHODS

=head2 method save-id

    method save-id($id)

Sets the primary key field. This method should not be called except by ModelDB components. It is only called when a row is created.

=end pod

class Model does ModelDB::Object {
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

    method create-values(--> Hash) {
        my $id-column-attr-name = self.HOW.id-column;
        % = self.^columns
            .grep({ .name ne $id-column-attr-name })
            .map(-> $col {
                my $getter = $col.name.substr(2);
                my $value  = $col.save-filter(self."$getter"());
                $col.column-name => $value;
            });
    }
}

