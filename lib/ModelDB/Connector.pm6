use v6.d;

unit package ModelDB;

use DBIish;

class Connector {
    my class Connection {
        has $!dbh;
        has $.connect-args;

        method !connect() {
            DBIish.connect(|$!connect-args);
        }

        method dbh() {
            $!dbh //= self!connect();
        }
    }

    has UInt $.max-connections = 1;
    has UInt $.tries = 2;

    has Capture $.connect-args;

    has %!in-use;
    has Channel $!connections .= new;

    submethod TWEAK() {
        for ^$!max-connections {
            $!connections.send: Connection.new(:$!connect-args);
        }
    }

    method acquire() {
        my $connection = await $!connections;
        %!in-use{ $connection.dbh.WHICH } = $connection;
        $connection.dbh;
    }

    method release($dbh) {
        my $connection = %!in-use{ $dbh.WHICH }:delete;
        $!connections.send: $connection;
    }

    method try-with($dbh is rw, &code) {
        my $result;

        try {
            for ^$!tries {
                $result := code($dbh);
                last;

                CATCH {
                    when X::DBDish::DBError {
                        %!in-use{ $dbh.WHICH }:delete;
                        my $connection = Connection.new(:$!connect-args);
                        %!in-use{ $connection.dbh.WHICH } = $connection;
                        $dbh = $connection.dbh;
                    }
                }
            }
        }

        $result;
    }

    method run(&code) {
        my $dbh = self.acquire;

        LEAVE self.release($dbh);

        self.try-with($dbh, &code);
    }

    method last-insert-rowid($dbh) {
        my $sth = do given $dbh {
            use DBDish::SQLite::Connection;
            use DBDish::mysql::Connection;

            when DBDish::SQLite::Connection {
                $dbh.prepare('SELECT last_insert_rowid()');
            }
            when DBDish::mysql::Connection {
                $dbh.prepare('SELECT last_insert_id()');
            }
            default {
                die "Unsupported database error";
            }
        }

        $sth.execute;
        $sth.fetchrow[0];
    }
}

=begin pod

=head1 NAME

ModelDB::Connector - manages the connections to the database

=head1 DESCRIPTION

This provides tooling used inside of ModelDB for managing database connections, recovering from lost connections, etc. This is still pretty immature so I don't really want to expose and document the innards yet.

=end pod
