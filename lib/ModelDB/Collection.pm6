use v6;

unit package ModelDB;

role Collection {
    has %.search;

    method all() { ... }
}

