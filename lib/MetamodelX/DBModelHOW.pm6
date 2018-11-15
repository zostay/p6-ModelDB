use v6;

use ModelDB::Column;
use ModelDB::Model;

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

