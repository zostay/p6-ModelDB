use v6;

use MetamodelX::DBModelHOW;
use ModelDB::Collection;
use ModelDB::Column;
use ModelDB::Model;
use ModelDB::RelationshipSetup;
use ModelDB::Schema;
use ModelDB::Table;
use ModelDB::TableBuilder;

module ModelDB {}

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

