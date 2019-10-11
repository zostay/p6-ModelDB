NAME
====

ModelDB - an MVP ORM

SYNOPSIS
========

    use DBIish;
    use ModelDB;

    module Model {
        use ModelDB::ModelBuilder;

        model Person {
            has Int $.person-id is column is primary;
            has Str $.name is column is rw
            has Int $.age is column is rw;
            has Str $.favorite-color is column is rw;
        }

        model Pet {
            has Str $.pet-id is column is primary;
            has Str $.name is column is rw;
            has Str $.animal is column is rw;
        }
    }

    class Schema is ModelDB::Schema {
        use ModelDB::SchemaBuilder;

        has ModelDB::Table[Person] $.persons is table;
        has ModelDB::Table[Pet] $.pets is table;
    }

    my $dbh = DBIish.connect('SQLite', :database<db.sqlite3>);
    my $schema = Schema.new(:$dbh);

    my $person = $schema.persons.create(%(
        name           => 'Steve',
        age            => 9,
        favorite-color => 'cyan',
    ));

    $person.name           = 'Alex';
    $person.age            = 4;
    $person.favorite-color = 'green';

    $schema.persons.update($person);

    my $by-id = $schema.pets.find(pet-id(1));
    my @cats = $schema.pets.search(:animal<cat>).all;

DESCRIPTION
===========

This is a minimalist object relational mapping tool. It helps with mapping your database objects into Perl from an RDBMS. I am experimenting with this API to see what I can learn about RDBMS patterns, problems, and specific issues as related to Perl 6.

As such, this is highly experimental and I make no promises as regards the API. Though, I do use it in some production-ish code, so I don't want to change too much too fast.

My intent, though, is to use what I learn here to build a different library in a different namespace that does what I really want based on what I learn here.

My goals include:

over
====



Pod::Defn<140722687036832>

Pod::Defn<140722687036776>

Pod::Defn<140722687036720>

Pod::Defn<140722687036664>

Pod::Defn<140722691871336>

back
====



Performance and multiple RDBMS support are anti-goals. This will likely only support MySQL (and forks) and SQLite because that's what I care about. I do not plan to make performance improvements unless required and I especially do not intend to add any optimizations that harm code readability of even the internals unless required.

