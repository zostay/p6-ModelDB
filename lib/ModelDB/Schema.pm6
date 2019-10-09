use v6;

unit package ModelDB;

use ModelDB::Connector;

=begin pod

=head1 NAME

ModelDB::Schema - a schema ties models to tables on a particular DB connector

=head2 SYNOPSIS

    use ModelDB::SchemaBuilder;
    use MyApp::Model;

    class MyApp::Schema is ModelDB::Schema {
        has ModelDB::Table[MyApp::Model::Thing] $.things is table('thing');
    }

    my MyApp::Schema $schema .= new(
        connect-args => \('mysql', :host<db.example.com>, :port(3306), :database<db_of_things>),
    );

    my @things = $schema.things.search.all;

=head1 DESCRIPTION

A schema is a collection of models.

Each model is tied to a table. A model object may be tied to multiple tables if they have the same RDBMS schema.

When instantiated, a schema object is tied to a specific database connection. Multiple schemas can be created to connect to different databases. This can be useful if you have read replicas, for example.

=head1 METHODS

=head2 method connect

    has Capture $.connect-args is required

These are the arguments to pass to the C<connect> method of L<DBIish> when connecting to the database.

=head2 method connector

    method connector(--> ModelDB::Connector)

This is the L<ModelDB::Connector> object that manages the database connections.

=end pod

class Schema {
    has ModelDB::Connector $!connector;

    has UInt $.max-connections = 16;
    has UInt $.tries = 2;
    has Capture $.connect-args is required;

    method connector(--> ModelDB::Connector) {
        $!connector //= ModelDB::Connector.new(
            :$.max-connections, :$.tries, :$.connect-args,
        );
    }
}

