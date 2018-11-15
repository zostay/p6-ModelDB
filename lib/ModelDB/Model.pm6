use v6;

unit package ModelDB;

use ModelDB::Column;

class Model {
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

