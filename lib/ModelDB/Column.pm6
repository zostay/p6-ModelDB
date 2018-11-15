use v6;

unit package ModelDB;

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

